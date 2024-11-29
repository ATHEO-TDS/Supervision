# ====================================================================
# Script PowerShell : Vérification et gestion des sessions de sauvegarde Veeam
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Description : Ce script vérifie l'état des sessions de sauvegarde Veeam
#               et retourne des messages d'alerte en fonction du statut des tâches.
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-11-29
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

#region arguments
param (
    [int]$RPO
)
#endregion

#region functions
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
            if ($scriptContent -match "#Version\s*:\s*([\d\.]+)") {
                return $matches[1]
            } else {
                Write-Error "Impossible de trouver la version dans le script."
                return $null
            }
        }
    #endregion

    #region Fonctions Handle NRPE
        function handle_ok {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "OK - $message"
            }
            exit 0
        }

        function handle_warning {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "WARNING - $message"
            }
            exit 1
        }

        function handle_critical {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "CRITICAL - $message"
            }
            exit 2
        }

        function handle_unknown {
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

#region update script
# Configuration
$repoURL = "https://github.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/SDSup_Backup_newgen.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path

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
$vbrMasterHash = @()
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

$sessListBk = @(GetVBRBackupSession)
$sessListBk = $sessListBk | Group-Object JobName | ForEach-Object { $_.Group | Sort-Object SessionEndTime -Descending | Select-Object -First 1}

$successSessionsBk = @($sessListBk | Where-Object {$_.Result -eq "Success"})
$warningSessionsBk = @($sessListBk | Where-Object {$_.Result -eq "Warning"})
$failsSessionsBk = @($sessListBk | Where-Object {($_.Result -eq "Failed") -and ($_.WillBeRetried -eq "True")})
$runningSessionsBk = @($sessListBk | Where-Object {($_.State -eq "Working")})
$failedSessionsBk = @($sessListBk | Where-Object {($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})

$vbrMasterHash = @{
    "Failed" = @($failedSessionsBk).Count
    "Sessions" = If ($sessListBk) {@($sessListBk).Count} Else {0}
    "Successful" = @($successSessionsBk).Count
    "Warning" = @($warningSessionsBk).Count
    "Fails" = @($failsSessionsBk).Count
    "Running" = @($runningSessionsBk).Count
}
$vbrMasterObj = New-Object -TypeName PSObject -Property $vbrMasterHash

if ($vbrMasterObj.Sessions -eq 0) {
    handle_critical "No backup sessions found or unable to fetch backup job information."
}
if ($vbrMasterObj.Failed -gt 0) {
    $failedJobs = @($failedSessionsBk | Select-Object -ExpandProperty JobName) -join ", "
    handle_critical "At least one failed backup session: $failedJobs"
}
if ($vbrMasterObj.Warning -gt 0 -and $vbrMasterObj.Failed -eq 0) {
    $warningJobs = @($warningSessionsBk | Select-Object -ExpandProperty JobName) -join ", "
    handle_warning "At least one backup session is in a warning state: $warningJobs"
}
if ($vbrMasterObj.Fails -gt 0) {
    $failedJobs = @($failsSessionsBk | Select-Object -ExpandProperty JobName) -join ", "
    handle_warning "At least one backup session has failed, but waiting for retry : $failedJobs"
}
if ($vbrMasterObj.Successful -eq $vbrMasterObj.Sessions) {
    $message = "All backup sessions are successful ($($vbrMasterObj.Successful))."
    if ($vbrMasterObj.Running -gt 0) {
        $runningJobs = @($runningSessionsBk | Select-Object -ExpandProperty JobName) -join ", "
        $message = "All backup sessions are successful, but there are jobs still running: $runningJobs."
    }
    handle_ok $message
}
