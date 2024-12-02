# ====================================================================
# Script PowerShell : Vérification et gestion des sessions de sauvegarde Veeam
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Description : Ce script vérifie l'état des sessions de sauvegarde Veeam
#               et retourne des messages d'alerte en fonction du statut des tâches.
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
# Ce script permet de surveiller les tâches de sauvegarde dans Veeam Backup & Replication
# et d'envoyer des alertes basées sur le statut des sauvegardes.
# Il analyse les sessions récentes en fonction de l'heure définie par le paramètre `$RPO`,
# en signalant toute session ayant échoué, étant en avertissement ou en échec et en attente de reprise.
#
# L'objectif est d'assurer un suivi efficace des sauvegardes et de signaler rapidement tout
# problème éventuel nécessitant une attention particulière.
#
# Veuillez consulter le dépôt GitHub pour plus de détails et de documentation.
#
# ====================================================================

#region Update Script
# Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/SDSup_Backup.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path

#region Arguments
param (
    [int]$RPO
)
#endregion

#region Functions
    #region Fonction Write-Log
        function Write-Log {
            param (
                [string]$File,
                [string]$Type,
                [string]$Message
            )
            # Chemin du fichier de log
            $logFile = ".\LOGS\$File.log"
            # Timestamp pour l'entrée de log
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            # Format du message de log
            $logMessage = "$timestamp - $Type - $Message"
            # Ajout du message au fichier de log
            Add-Content -Path $logFile -Value $logMessage
        }
    #endregion

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

    #region Fonctions Handle NRPE
        function Handle-OK {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "OK - $message"
            }
            exit 0
        }

        function Handle-Warning {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "WARNING - $message"
            }
            exit 1
        }

        function Handle-Critical {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "CRITICAL - $message"
            }
            exit 2
        }

        function Handle-Unknown {
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

# --- Extraction de la version locale ---
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -scriptContent $localScriptContent
if (-not $localVersion) {
    Write-Log "Update" "ERROR" "Version locale introuvable. Vérifiez le format de la ligne de version."
    exit 1
}
Write-Log "Update" "INFO" "Version locale : $localVersion"

# --- Récupération du script distant ---
try {
    $remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -Headers $headers -UseBasicParsing
} catch {
    Write-Log "Update" "ERROR" "Erreur lors de la récupération du script distant : $_"
    exit 1
}

# --- Extraction de la version distante ---
$remoteVersion = Get-VersionFromScript -scriptContent $remoteScriptContent
if (-not $remoteVersion) {
    Write-Log "Update" "ERROR" "Version distante introuvable. Vérifiez le format de la ligne de version dans le script distant."
    exit 1
}
Write-Log "Update" "INFO" "Version distante : $remoteVersion"

# --- Comparaison des versions ---
if ($localVersion -ne $remoteVersion) {
    Write-Log "Update" "INFO" "Une nouvelle version est disponible ! (Locale : $localVersion, Distante : $remoteVersion)"
    try {
        # Écrase le script local avec le contenu distant
        $remoteScriptContent | Set-Content -Path $localScriptPath -Force
        Write-Log "Update" "INFO" "Mise à jour réussie. Le script mis à jour sera utilisé lors de la prochaine execution"
    } catch {
        Write-Log "Update" "ERROR" "Erreur lors de la mise à jour : $_"
        exit 1
    }
} else {
    Write-Log "Update" "INFO" "Le script est déjà à jour (Version locale : $localVersion)."
}
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
        handle_critical "Unable to connect to the VBR server."
    exit
    }
}
#endregion

try {
    # Get all backup session
    $sessListBk = @(GetVBRBackupSession)
    $sessListBk = $sessListBk | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1}
    if (-not $sessListBk) {
        Handle-Unknown "No Backup Session found."
    }
        
    # Iterate over each collection
    foreach ($session in $sessListBk) {
        $sessionName = $session.JobName
        $quotedSessionName = "'$sessionName'"

        Switch($session.Result){
            "Success" {$sessionResult = 0}
            "Warning" {$sessionResult = 1}
            "Failed" {$sessionResult = 2}        
        }

        # Append session details
        $allSessionDetails += "$quotedSessionName=$sessionResult;1;2"

        if ($sessionResult -eq 2) {
            $criticalSessions += "$sessionName"
        } elseif ($totalUsers -eq 1) {
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
        "CRITICAL" { Handle-Critical $finalMessage }
        "WARNING" { Handle-Warning $finalMessage }
        "OK" { Handle-OK $finalMessage }
    }

} catch {
    Handle-Critical "An error occurred: $_"
}
