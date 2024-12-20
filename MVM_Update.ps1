# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-19
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# Description:
# This PowerShell script is designed to automate the process of checking for
# updates to MVM scripts stored in GitHub repository. It compares the
# local versions of files with the versions available on the GitHub repository
# and updates the local files if a newer version is found. The script downloads
# the files to a specified installation directory and logs all actions.
#
# Parameters:
# - InstallDir: The directory where the scripts and configuration files will
#   be installed or updated. This directory should be provided when running
#   the script.
#
# Returns:
#   - The script logs actions and errors to the specified installation directory,
#     specifically to a log file named 'mvm_update.log'.
#
# =========================================================

param (
    [string]$InstallDir  # Directory where files will be installed or updated
)

# Define the repository URL where the scripts are hosted
$RepoURL = "https://github.com/TiagoDSLV/MyVeeamMonitoring"

#region Functions
# Function to extract version from script content using a regex pattern
function Get-VersionFromScript {
    param ([string]$Content)
    if ($Content -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]  # Return the version string if found
    }
    return $null  # Return null if no version is found
}

# Function to generate the GitHub API URL based on the repository URL
function Get-GitHubAPIURL {
    param ([string]$RepoURL)
    $RepoParts = $RepoURL -replace "https://github.com/", "" -split "/"
    if ($RepoParts.Count -lt 2) {
        throw "The repository URL is invalid."  # Throw error if URL is invalid
    }
    return "https://api.github.com/repos/$($RepoParts[0])/$($RepoParts[1])/contents"
}

# Function to download a file from GitHub repository to a specified path
function Get-GitFile {
    param (
        [string]$FileURL,  # URL of the file to be downloaded
        [string]$OutputPath  # Local path where the file will be saved
    )
    try {
        # Try downloading the file and saving it to the output path
        Invoke-RestMethod -Uri $FileURL -OutFile $OutputPath
        Write-Log -Message "Downloaded: $OutputPath"
    } catch {
        Write-Log -Message "Error downloading $($FileURL): $_" -Level Warning  # Log errors if download fails
    }
}

# Function to write log messages to a log file and display in the console
function Write-Log {
    param (
        [string]$Message,  # The log message
        [ValidateSet("Info", "Warning", "Error")] [string]$Level = "Info"  # Log level (default is Info)
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"  # Add timestamp to log
    $LogEntry = "$Timestamp [$Level] $Message"  # Format log entry
    Add-Content -Path "$InstallDir\mvm_update.log" -Value $LogEntry  # Write to log file
    Write-Host $LogEntry  # Display in console
}
#endregion

# Get the GitHub API URL based on the repository URL
$APIURL = Get-GitHubAPIURL -RepoURL $RepoURL

# Fetch the list of files from the GitHub repository
try {
    $Files = Invoke-RestMethod -Uri $APIURL  # Get file list from GitHub API
} catch {
    Write-Log -Message "Error retrieving files from the GitHub API: $_" -Level Error  # Log error if the API call fails
    exit 1  # Exit the script with error code
}

# Process each file retrieved from the repository
foreach ($File in $Files) {
    $FileURL = $File.download_url  # Get the URL of the file to be downloaded

    $OutputPath = Join-Path -Path "$InstallDir\scripts\MyVeeamMonitoring" -ChildPath $File.name  # Destination path

    # Check if the file already exists
    if (Test-Path -Path $OutputPath) {
        Write-Log -Message "File already exists: $OutputPath. Checking versions."

        # Compare the local and remote versions of the file
        $localScriptContent = Get-Content -Path $OutputPath -Raw  # Read local file content
        $localVersion = Get-VersionFromScript -Content $localScriptContent  # Extract local version

        $remoteScriptContent = Invoke-RestMethod -Uri $FileURL -UseBasicParsing  # Get remote file content
        $remoteVersion = Get-VersionFromScript -Content $remoteScriptContent  # Extract remote version

        # If versions are identical, log and skip update
        if ($localVersion -eq $remoteVersion) {
            Write-Log -Message "Versions are identical: $localVersion. No action required."
            continue
        } else {
            Write-Log -Message "Versions differ (Local: $localVersion, Remote: $remoteVersion). Updating file."
            try {
                # Update local file with remote content if versions differ
                $remoteScriptContent | Set-Content -Path $OutputPath -Encoding UTF8 -Force
                Write-Log -Message "File updated: $OutputPath"
            } catch {
                Write-Log -Message "Failed to update the file: $OutputPath" -Level Warning  # Log failure to update
            }
        }
    } else {
        # If the file doesn't exist, download it
        Write-Log -Message "File does not exist. Downloading: $OutputPath"
        # Ensure the parent directory exists before downloading
        $ParentDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $ParentDir)) {
            New-Item -ItemType Directory -Path $ParentDir | Out-Null  # Create parent directory if necessary
        }

        # Download the file from GitHub repository
        Get-GitFile -FileURL $FileURL -OutputPath $OutputPath
    }
}
