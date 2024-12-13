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

param (
    [string]$InstallDir = "C:\Program Files\snclient",
    [string]$AllowedHosts = "127.0.0.1"  # IP de la box de supervision
)

#region Validate Parameters
#endregion

$RepoURL = "https://github.com/ATHEO-TDS/MyVeeamMonitoring"

#region Functions
function Get-GitHubAPIURL {
    param ([string]$RepoURL)
    $RepoParts = $RepoURL -replace "https://github.com/", "" -split "/"
    if ($RepoParts.Count -lt 2) {
        throw "L'URL du dépôt n'est pas valide."
    }
    return "https://api.github.com/repos/$($RepoParts[0])/$($RepoParts[1])/contents"
}

function Get-GitFile {
    param (
        [string]$FileURL,
        [string]$OutputPath
    )
    try {
        Invoke-RestMethod -Uri $FileURL -OutFile $OutputPath
        Write-Host "Téléchargé : $OutputPath"
    } catch {
        Write-Warning "Erreur lors du téléchargement de $FileURL : $_"
    }
}

# Récupère l'URL de l'API GitHub
$APIURL = Get-GitHubAPIURL -RepoURL $RepoURL

# Récupère les fichiers du dépôt via l'API GitHub
try {
    $Files = Invoke-RestMethod -Uri $APIURL
} catch {
    Write-Error "Erreur lors de la récupération des fichiers depuis l'API GitHub : $_"
    exit 1
}

foreach ($File in $Files) {
    $FileURL = $File.download_url

    if ($File.name -match "\.ini$") {
        # Destination pour les fichiers .ini
        $OutputPath = Join-Path -Path $InstallDir -ChildPath $File.name
    } else {
        # Destination pour tous les autres fichiers
        $OutputPath = Join-Path -Path "$InstallDir\scripts\MyVeeamMonitoring" -ChildPath $File.name
    }

    # Vérifie si le répertoire parent de $OutputPath existe, sinon le crée
    $ParentDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir | Out-Null
    }

    # Télécharge le fichier
    Get-GitFile -FileURL $FileURL -OutputPath $OutputPath
}

# Variables
$RepoReleasesAPI = "https://api.github.com/repos/ConSol-Monitoring/snclient/releases"

# Crée le répertoire de téléchargement s'il n'existe pas
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

# Récupère les informations sur les releases via l'API GitHub
try {
    $Releases = Invoke-RestMethod -Uri $RepoReleasesAPI
} catch {
    Write-Error "Erreur lors de l'accès à l'API GitHub : $_"
    exit 1
}

# Recherche le fichier contenant "windows-x86_64.msi" dans la dernière release
$Asset = $Releases.assets | Where-Object { $_.name -match "windows-x86_64\.msi" } | Select-Object -First 1

if ($null -eq $Asset) {
    Write-Error "Aucun fichier contenant 'windows-x86_64.msi' n'a été trouvé."
    exit 1
}

# URL de téléchargement
$DownloadURL = $Asset.browser_download_url
$OutputFile = Join-Path -Path $InstallDir -ChildPath $Asset.name

# Télécharge le fichier
Write-Host "Téléchargement de $($Asset.name)..."
Invoke-WebRequest -Uri $DownloadURL -OutFile $OutputFile

Write-Host "Fichier téléchargé avec succès : $OutputFile"

# Variables
$RepoReleasesAPI = "https://api.github.com/repos/ConSol-Monitoring/snclient/releases"
$LogFile = Join-Path -Path $InstallDir -ChildPath "snclient_installer.log"
$IniFile =  ".\test.ini"

# Crée le répertoire de téléchargement s'il n'existe pas
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

# Récupère les informations sur les releases via l'API GitHub
try {
    $Releases = Invoke-RestMethod -Uri $RepoReleasesAPI
} catch {
    Write-Error "Erreur lors de l'accès à l'API GitHub : $_"
    exit 1
}

# Recherche le fichier contenant "windows-x86_64.msi" dans la dernière release
$Asset = $Releases.assets | Where-Object { $_.name -match "windows-x86_64\.msi" } | Select-Object -First 1

if ($null -eq $Asset) {
    Write-Error "Aucun fichier contenant 'windows-x86_64.msi' n'a été trouvé."
    exit 1
}

# URL de téléchargement
$DownloadURL = $Asset.browser_download_url
$OutputFile = Join-Path -Path $InstallDir -ChildPath $Asset.name

# Télécharge le fichier MSI
Write-Host "Téléchargement de $($Asset.name)..."
Invoke-WebRequest -Uri $DownloadURL -OutFile $OutputFile

Write-Host "Fichier téléchargé avec succès : $OutputFile"


# Installe le MSI
Write-Host "Démarrage de l'installation de snclient.msi..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$OutputFile`" /l*V `"$LogFile`" /qn INCLUDES=`"$IniFile`" ALLOWEDHOSTS=`"$AllowedHosts`" WEBSERVER=0 WEBSERVERSSL=0 NRPESERVER=1" -Wait
Write-Host "Installation terminée avec succès, fichiers de logs : $LogFile"



CHANGER LES PARAMETRES DANS LE FICHIER ini UPDATE ECT
TACHE PLANIFIER POUR UPDATE .INI 
REGLE FW
OPTION INSTALL NRPE OR WINRM
OPTION JUSTE DL SCRIPTS
