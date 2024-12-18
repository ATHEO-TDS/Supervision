# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
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

# Retrieves all replication sessions from the past $RPO hours
function GetVBRBackupSession {
    $Type = @("Replica")
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
    # Retrieve all replica sessions
    $sessListRp = GetVBRBackupSession | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1}

    if (-not $sessListRp) {
        Exit-Unknown "No replication session found."
    }
        
    foreach ($session in $sessListRp) {
        $sessionName = $session.JobName
        $quotedSessionName = "'$sessionName'"

        $sessionResult = switch ($session.Result) {
            "Successful" { 0 }
            "Running" { 0.5 }
            "Warning" { 1 }
            "Fails" {1.5}
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
        $statusMessage = "At least one failed replication session: " + ($criticalSessions -join " / ")
        $status = "CRITICAL"
    } elseif ($warningSessions.Count -gt 0) {
        $statusMessage = "At least one replication session is in a warning state: " + ($warningSessions -join " / ")
        $status = "WARNING"
    } else {
        $statusMessage = "All replication sessions are successful ($($allSessionDetails.Count))"
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
