# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-06
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
# This script monitors the backup configuration of the Veeam Backup & Replication server 
# and sends alerts based on the backup status. It analyzes recent sessions 
# according to the time defined by the $RPO (Recovery Point Objective) parameter, 
# and reports any session that is in warning or has failed.
#
# Please refer to the GitHub repository for more details and documentation.
#
# ====================================================================

#region Parameters
param (
    [int]$RPO = 24  # RPO (Recovery Point Objective) in hours
)
#endregion

#region Validate Parameters
# Validate the $RPO parameter to ensure it's a positive integer
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}
#endregion

#region Functions

# Extracts the version from script content
function Get-VersionFromScript {
    param ([string]$Content)
    if ($Content -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]
    }
    return $null
}

# Functions for exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Ensures connection to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"
    $OpenConnection = (Get-VBRServerSession).Server

    if ($OpenConnection -ne $vbrServer) {
        Disconnect-VBRServer
        Try {
            Connect-VBRServer -server $vbrServer -ErrorAction Stop
        } Catch {
            Exit-Critical "Unable to connect to the VBR server."
        }
    }
}

#endregion

#region Update Script
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_BackupConfig.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path

# Extract and compare versions to update the script if necessary
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -Content $localScriptContent

$remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -UseBasicParsing
$remoteVersion = Get-VersionFromScript -Content $remoteScriptContent

if ($localVersion -ne $remoteVersion) {
    try {
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
        Write-Warning "Failed to update the script"
    }
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

try {
    $configBackup = Get-VBRConfigurationBackupJob

    If ($configBackup.LastResult -eq "Failed" -or ($configBackup.NextRun -gt (Get-Date).AddHours($RPO))) {
        Exit-Critical "Backup configuration has failed or the next run is scheduled more than $RPO hours ahead."
    } ElseIf ($configBackup.LastResult -eq "Warning") {
        Exit-Warning "Backup configuration is in a warning state."
    } ElseIf (-not $configBackup.EncryptionOptions.Enabled) {
        Exit-Warning "Backup configuration is not encrypted."
    } ElseIf ($configBackup.LastResult -eq "Success" -and $configBackup.EncryptionOptions.Enabled -and $configBackup.NextRun -lt (Get-Date).AddHours($RPO)) {
        Exit-Ok "Backup Configuration is successful on the $($configBackup.Target) repository. Backup is Encrypted, and the next run is scheduled for $($configBackup.NextRun.ToString("dd/MM/yyyy"))."
    } Else {
        Exit-Unknown "Unknown: Backup configuration status."
    }
}
catch {
    Exit-Critical "An error occurred: $_"
}
