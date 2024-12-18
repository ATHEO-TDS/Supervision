# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
# This script monitors the status of licenses installed on a Veeam Backup & Replication server.
# It checks the license type, expiration date, and the number of days remaining before expiration.
# Warning and critical thresholds can be configured to generate alerts based on the remaining days.
#
# ====================================================================

#region Parameters
param (
    [int]$Warning = 90,
    [int]$Critical = 30
)
#endregion

#region Validate Parameters
if ($Warning -le $Critical) {
    Exit-Critical "Invalid parameter values: 'Warning' must be greater than 'Critical'. Please ensure that 'Warning' > 'Critical'."
}

if ($Critical -le 0 -or $Warning -le 0) {
    Exit-Critical "Invalid parameter values: Both 'Warning' and 'Critical' must be greater than 0. Please provide valid values for both."
}
#endregion

#region Functions
# Functions for exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Ensures connection to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"
    .\key.xml"
    $OpenConnection = (Get-VBRServerSession).Server
    if ($OpenConnection -ne $vbrServer) {
        Disconnect-VBRServer
        if (Test-Path $credentialPath) {
            # Load credentials from the XML file
            try {
                $credential = Import-Clixml -Path $credentialPath
                Connect-VBRServer -server $vbrServer -Credential $credential -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to load credentials from the XML file."
            }
        } else {
            # Connect without credentials
            try {
                Connect-VBRServer -server $vbrServer -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to connect to the VBR server."
            }
        }
    }
}

# Retrieves license informations
Function Get-VeeamSupportDate {
    # Query for license info
    $licenseInfo = Get-VBRInstalledLicense

    # Extract license type
    $type = $licenseInfo.Type
    $date = $null

    # Determine expiration date based on license type
    switch ($type) {
        'Perpetual'    { $date = $licenseInfo.SupportExpirationDate }
        'Evaluation'   { $date = $null } # Evaluation licenses have no defined expiration
        'Subscription' { $date = $licenseInfo.ExpirationDate }
        'Rental'       { $date = $licenseInfo.ExpirationDate }
        'NFR'          { $date = $licenseInfo.ExpirationDate }
        default        { Exit-Critical "Unknown license type: $type" }
    }

    # Create custom object with details
    [PSCustomObject]@{
        LicType    = $type
        ExpDate    = if ($date) { $date.ToShortDateString() } else { "No Expiration" }
        DaysRemain = if ($date) { ($date - (Get-Date)).Days } else { "Unlimited" }
    }
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

try {
    # Retrieve license info
    $licenseInf = Get-VeeamSupportDate

    if (-not $licenseInf) {
        Exit-Unknown "Unable to retrieve Veeam license information." 
    }
    
    if ($licenseInf.LicType -eq "Evaluation") { $licenseStatus = "OK" }
        elseif ($licenseInf.DaysRemain -lt $Critical) { $licenseStatus = "Critical" }
        elseif ($licenseInf.DaysRemain -lt $Warning) { $licenseStatus = "Warning" }
        else { $licenseStatus = "OK" }

    switch ($licenseStatus) {
        "OK"        { Exit-OK "Support License Days Remaining: $($licenseInf.DaysRemain)." }
        "Warning"   { Exit-Warning "Support License Days Remaining: $($licenseInf.DaysRemain)." }
        "Critical"  { Exit-Critical "Support License Days Remaining: $($licenseInf.DaysRemain)." }
        default     { Exit-Critical "Support License is expired or in an invalid state." }
    }
}Catch{
    Exit-Critical "An error occurred: $_"
}