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
    [string]$OutputDirectory = "C:\Scripts"
)

# Variables
$RepoReleasesAPI = "https://api.github.com/repos/ConSol-Monitoring/snclient/releases"
$InstallDir = $OutputDirectory

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


#region Functions
#endregion  
