# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.2.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-16
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================

param (
    [string]$InstallDir
)

$RepoURL = "https://github.com/ATHEO-TDS/MyVeeamMonitoring"

#region Functions
function Get-VersionFromScript {
    param ([string]$Content)
    if ($Content -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]
    }
    return $null
}

function Get-GitHubAPIURL {
    param ([string]$RepoURL)
    $RepoParts = $RepoURL -replace "https://github.com/", "" -split "/"
    if ($RepoParts.Count -lt 2) {
        throw "The repository URL is invalid."
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
        Write-Log -Message "Downloaded: $OutputPath"
    } catch {
        Write-Log -Message "Error downloading $($FileURL): $_" -Level Warning
    }
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")] [string]$Level = "Info"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp [$Level] $Message"
    Add-Content -Path "$InstallDir\mvm_update.log" -Value $LogEntry
    Write-Host $LogEntry
}
#endregion

# Get the GitHub API URL
$APIURL = Get-GitHubAPIURL -RepoURL $RepoURL

# Fetch the files from the repository using the GitHub API
try {
    $Files = Invoke-RestMethod -Uri $APIURL
} catch {
    Write-Log -Message "Error retrieving files from the GitHub API: $_" -Level Error
    exit 1
}

foreach ($File in $Files) {
    $FileURL = $File.download_url

    if ($File.name -match "\.ini$") {
        $IniFile = $File.name
        # Destination for .ini files
        $OutputPath = Join-Path -Path $InstallDir -ChildPath $IniFile
    } else {
        # Destination for all other files
        $OutputPath = Join-Path -Path "$InstallDir\scripts\MyVeeamMonitoring" -ChildPath $File.name
    }

    # Check if the file already exists
    if (Test-Path -Path $OutputPath) {
        Write-Log -Message "File already exists: $OutputPath. Checking versions."

        # Compare versions
        $localScriptContent = Get-Content -Path $OutputPath -Raw
        $localVersion = Get-VersionFromScript -Content $localScriptContent

        $remoteScriptContent = Invoke-RestMethod -Uri $FileURL -UseBasicParsing
        $remoteVersion = Get-VersionFromScript -Content $remoteScriptContent

        if ($localVersion -eq $remoteVersion) {
            Write-Log -Message "Versions are identical: $localVersion. No action required."
            continue
        } else {
            Write-Log -Message "Versions differ (Local: $localVersion, Remote: $remoteVersion). Updating file."
            try {
                $remoteScriptContent | Set-Content -Path $OutputPath -Encoding UTF8 -Force
                Write-Log -Message "File updated: $OutputPath"
            } catch {
                Write-Log -Message "Failed to update the file: $OutputPath" -Level Warning
            }
        }
    } else {
        # If the file doesn't exist, download it
        Write-Log -Message "File does not exist. Downloading: $OutputPath"
        # Ensure the parent directory exists
        $ParentDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $ParentDir)) {
            New-Item -ItemType Directory -Path $ParentDir | Out-Null
        }

        # Download the file
        Get-GitFile -FileURL $FileURL -OutputPath $OutputPath
    }
}
