# ==================================================================== 
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-06
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
# This script monitors Veeam Backup Agent backup sessions and reports their status 
# to an external monitoring system. It checks backup sessions within a specified 
# time window (RPO) and categorizes their status as successful, warning, or 
# failed. The script updates itself if a new version is available from the GitHub repository.
#
# ====================================================================

#region Arguments
param (
    [int]$RPO  # RPO (Recovery Point Objective) in hours
)
#endregion

#region Update Script
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_BackupAgentSessions.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path

# Extract and compare versions to update the script if necessary
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -Content $localScriptContent

$remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -Headers $headers -UseBasicParsing
$remoteVersion = Get-VersionFromScript -Content $remoteScriptContent

if ($localVersion -ne $remoteVersion) {
    try {
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
        Write-Warning "Failed to update the script"
    }
}
#endregion

#region Functions

# Function to extract the version from the script content
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

#endregion

#region Connection to VBR Server

# Ensure connection to the VBR server
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

Connect-VBRServerIfNeeded
#endregion

#region Monitor Backup Agent Sessions

# Get and filter Agent Backup Sessionsfor the specified RPO window
function Get-BackupSessions {
    param (
        [int]$RPO
    )

    return Get-VBRComputerBackupJobSession | Where-Object {
        ($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -eq "Working")
    } | Group-Object JobName | ForEach-Object {
        $_.Group | Sort-Object EndTime -Descending | Select-Object -First 1
    }
}

$sessListEp = Get-BackupSessions -RPO $RPO
if (-not $sessListEp) {
    Exit-Unknown "No agent backup session found."
}

# Process the Agent Backup Sessionsand categorize them by result
$allSessionDetails = @()
$criticalSessions = @()
$warningSessions = @()

foreach ($session in $sessListEp) {
    $sessionName = $session.JobName
    $quotedSessionName = "'$sessionName'"

    $sessionResult = switch ($session.Result) {
        "Success" { 0 }
        "Working" { 0.5 }
        "Warning" { 1 }
        "Failed" { 2 }
        default { Exit-Critical "Unknown session result: $($session.Result)" }
    }

    $allSessionDetails += "$quotedSessionName=$sessionResult;1;2"

    if ($sessionResult -ge 2) {
        $criticalSessions += $sessionName
    } elseif ($sessionResult -ge 1) {
        $warningSessions += $sessionName
    }
}

#endregion

#region Final Status Report

# Determine the final status based on session results
$statusMessage = ""
if ($criticalSessions.Count -gt 0) {
    $statusMessage = "At least one failed agent backup session: " + ($criticalSessions -join " / ")
    $status = "CRITICAL"
} elseif ($warningSessions.Count -gt 0) {
    $statusMessage = "At least one agent backup session is in a warning state: " + ($warningSessions -join " / ")
    $status = "WARNING"
} else {
    $statusMessage = "All agent backup sessions are successful ($($allSessionDetails.Count))"
    $status = "OK"
}

$statisticsMessage = $allSessionDetails -join " "
$finalMessage = "$statusMessage|$statisticsMessage"

# Exit with the appropriate status
switch ($status) {
    "CRITICAL" { Exit-Critical $finalMessage }
    "WARNING" { Exit-Warning $finalMessage }
    "OK" { Exit-OK $finalMessage }
}
#endregion
