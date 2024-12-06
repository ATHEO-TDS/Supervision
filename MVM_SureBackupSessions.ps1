# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
#a tester
# ====================================================================

#region Parameters
param (
    [string]$RPO
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$remoteScriptURL = "$repoURL/MVM_SureBackupSessions.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path
#endregion

#region Functions      

# Function to extract version from a script file
function Get-ScriptVersion {
    param (
        [string]$ScriptContent
    )
    if ($ScriptContent -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]
    } else {
        return $null
    }
}

# Functions for NRPE-style exit codes
function Exit-OK {
    param ([string]$Message)
    Write-Host "OK - $Message"
    exit 0
}

function Exit-Warning {
    param ([string]$Message)
    Write-Host "WARNING - $Message"
    exit 1
}

function Exit-Critical {
    param ([string]$Message)
    Write-Host "CRITICAL - $Message"
    exit 2
}

function Exit-Unknown {
    param ([string]$Message)
    Write-Host "UNKNOWN - $Message"
    exit 3
}
#endregion

#region Script Update
# Fetch local script version
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-ScriptVersion -ScriptContent $localScriptContent

# Fetch remote script version
$remoteScriptContent = Invoke-RestMethod -Uri $remoteScriptURL -UseBasicParsing
$remoteVersion = Get-ScriptVersion -ScriptContent $remoteScriptContent

# Update script if versions differ
if ($localVersion -ne $remoteVersion) {
    try {
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
    }
}
#endregion

#region Connect to VBR Server
if ((Get-VBRServerSession).Server -ne $vbrServer) {
    Disconnect-VBRServer
    try {
        Connect-VBRServer -Server $vbrServer -ErrorAction Stop
    } catch {
        Exit-Critical "Unable to connect to VBR server."
    }
}
#endregion

try {
    # Get all surebackup sessions
    $sessListSb = Get-VBRSureBackupSession | Where-Object {$_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -ne "Stopped"}
    $sessListSb = $sessListSb | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object EndTime -Descending | Select-Object -First 1}

    if (-not $sessListSb) {
        Exit-Unknown "No surebackup session found."
    }
        
    # Iterate over each collection
    foreach ($session in $sessListSb) {
        $sessionName = $session.JobName
        $quotedSessionName = "'$sessionName'"

        $sessionResult = switch ($session.Result) {
            "Success" { 0 }
            "Warning" { 1 }
            "Failed" { 2 }
            default { Exit-Critical "Unknown session result : $($session.Result)"}  # Gérer les cas inattendus
        }

        # Append session details
        $allSessionDetails += "$quotedSessionName=$sessionResult;1;2"

        if ($sessionResult -eq 2) {
            $criticalSessions += "$sessionName"
        } elseif ($sessionResult -eq 1) {
            $warningSessions += "$sessionName"
        }
    }

    $sessionsCount = $allSessionDetails.Count

    # Construct the status message
    if ($criticalSessions.Count -gt 0) {
        $statusMessage = "At least one failed surebackup session : " + ($criticalSessions -join " / ")
        $status = "CRITICAL"
    } elseif ($warningSessions.Count -gt 0) {
        $statusMessage = "At least one surebackup session is in a warning state : " + ($warningSessions -join " / ")
        $status = "WARNING"
    } else {
        $statusMessage = "All surebackup sessions are successful ($sessionsCount)"
        $status = "OK"
    }

    # Construct the statistics message
    $statisticsMessage = $allSessionDetails -join " "

    # Construct the final message
    $finalMessage = "$statusMessage|$statisticsMessage"

    # Handle the final status
    switch ($status) {
        "CRITICAL" { Exit-Critical $finalMessage }
        "WARNING" { Exit-Warning $finalMessage }
        "OK" { Exit-OK $finalMessage }
    }

} catch {
    Exit-Critical "An error occurred: $_"
}