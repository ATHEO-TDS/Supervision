# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
# This script is designed to monitor backup jobs in Veeam Backup & Replication 
# and send alerts based on the backup status. It analyzes recent sessions 
# according to the time defined by the $RPO (Recovery Point Objective) parameter, 
# and reports any sessions that are in warning or have failed.
#
# Please refer to the GitHub repository for more details and documentation.
#
# ====================================================================

#region Parameters
param (
    [int]$RPO = 24 # Recovery Point Objective (hours)
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

# Retrieves all backup sessions from the past $RPO hours
    function GetVBRBackupSession {
        $Type = @("Backup")
        foreach ($i in ([Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetAll())  | Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -eq "Working") -and $_.JobType -in $Type})
    { 
                    $sessionProps = @{ 
                    JobName = $i.JobName
                    JobType = $i.JobType
                    SessionId = $i.Id
                    SessionCreationTime = $i.CreationTime
                    SessionEndTime = $i.EndTime
                    SessionResult = $i.Result.ToString()
                    State = $i.State.ToString()
                    Result = $i.Result
                    Failures = $i.Failures
                    Warnings = $i.Warnings
                    WillBeRetried = $i.WillBeRetried
            }  
            New-Object PSObject -Property $sessionProps 
        }
    }
#endregion

#region Update Script
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_BackupSessions.ps1"
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

#region Variables
$criticalSessions = @()
$warningSessions = @()
$allSessionDetails = @()
$statusMessage = ""
#endregion

try {
    # Retrieve all backup sessions
    $sessListBk = GetVBRBackupSession | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1}

    if (-not $sessListBk) {
        Exit-Unknown "No backup session found."
    }
        
    foreach ($session in $sessListBk) {
        $sessionName = $session.JobName
        $quotedSessionName = "'$sessionName'"

        $sessionResult = switch ($session.Result) {
            "Success" { 0 }
            "Warning" { 1 }
            "Failed" { 2 }
            default { Exit-Critical "Unknown session result: $($session.Result)" }
        }

        # Append session details
        $allSessionDetails += "$quotedSessionName=$sessionResult;1;2"

        if ($sessionResult -ge 2) {
            $criticalSessions += $sessionName
        } elseif ($sessionResult -ge 1) {
            $warningSessions += $sessionName
        }
    }

    # Construct the status message
    if ($criticalSessions.Count -gt 0) {
        $statusMessage = "At least one failed backup session: " + ($criticalSessions -join " / ")
        $status = "CRITICAL"
    } elseif ($warningSessions.Count -gt 0) {
        $statusMessage = "At least one backup session is in a warning state: " + ($warningSessions -join " / ")
        $status = "WARNING"
    } else {
        $statusMessage = "All backup sessions are successful ($($allSessionDetails.Count))"
        $status = "OK"
    }

    # Construct the statistics message
    $statisticsMessage = $allSessionDetails -join " "
    # Construct the final message
    $finalMessage = "$statusMessage|$statisticsMessage"

    # Exit with the appropriate status
    switch ($status) {
        "CRITICAL" { Exit-Critical $finalMessage }
        "WARNING" { Exit-Warning $finalMessage }
        "OK" { Exit-OK $finalMessage }
    }
}Catch{
    Exit-Critical "An error occurred: $_"
}
