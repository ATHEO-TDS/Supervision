# ====================================================================
# Author : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.2
# Creation Date : 2024-11-29
# Last Updated : 2024-12-02
# GitHub Repository : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
# This script monitors backup copy jobs in Veeam Backup & Replication and sends alerts 
# based on the job status. It analyzes recent sessions according to the specified $RPO 
# (Recovery Point Objective) parameter and reports any jobs in a warning or failed state.
#
# For additional details and documentation, refer to the GitHub repository.
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
# Functions for exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Ensures connection to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"
    $credentialPath = ".\key.xml"
    
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

# Retrieves all backup copy sessions from the past $RPO hours
function GetVBRBackupCopySession {
    $JobType = @("SimpleBackupCopyWorker","SimpleBackupCopyPolicy","BackupSync")
    $copyjob = [Veeam.Backup.Core.CBackupJob]::GetAllBackupSyncAndTape() | Where-Object {$_.JobType -in $JobType}
    foreach ($i in ($copyjob.FindLastSession() | Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -match "Working|Idle")})) { 
        $sessionProps = @{ 
            JobName = $i.JobName
            JobType = $i.JobType
            SessionId = $i.Id
            SessionCreationTime = $i.CreationTime
            SessionEndTime = $i.EndTime
            SessionResult = $i.Result.ToString()
            State = $i.State.ToString()
            Result = $i.Result
            Failures = $i.info.Failures
            Warnings = $i.info.Warnings
            WillBeRetried = $i.WillBeRetried
        }  
        New-Object PSObject -Property $sessionProps 
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
    # Retrieve all backup copy sessions
    $sessListBc = GetVBRBackupCopySession | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1 }

    if (-not $sessListBc) {
        Exit-Unknown "No backup copy session found."
    }
        
    foreach ($session in $sessListBc) {
        $sessionName = $session.JobName
        $quotedSessionName = "'$sessionName'"

        $sessionResult = switch ($session.Result) {
            "Success" { 0 }
            "Idle" { 0.5 }
            "Working" { 0.5 }
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
        $statusMessage = "At least one failed backup copy session: " + ($criticalSessions -join " / ")
        $status = "CRITICAL"
    } elseif ($warningSessions.Count -gt 0) {
        $statusMessage = "At least one backup copy session is in a warning state: " + ($warningSessions -join " / ")
        $status = "WARNING"
    } else {
        $statusMessage = "All backup copy sessions are successful ($($allSessionDetails.Count))"
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
