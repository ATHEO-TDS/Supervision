# --- Configuration ---
# URL de base du dépôt GitHub
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/Supervision"
# Remplacez USER, REPO, et BRANCH par votre utilisateur, le nom du dépôt, et la branche (ex. : main).

# Fichiers distants
$versionFileURL = "$repoURL/version.txt"  # Fichier contenant le numéro de version
$scriptFileURL = "$repoURL/Test-Update.ps1"    # Le script PowerShell à télécharger

# Jeton GitHub (recommandé de le stocker dans une variable d'environnement pour plus de sécurité)
$token = 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  # Stockez le jeton dans une variable d'environnement nommée "GITHUB_TOKEN"

# Vérifiez que le jeton existe
if (-not $token) {
    Write-Error "Le jeton GitHub est introuvable. Stockez-le dans une variable d'environnement nommée GITHUB_TOKEN."
    exit 1
}

# En-têtes pour l'authentification
$headers = @{
    Authorization = "token $token"
}

# Chemin du script local (le fichier actuellement exécuté)
$localScriptPath = $MyInvocation.MyCommand.Path

# Version locale du script
$localVersion = "2.0.0"  # Version actuelle codée en dur

# --- Vérification de la version distante ---
Write-Host "Récupération de la version distante..."
try {
    $remoteVersion = Invoke-RestMethod -Uri $versionFileURL -Headers $headers -UseBasicParsing
    $remoteVersion = $remoteVersion.Trim()  # Supprime les espaces inutiles
    Write-Host "Version distante : $remoteVersion"
} catch {
    Write-Error "Erreur lors de la récupération de la version distante : $_"
    exit 1
}

# Comparer les versions
if ($remoteVersion -ne $localVersion) {
    Write-Host "Une nouvelle version est disponible ! (Locale : $localVersion, Distante : $remoteVersion)"
    Write-Host "Téléchargement et mise à jour du script..."

    # --- Téléchargement et mise à jour ---
    try {
        Invoke-WebRequest -Uri $scriptFileURL -Headers $headers -OutFile $localScriptPath -UseBasicParsing
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


#CECI EST MON SCRIPT V2.0.0
