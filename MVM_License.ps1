# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# DESCRIPTION:
# This PowerShell script is designed to monitor Veeam Backup & Replication (VBR) licenses.
# It checks the license type, expiration date, and the number of days remaining before expiration.
#
# PARAMETERS:
# - Warning: Defines the threshold (in days) for issuing a "Warning" - Default is 90 days.
# - Critical: Defines the threshold (in days) for issuing a "Critical" - Default is 30 days.
#
# RETURNS:
# - OK: License is valid and has more days remaining than the defined thresholds.
# - Warning: License has fewer days remaining than the "Warning" threshold but more than "Critical".
# - Critical: License has fewer days remaining than the "Critical" threshold or is expired.
# - Unknown: If there is an error or the license type cannot be determined.
#
# ====================================================================

#region Parameters
param (
    [int]$Warning = 90,  # Number of days for issuing a Warning status.
    [int]$Critical = 30  # Number of days for issuing a Critical status.
)
#endregion

#region Functions
# Functions for returning exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Function to connect to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"  # Veeam Backup & Replication server address
    $credentialPath = ".\scripts\MyVeeamMonitoring\key.xml"  # Path to credentials file for connection
    
    # Check if a connection to the VBR server is already established
    $OpenConnection = (Get-VBRServerSession).Server
    
    if ($OpenConnection -ne $vbrServer) {
        # Disconnect existing session if connected to a different server
        Disconnect-VBRServer
        
        if (Test-Path $credentialPath) {
            # Load credentials from XML file
            try {
                $credential = Import-Clixml -Path $credentialPath
                Connect-VBRServer -server $vbrServer -Credential $credential -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to load credentials from the XML file."
            }
        } else {
            # Connect without credentials if file does not exist
            try {
                Connect-VBRServer -server $vbrServer -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to connect to the VBR server."
            }
        }
    }
}

# Retrieves license information and calculates expiration details
Function Get-VeeamSupportDate {
    # Fetch installed license details
    $licenseInfo = Get-VBRInstalledLicense

    # Determine license type and expiration date
    $type = $licenseInfo.Type
    $date = $null

    switch ($type) {
        'Perpetual'    { $date = $licenseInfo.SupportExpirationDate } # Perpetual licenses have a support expiration date
        'Evaluation'   { $date = $null }  # Evaluation licenses don't expire
        'Subscription' { $date = $licenseInfo.ExpirationDate } # Subscription licenses have an expiration date
        'Rental'       { $date = $licenseInfo.ExpirationDate } # Rental licenses have an expiration date
        'NFR'          { $date = $licenseInfo.ExpirationDate } # Not-for-Resale licenses have an expiration date
        default        { Exit-Critical "Unknown license type: $type" } # Handle unknown license types
    }

    # Return a custom object with license details
    [PSCustomObject]@{
        LicType    = $type
        ExpDate    = if ($date) { $date.ToShortDateString() } else { "No Expiration" }
        DaysRemain = if ($date) { ($date - (Get-Date)).Days } else { "Unlimited" }
    }
}
#endregion

#region Validate Parameters
# Ensure both thresholds are positive integers
if ($Critical -le 0 -or $Warning -le 0) {
    Exit-Critical "Invalid parameter values: Both 'Warning' and 'Critical' must be greater than 0. Please provide valid values for both."
}

# Ensure the Warning threshold is greater than the Critical threshold
if ($Warning -le $Critical) {
    Exit-Critical "Invalid parameter values: 'Warning' must be greater than 'Critical'. Please ensure that 'Warning' > 'Critical'."
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

try {
    # Retrieve license details
    $licenseInf = Get-VeeamSupportDate

    if (-not $licenseInf) {
        # Exit with Unknown status if license information is unavailable
        Exit-Unknown "Unable to retrieve Veeam license information." 
    }
    
    # Determine license status based on days remaining
    if ($licenseInf.LicType -eq "Evaluation") { 
        $licenseStatus = "OK" # Evaluation licenses are always considered OK
    } elseif ($licenseInf.DaysRemain -lt $Critical) { 
        $licenseStatus = "Critical" # License is about to expire or expired
    } elseif ($licenseInf.DaysRemain -lt $Warning) { 
        $licenseStatus = "Warning" # License is approaching expiration
    } else { 
        $licenseStatus = "OK" # License is valid
    }

    # Handle the status and provide output
    switch ($licenseStatus) {
        "OK"        { Exit-OK "Support License Days Remaining: $($licenseInf.DaysRemain)." }
        "Warning"   { Exit-Warning "Support License Days Remaining: $($licenseInf.DaysRemain)." }
        "Critical"  { Exit-Critical "Support License Days Remaining: $($licenseInf.DaysRemain)." }
        default     { Exit-Critical "Support License is expired or in an invalid state." }
    }
} Catch {
    # Handle any errors during execution
    Exit-Critical "An error occurred: $($_.Exception.Message)"
}