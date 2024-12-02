# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.1
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
# Ce script permet de surveiller les tâches de sauvegarde dans Veeam Backup & Replication 
# et d'envoyer des alertes basées sur le statut des sauvegardes. Il analyse les sessions 
# récentes en fonction de l'heure définie par le paramètre $RPO (Recovery Point Objective), 
# et signale toute session étant en avertissement ou ayant échoué.
#
# L'objectif est d'assurer un suivi efficace des sauvegardes et de signaler rapidement via 
# un outil de monitoring tout problème éventuel nécessitant une attention particulière.
#
# Veuillez consulter le dépôt GitHub pour plus de détails et de documentation.
#
# ====================================================================

#region Arguments
param (
    [int]$RPO
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_BackupSessions.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path
#endregion

#region Functions      
    #region Fonction Get-VersionFromScript
        function Get-VersionFromScript {
            param (
                [string]$scriptContent
            )
            # Recherche une ligne contenant '#Version X.Y.Z'
            if ($scriptContent -match "# Version\s*:\s*([\d\.]+)") {
                return $matches[1]
            } else {
                Write-Error "Impossible de trouver la version dans le script."
                return $null
            }
        }
    #endregion

    #region Fonctions Exit NRPE
        function Exit-OK {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "OK - $message"
            }
            exit 0
        }

        function Exit-Warning {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "WARNING - $message"
            }
            exit 1
        }

        function Exit-Critical {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "CRITICAL - $message"
            }
            exit 2
        }

        function Exit-Unknown {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "UNKNOWN - $message"
            }
            exit 3
        }
    #endregion

    #region Fonction GetVBRBackupSession
        function GetVBRBackupSession {
            $Type = @("Backup")
            foreach ($i in ([Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetAll())  | Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$HourstoCheck) -or $_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck) -or $_.State -eq "Working") -and $_.JobType -in $Type})
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
#endregion

#region Update 
# --- Extraction de la version locale ---
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -scriptContent $localScriptContent

# --- Récupération du script distant ---
$remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -Headers $headers -UseBasicParsing

# --- Extraction de la version distante ---
$remoteVersion = Get-VersionFromScript -scriptContent $remoteScriptContent

# --- Comparaison des versions et mise à jour ---
if ($localVersion -ne $remoteVersion) {
    try {
        # Écrase le script local avec le contenu distant
        $remoteScriptContent | Set-Content -Path $localScriptPath -Force
    } catch {
    }
}
#endregion

#endregion

#region Variables
$vbrServer = "localhost"
$HourstoCheck = $RPO
$criticalSessions = @()
$warningSessions = @()
$allSessionDetails = @()
#endregion

#region Connect to VBR server
$OpenConnection = (Get-VBRServerSession).Server
If ($OpenConnection -ne $vbrServer){
    Disconnect-VBRServer
    Try {
        Connect-VBRServer -server $vbrServer -ErrorAction Stop
    } Catch {
        Exit-Critical "Unable to connect to the VBR server."
    exit
    }
}
#endregion

try {
    # Get all backup session
    $sessListBk = @(GetVBRBackupSession)
    $sessListBk = $sessListBk | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1}
    if (-not $sessListBk) {
        Exit-Unknown "No Backup Session found."
    }
        
    # Iterate over each collection
    foreach ($session in $sessListBk) {
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
        $statusMessage = "At least one failed backup session : " + ($criticalSessions -join " / ")
        $status = "CRITICAL"
    } elseif ($warningSessions.Count -gt 0) {
        $statusMessage = "At least one backup session is in a warning state : " + ($warningSessions -join " / ")
        $status = "WARNING"
    } else {
        $statusMessage = "All backup sessions are successful ($sessionsCount)"
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
