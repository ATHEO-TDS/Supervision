# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-19
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# DESCRIPTION:
# This PowerShell script automates the process of downloading, installing, and configuring NSClient.
# It also retrieves files from the MyVeeamMonitoring GitHub repository.
# The script handles the configuration of authentication if needed for running scripts.
# Additionally, it sets up a scheduled task to run the update script daily to ensure MyVeeamMonitoring scripts remain updated.
#
# PARAMETERS:
# - InstallDir: Specifies the directory where NSClient will be installed - Default is "C:\Program Files\snclient". 
#                This directory is where the software and related files will be downloaded and stored.
#
# - AllowedHosts: Defines the IP addresses permitted to send NRPE requests to the VBR server. 
#                 This parameter should be an IP address or "localhost" (default: "127.0.0.1").
#                 The value is used to configure access control in the NSClient configuration file.
#
# - AuthNeeded: A switch that indicates whether authentication is required to run the scripts.
#               If this switch is specified, the script will prompt for user credentials, 
#               which will be saved in a secure XML file for future use.
#               If this switch is not used, no authentication will be prompted and no credentials will be saved.
#
# ====================================================================


param (
    [ValidateNotNullOrEmpty()]
    [string]$InstallDir = "C:\Program Files\snclient",  # Directory where the snclient will be installed

    [ValidatePattern("^(?:(?:\d{1,3}\.){3}\d{1,3}|localhost)$")]
    [string]$AllowedHosts = "127.0.0.1",  # IP address of the monitoring box

    [ValidateSet("True", "False")]
    [switch]$AuthNeeded  # switch indicating whether authentication is required for running scripts
)

#region Validate Parameters
# Validate that the $AllowedHosts parameter contains a valid IP address or 'localhost'
if (-not ($AllowedHosts -match "^(?:(?:\d{1,3}\.){3}\d{1,3}|localhost)$")) {
    throw "Invalid IP address format for AllowedHosts: '$AllowedHosts'. Please use a valid IP or 'localhost'."
}
#endregion

$RepoURL = "https://github.com/TiagoDSLV/MyVeeamMonitoring"  # GitHub repository URL for MyVeeamMonitoring

#region Functions

# Function to retrieve the GitHub API URL based on the repository URL
function Get-GitHubAPIURL {
    param ([string]$RepoURL)
    $RepoParts = $RepoURL -replace "https://github.com/", "" -split "/"
    if ($RepoParts.Count -lt 2) {
        throw "The repository URL is not valid."
    }
    return "https://api.github.com/repos/$($RepoParts[0])/$($RepoParts[1])/contents"
}

# Function to download a file from the GitHub repository using the API URL
function Get-GitFile {
    param (
        [string]$FileURL,  # URL of the file to download
        [string]$OutputPath  # Destination path to save the downloaded file
    )
    try {
        Invoke-RestMethod -Uri $FileURL -OutFile $OutputPath  # Download the file
        Write-Host "Downloaded: $OutputPath"  # Notify successful download
    } catch {
        Write-Warning "Error downloading $($FileURL): $_"  # Notify if an error occurred during download
    }
}
#endregion

# Retrieve GitHub API URL
$APIURL = Get-GitHubAPIURL -RepoURL $RepoURL

# Get files from the GitHub repository via the API
try {
    $Files = Invoke-RestMethod -Uri $APIURL  # Retrieve file list from GitHub
} catch {
    Write-Error "Error retrieving files from GitHub API: $_"
    exit 1
}

# Loop through each file in the repository and download it to the appropriate directory
foreach ($File in $Files) {
    $FileURL = $File.download_url

    # Destination path
    $OutputPath = Join-Path -Path "$InstallDir\scripts\MyVeeamMonitoring" -ChildPath $File.name
    
    # Ensure the parent directory exists before saving the file
    $ParentDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -Path $ParentDir)) {
        New-Item -ItemType Directory -Path $ParentDir | Out-Null  # Create the parent directory if it doesn't exist
    }

    # Download the file
    Get-GitFile -FileURL $FileURL -OutputPath $OutputPath
}

# Variables for downloading the snclient installer and setting up logging
$RepoReleasesAPI = "https://api.github.com/repos/ConSol-Monitoring/snclient/releases"
$LogFile = Join-Path -Path $InstallDir -ChildPath "snclient_installer.log"

