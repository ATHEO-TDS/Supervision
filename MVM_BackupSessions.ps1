# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-19
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# DESCRIPTION:
# This PowerShell script is designed to monitor Veeam Backup & Replication (VBR) backup job sessions.
# It checks whether the sessions meet a specified Recovery Point Objective (RPO), which is the maximum allowable
# time in hours since the last successful backup. The script categorizes backup sessions into three states:
#
# PARAMETERS:
# - RPO: Defines the backup analysis period (in hours). Default is 24 hours.
# - ExcludedJobs: A comma-separated list of job names to exclude from monitoring.
#
# RETURNS:
# - Critical: At least one session has failed or is in an unexpected state.
# - Warning: At least one session is in a warning state.
# - OK: All sessions are successful or still running.
# - Unknown: No sessions found to evaluate.
#
# ====================================================================

#region Parameters
param (
    [int]$RPO = 24, # Recovery Point Objective (hours)
    [string]$ExcludedJobs = "" # Comma-separated list of backup jobs to exclude from the monitoring process
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

#region Validate Parameters
# Validate that the RPO parameter is a positive integer
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$ExcludedJobsArray = $ExcludedJobs -split ','  # Parse the excluded jobs list into an array
$criticalSessions = @()  # Array to store sessions that are critical
$warningSessions = @()  # Array to store sessions that are in a warning state
$allSessionDetails = @()  # Array to store details of all sessions
$statusMessage = ""  # Variable to hold the overall status message
#endregion

try {
    # Retrieve all backup sessions
    $sessListBk = GetVBRBackupSession | Where-Object { -not ($_.JobName -in $ExcludedJobsArray) } | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1}

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

         # Append the session's status to the session details array
         $allSessionDetails += "$quotedSessionName=$sessionResult;1;2"

        # Categorize the session based on its result
         if ($sessionResult -ge 2) {
            $criticalSessions += $sessionName
        } elseif ($sessionResult -ge 1) {
            $warningSessions += $sessionName
        }
    }

    # Construct the status message based on session results
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
    # Construct the final message that will be reported
    $finalMessage = "$statusMessage|$statisticsMessage"

    # Exit with the appropriate status code and message code and message
    switch ($status) {
        "CRITICAL" { Exit-Critical $finalMessage }
        "WARNING" { Exit-Warning $finalMessage }
        "OK" { Exit-OK $finalMessage }
    }
} Catch {
    Exit-Critical "An error occurred: $($_.Exception.Message)"
}