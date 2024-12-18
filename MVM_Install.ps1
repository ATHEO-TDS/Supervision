# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================

param (
    [ValidateNotNullOrEmpty()]
    [string]$InstallDir = "C:\Program Files\snclient",

    [ValidatePattern("^(?:(?:\d{1,3}\.){3}\d{1,3}|localhost)$")]
    [string]$AllowedHosts = "127.0.0.1"  # Monitoring box IP
)

#region Validate Parameters
if (-not ($AllowedHosts -match "^(?:(?:\d{1,3}\.){3}\d{1,3}|localhost)$")) {
    throw "Invalid IP address format for AllowedHosts: '$AllowedHosts'. Please use a valid IP or 'localhost'."
}
#endregion

$RepoURL = "https://github.com/ATHEO-TDS/MyVeeamMonitoring"

#region Functions

function Get-GitHubAPIURL {
    param ([string]$RepoURL)
    $RepoParts = $RepoURL -replace "https://github.com/", "" -split "/"
    if ($RepoParts.Count -lt 2) {
        throw "The repository URL is not valid."
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
        Write-Host "Downloaded: $OutputPath"
    } catch {
        Write-Warning "Error downloading $($FileURL): $_"
    }
}

#endregion

# Retrieve GitHub API URL
$APIURL = Get-GitHubAPIURL -RepoURL $RepoURL

# Get files from the GitHub repository via the API
try {
    $Files = Invoke-RestMethod -Uri $APIURL
} catch {
    Write-Error "Error retrieving files from GitHub API: $_"
    exit 1
}

foreach ($File in $Files) {
    $FileURL = $File.download_url

    if ($File.name -match "\.ini$") {
        $IniFile = $File.name
        # Destination for .ini files
        $OutputPath = Join-Path -Path $InstallDir -ChildPath $IniFile
        
    } else {
        # Destination for other files
        $OutputPath = Join-Path -Path "$InstallDir\scripts\MyVeeamMonitoring" -ChildPath $File.name
    }

    # Ensure the parent directory exists
    $ParentDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir | Out-Null
    }

    # Download the file
    Get-GitFile -FileURL $FileURL -OutputPath $OutputPath
}

# Variables
$RepoReleasesAPI = "https://api.github.com/repos/ConSol-Monitoring/snclient/releases"
$LogFile = Join-Path -Path $InstallDir -ChildPath "snclient_installer.log"

# Ensure the installation directory exists
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}

# Retrieve release information from the GitHub API
try {
    $Releases = Invoke-RestMethod -Uri $RepoReleasesAPI
} catch {
    Write-Error "Error accessing GitHub API: $_"
    exit 1
}

# Find the MSI file in the latest release
$Asset = $Releases.assets | Where-Object { $_.name -match "windows-x86_64\.msi" } | Select-Object -First 1

if ($null -eq $Asset) {
    Write-Error "No file containing 'windows-x86_64.msi' was found."
    exit 1
}

# Download URL
$DownloadURL = $Asset.browser_download_url
$OutputFile = Join-Path -Path $InstallDir -ChildPath $Asset.name
    
# Download the MSI file
Write-Host "Downloading $($Asset.name)..."
Invoke-WebRequest -Uri $DownloadURL -OutFile $OutputFile
Write-Host "File downloaded successfully: $OutputFile"

# Install the MSI
Write-Host "Starting installation of snclient.msi..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$OutputFile`" /l*V `"$LogFile`" /qn INCLUDES=`"$IniFile`" ALLOWEDHOSTS=`"$AllowedHosts`" WEBSERVER=0 WEBSERVERSSL=0 NRPESERVER=1" -Wait
Write-Host "Installation completed successfully, log files: $LogFile"


## Configure the scheduled task
$TaskName = "MVM - Update scripts"
$ScriptPath = "$InstallDir\scripts\MyVeeamMonitoring\MVM_Update.ps1"
$TriggerTime = "12:00:00"
$Description = "Scheduled Task to run the script which updates MVM Scripts and Ini File"

# Check if the task already exists
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Task '$TaskName' already exists. Skipping creation."
} else {
    # Create a trigger for the task
    $Trigger = New-ScheduledTaskTrigger -Daily -At $TriggerTime

    # Define the action to execute PowerShell with the script
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -InstallDir `"$InstallDir`""

    # Set the task to run as SYSTEM
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Définir les paramètres, incluant une limite de temps d'exécution de 1 heure
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    # Register the scheduled task with a description
    Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Principal $Principal -Settings $Settings -Description $Description  | Out-Null

    Write-Host "The task '$TaskName' has been successfully created and will run daily at $TriggerTime."
}

# Create a firewall rule to allow NRPE traffic
if (-not (Get-NetFirewallRule -DisplayName "Allow NRPE From Monitoring" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Allow NRPE From Monitoring" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5666 -RemoteAddress $AllowedHosts -Profile Any | Out-Null
    Write-Host "Firewall rule created successfully."
} else {
    Write-Host "Firewall rule 'Allow NRPE From Monitoring' already exists. Skipping creation."
}