# Ensure the installation directory exists
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null  # Create the installation directory if it doesn't exist
}

# Retrieve release information for snclient from the GitHub API
try {
    $Releases = Invoke-RestMethod -Uri $RepoReleasesAPI  # Retrieve release information
} catch {
    Write-Error "Error accessing GitHub API: $_"
    exit 1
}

# Find the MSI installer for Windows
$Asset = $Releases.assets | Where-Object { $_.name -match "windows-x86_64\.msi" } | Select-Object -First 1

# If no suitable MSI is found, exit with an error
if ($null -eq $Asset) {
    Write-Error "No file containing 'windows-x86_64.msi' was found."
    exit 1
}

# Get the download URL for the MSI file
$DownloadURL = $Asset.browser_download_url
$OutputFile = Join-Path -Path $InstallDir -ChildPath $Asset.name

# Download the MSI installer
Write-Host "Downloading $($Asset.name)..."
Invoke-WebRequest -Uri $DownloadURL -OutFile $OutputFile  # Download the MSI file
Write-Host "File downloaded successfully: $OutputFile"

# Install snclient.msi using msiexec
Write-Host "Starting installation of snclient.msi..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$OutputFile`" /l*V `"$LogFile`" /qn ALLOWEDHOSTS=`"$AllowedHosts`" WEBSERVER=0 WEBSERVERSSL=0 NRPESERVER=1" -Wait
Write-Host "Installation completed successfully, log files: $LogFile"

# Update Ini File
Write-Host "Updating Ini File..."
$iniFilePath = "$InstallDir\snclient.ini" # Define the path to the .ini file
$iniContent = Get-Content -Path $iniFilePath
# Specify the branch and file path in the repository
$Branch = "main"
$FilePath = "MVM_SNClientConfig.ini"
# Construct the raw content URL
$rawContentURL = "$RepoURL" -replace "https://github.com/", "https://raw.githubusercontent.com/" -replace "/blob/", "/"
$rawContentURL = "$rawContentURL/$Branch/$FilePath"
$RemoteIni = "remote = $rawContentURL"
Add-Content -Path $iniFilePath -Value $RemoteIni # Add the new line to the end of the file
$iniContent = $iniContent -replace "CheckExternalScripts = disabled", "CheckExternalScripts = enabled"
$iniContent = $iniContent -replace "timeout = 30", "timeout = 60"
$iniContent = $iniContent -replace "allow arguments = false", "allow arguments = true"
$iniContent = $iniContent -replace "automatic updates = disabled", "automatic updates = true"
$iniContent = $iniContent -replace "automatic restart = disabled", "automatic restart = true"
$iniContent = $iniContent -replace "update hours = 0-24", "update hours = 9-17"
$iniContent = $iniContent -replace "update days = mon-sun", "update days = mon-fri"
$iniContent = $iniContent -replace "update interval = 1h", "update interval = 24h"
Set-Content -Path $iniFilePath -Value $iniContent
Write-Host "Ini File updated."
Write-Host "Restarting SNClient Service"
Restart-Service -Name snclient
Write-Host "SNClient Service restarted"

## Configure the scheduled task to update scripts
$TaskName = "MVM - Update scripts"
$ScriptPath = "$InstallDir\scripts\MyVeeamMonitoring\MVM_Update.ps1"
$TriggerTime = "12:00:00"  # Time when the task will run daily
$Description = "Scheduled Task to run the script which updates MyVeeamMonitoring"

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

    # Define task settings, including execution time limit of 1 hour
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    # Register the scheduled task with a description
    Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Principal $Principal -Settings $Settings -Description $Description | Out-Null

    Write-Host "The task '$TaskName' has been successfully created and will run daily at $TriggerTime."
}

# If authentication is required, prompt the user for credentials and save them to the XML file
$credentialPath = "$InstallDir\scripts\MyVeeamMonitoring\key.xml"

if ($AuthNeeded) {
    try {
        Write-Host "Authentication is needed. Please provide credentials."
        $credential = Get-Credential
        $credential | Export-Clixml -Path $credentialPath  # Save credentials to XML
        Write-Host "Credentials have been saved to $credentialPath."
    } catch {
        Write-Error "Failed to save credentials. Error: $_"
        Exit 1
    }
} else {
    Write-Host "Authentication is not needed. Skipping credential storage."
}