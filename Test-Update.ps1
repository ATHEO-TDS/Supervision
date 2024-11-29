#Version 1.0.0
# --- Configuration ---
# URL du script distant sur GitHub
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/Supervision"
$versionFileURL = "$repoURL/version.txt"
$scriptFileURL = "$repoURL/Test-Update.ps1"

# Jeton GitHub (optionnel pour les dépôts publics, nécessaire pour les privés)
$token = $env:GITHUB_TOKEN
if (-not $token) {
    Write-Host "Aucun jeton GitHub trouvé. Les dépôts publics fonctionneront sans authentification."
}

# En-têtes pour l'authentification (ajoutés seulement si un token est défini)
$headers = if ($token) { @{ Authorization = "token $token" } } else { @{} }

# Chemin local du script (le fichier actuellement exécuté)
$localScriptPath = $MyInvocation.MyCommand.Path

# --- Fonction pour extraire la version ---
function Get-VersionFromScript {
    param (
        [string]$scriptContent
    )
    # Recherche une ligne contenant '#Version X.Y.Z'
    if ($scriptContent -match "#Version\s+([\d\.]+)") {
        return $matches[1]
    } else {
        Write-Error "Impossible de trouver la version dans le script."
        return $null
    }
}

# --- Extraction de la version locale ---
Write-Host "Extraction de la version locale..."
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -scriptContent $localScriptContent
if (-not $localVersion) {
    Write-Error "Erreur : Version locale introuvable. Vérifiez le format de la ligne de version."
    exit 1
}
Write-Host "Version locale : $localVersion"

# --- Récupération du script distant ---
Write-Host "Téléchargement du script distant pour vérifier sa version..."
try {
    $remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -Headers $headers -UseBasicParsing
} catch {
    Write-Error "Erreur lors de la récupération du script distant : $_"
    exit 1
}

# --- Extraction de la version distante ---
$remoteVersion = Get-VersionFromScript -scriptContent $remoteScriptContent
if (-not $remoteVersion) {
    Write-Error "Erreur : Version distante introuvable. Vérifiez le format de la ligne de version dans le script distant."
    exit 1
}
Write-Host "Version distante : $remoteVersion"

# --- Comparaison des versions ---
if ($localVersion -ne $remoteVersion) {
    Write-Host "Une nouvelle version est disponible ! (Locale : $localVersion, Distante : $remoteVersion)"
    Write-Host "Mise à jour du script local..."
    try {
        # Écrase le script local avec le contenu distant
        $remoteScriptContent | Set-Content -Path $localScriptPath -Force
        Write-Host "Mise à jour réussie. Redémarrage du script..."
        
        # Redémarrer le script mis à jour
        Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$localScriptPath`"" -NoNewWindow
        exit
    } catch {
        Write-Error "Erreur lors de la mise à jour : $_"
        exit 1
    }
} else {
    Write-Host "Le script est déjà à jour (Version locale : $localVersion)."
}

# --- Exécution normale ---
Write-Host "Exécution du script actuel..."
# Ajoutez ici le reste de votre logique métier
