# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
# Ce script permet de surveiller la sauvegarde de la configuration du serveur Veeam Backup & Replication 
# et d'envoyer des alertes basées sur le statut de la sauvegarde. Il analyse les sessions 
# récentes en fonction de l'heure définie par le paramètre $RPO (Recovery Point Objective), 
# et signale toute session étant en avertissement ou ayant échoué.
#
# L'objectif est d'assurer un suivi efficace de la sauvegarde et de signaler rapidement via 
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
$scriptFileURL = "$repoURL/MVM_BackupConfig.ps1"
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
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
    }
}
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
