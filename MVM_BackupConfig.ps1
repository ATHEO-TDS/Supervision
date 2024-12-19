# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-19
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
# 
# DESCRIPTION:
# This PowerShell script is designed to monitor Veeam Backup & Replication (VBR) configuration backup.
# It checks whether the configuration backup is successful, in a warning state, or has failed. 
# The script also ensures that the backup is encrypted and that the next scheduled backup is within the acceptable time 
# Defined by the Recovery Point Objective (RPO). These are the possible return values :
#
# PARAMETERS:
# - RPO: Defines the backup analysis period (in hours). Default is 24 hours.
#
# RETURNS:
# - Critical: Backup configuration has failed or the next backup configuration run is scheduled more than $RPO hours ahead.
# - Warning: Backup configuration is in a warning state or the backup configuration is not encrypted.
# - OK: Backup configuration is successful, encrypted, and scheduled for the next run within the $RPO hours window.
#
# ====================================================================

#region Parameters
param (
    [int]$RPO = 24  # RPO (Recovery Point Objective) in hours
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
#endregion

#region Validate Parameters
# Validate the $RPO parameter to ensure it's a positive integer
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

try {
    # Retrieve the current configuration backup job information
    $configBackup = Get-VBRConfigurationBackupJob

    # Check if the last backup configuration failed
    If ($configBackup.LastResult -eq "Failed") {
        Exit-Critical "Backup configuration has failed."
    } 
    # Check if the next scheduled backup run exceeds the RPO window
    ElseIf (($configBackup.NextRun -gt (Get-Date).AddHours($RPO))) {
        Exit-Warning "The next backup configuration run is scheduled more than $RPO hours ahead."
    } 
    # Check if the last backup configuration is in a warning state
    ElseIf ($configBackup.LastResult -eq "Warning") {
        Exit-Warning "Backup configuration is in a warning state."
    } 
    # Check if the backup configuration is not encrypted
    ElseIf (-not $configBackup.EncryptionOptions.Enabled) {
        Exit-Warning "Backup configuration is not encrypted."
    } 
    # If the backup configuration is successful, encrypted, and within the RPO window
    ElseIf ($configBackup.LastResult -eq "Success" -and $configBackup.EncryptionOptions.Enabled -and $configBackup.NextRun -lt (Get-Date).AddHours($RPO)) {
        Exit-OK "Backup Configuration is successful on the $($configBackup.Target) repository. Backup is Encrypted, and the next run is scheduled for $($configBackup.NextRun.ToString("dd/MM/yyyy"))."
    } 
    # If the backup configuration status is unknown, report as such
    Else {
        Exit-Unknown "Backup configuration status is unknown"
    }
} Catch {
    Exit-Critical "An error occurred: $($_.Exception.Message)"

}
