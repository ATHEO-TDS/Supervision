# Définir l'URL GitHub où se trouve la version et le script
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/Supervision"
$versionFileURL = "$repoURL/version.txt"
$scriptFileURL = "$repoURL/Test-Update.ps1"

# Chemin du script local (emplacement actuel du script exécuté)
$localScriptPath = $MyInvocation.MyCommand.Path

# Récupérer la version distante
try {
    $remoteVersion = Invoke-RestMethod -Uri $versionFileURL -UseBasicParsing
    $remoteVersion = $remoteVersion.Trim()
} catch {
    Write-Error "Impossible de récupérer la version distante. Vérifiez l'URL."
    exit 1
}

# Définir la version locale (doit être codée dans le script local)
$localVersion = "2.0.0"

# Comparer les versions
if ($remoteVersion -ne $localVersion) {
    Write-Host "Nouvelle version disponible : $remoteVersion (locale : $localVersion)"
    Write-Host "Téléchargement de la nouvelle version..."

    try {
        # Télécharger le nouveau script
        Invoke-WebRequest -Uri $scriptFileURL -OutFile $localScriptPath -UseBasicParsing
        Write-Host "Mise à jour réussie ! Redémarrage du script..."
        
        # Relancer le script après mise à jour
        Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$localScriptPath`"" -NoNewWindow
        exit
    } catch {
        Write-Error "Erreur lors de la mise à jour : $_"
        exit 1
    }
} else {
    Write-Host "Le script est déjà à jour (version : $localVersion)."
}



#CECI EST MON SCRIPT V2.0.0
