# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-20
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# Description:
# This PowerShell script monitors the storage usage of repositories in 
# Veeam Backup & Replication (VBR). It calculates the used, free, and total
# storage on repositories and compares the storage usage to specified 
# thresholds (Warning and Critical). The script provides an alert if any 
# repository exceeds the defined thresholds, with a custom message 
# detailing the status of each repository.
#
# Parameters:
# - Warning: Defines the storage usage percentage at which a warning will be triggered. Default is 80%.
# - Critical: Defines the storage usage percentage at which a critical alert will be triggered. Default is 90%.
# - ExcludedTargets: A comma-separated list of repository names to exclude from monitoring. 
#
# Returns:
#   - OK: If all repositories are below the defined thresholds.
#   - Warning: If one or more repositories exceed the Warning threshold but not the Critical threshold.
#   - Critical: If one or more repositories exceed the Critical threshold.
#   - Unknown: If no repositories are found or an error occurs.
#
# ====================================================================

#region Parameters
param (
    [int]$Warning = 80,   # Warning threshold for storage usage percentage
    [int]$Critical = 90,  # Critical threshold for storage usage percentage
    [string]$ExcludedRepos = ""  # List of repository names to exclude from monitoring
)
#endregion

#region Functions
# Functions for returning exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Function to connect to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"  # Veeam Backup & Replication server address
    $credentialPath = ".\scripts\MyVeeamMonitoring\key.xml"  # Path to credentials file for connection
    
    # Check if a connection to the VBR server is already established
    $OpenConnection = (Get-VBRServerSession).Server
    
    if ($OpenConnection -ne $vbrServer) {
        # Disconnect existing session if connected to a different server
        Disconnect-VBRServer
        
        if (Test-Path $credentialPath) {
            # Load credentials from XML file
            try {
                $credential = Import-Clixml -Path $credentialPath
                Connect-VBRServer -server $vbrServer -Credential $credential -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to load credentials from the XML file."
            }
        } else {
            # Connect without credentials if file does not exist
            try {
                Connect-VBRServer -server $vbrServer -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to connect to the VBR server."
            }
        }
    }
}

# Retrieves all repository information
Function Get-VBRRepoInfo {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [PSObject[]]$InputObj
    )

    BEGIN {
        $outputAry = @()  # Initialize an array for output data
        $repAry = @()  # Initialize an array to track processed repos
    }

    PROCESS {
        foreach ($obj in $InputObj) {
            # Skip if the repository has already been processed
            if ($repAry -contains $obj.name) {
                continue
            }

            # Refresh Repository Size Info
            [Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb($obj, $true)

            # Retrieve the repository and calculate storage usage
            $StorageFree = [Math]::Round([Decimal]$obj.GetContainer().CachedFreeSpace.InBytes / 1GB, 2)
            $StorageTotal = [Math]::Round([Decimal]$obj.GetContainer().CachedTotalSpace.InBytes / 1GB, 2)
            $StorageUsed = $StorageTotal - $StorageFree
            $FreePercentage = [Math]::Round(($StorageFree / $StorageTotal) * 100)
            $usedPercentage = 100 - $FreePercentage

            # Prepare the output object
            $objoutput = [PSCustomObject]@{
                Repository       = $obj.Name  # Repository name
                StorageFree     = $StorageFree  # Free storage in GB
                StorageUsed     = $StorageUsed  # Used storage in GB
                StorageTotal    = $StorageTotal  # Total storage in GB
                FreePercentage  = $FreePercentage  # Free storage percentage
                UsedPercentage  = $UsedPercentage  # Used storage percentage
            }

            # Add the datastore name to the list and the result to the output array
            $repAry += $obj.Name
            $outputAry += $objoutput
        }
    }

    END {
        # Return the output
        $outputAry | Select-Object Repository, StorageFree, StorageUsed, StorageTotal, FreePercentage, UsedPercentage
    }
}
#endregion

#region Validate Parameters
# Validate that the Critical threshold is greater than the Warning threshold
if ($Critical -le $Warning) {
    Exit-Critical "Invalid parameter: Critical threshold ($Critical) must be greater than Warning threshold ($Warning)."
}
# Validate that the parameters are non-empty if they are provided
if ($ExcludedRepos -and $ExcludedRepos -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedRepos' contains invalid characters. Please provide a comma-separated list of repository names."
  }
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$ExcludedReposArray = $ExcludedRepos -split ',' # Split the ExcludedRepos string into an array
$outputStats = @()  # Initialize an array to store the output statistics
#endregion

try {
    #  Retrieve all repositories information
    $repoList = Get-VBRBackupRepository | Get-VBRRepoInfo | Select-Object @{Name='Name'; Expression={$_.Repository}},
    @{Name='UsedStorageGB'; Expression={$_.StorageUsed}},
    @{Name='FreeStorageGB'; Expression={$_.StorageFree}},
    @{Name='TotalStorageGB'; Expression={$_.StorageTotal}},
    @{Name='FreeStoragePercent'; Expression={$_.FreePercentage}},
    @{Name='UsedStoragePercent'; Expression={$_.UsedPercentage}},
    @{Name='Status'; Expression={
        If ($_.UsedPercentage -ge $Critical) { "Critical" }
        ElseIf ($_.UsedPercentage -ge $Warning) { "Warning" }
        Else { "OK" }
    }}

    # Create a regular expression to exclude specified repo from monitoring
    $ExcludedRepos_regex = ('(?i)^(' + (($ExcludedReposArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
    $filteredRepos= $repoList | Where-Object {$_.Name -notmatch $ExcludedRepos_regex}

    If ($filteredRepos.count -gt 0) {

        # Separate critical and warning  repos
        $criticalRepos = @($filteredRepos | Where-Object {$_.Status -eq "Critical"})
        $warningRepos = @($filteredRepos | Where-Object {$_.Status -eq "Warning"})
    
        foreach ($repo in $filteredRepos) {
            $name = $repo.Name -replace ' ', '_'  # Replace spaces in the name with underscores
            $totalGB = $repo.TotalStorageGB  # Total storage in GB
            $freeGB = $repo.FreeStorageGB # Free storage in GB
            $usedGB = $totalGB - $freeGB  # Used storage in GB
            $prctUsed = $repo.UsedStoragePercent  # Used storage percentage
    
            # Convert Warning and Critical thresholds to absolute storage in GB
            $warningGB = [Math]::Round(($Warning / 100) * $totalGB, 2)
            $criticalGB = [Math]::Round(($Critical / 100) * $totalGB, 2)
            
            # Construct strings for the output
            $repoStats = "$name=${usedGB}GB;$warningGB;$criticalGB;0;$totalGB"
            $prctUsedStats = "${name}_prct_used=$prctUsed%;$Warning;$Critical"
            
            # Append to the output array
            $outputStats += "$repoStats $prctUsedStats"
        }

        # Prepare output for critical and warning repos
        $outputCritical = ($criticalRepos | Sort-Object { $_.FreeStoragePercent } | ForEach-Object {
            "$($_.Name) - Used: $($_.UsedStoragePercent)% ($($_.FreeStorageGB)GB / $($_.TotalStorageGB)GB)"
        }) -join ", "
        $outputWarning = ($warningRepos | Sort-Object { $_.FreeStoragePercent } | ForEach-Object {
            "$($_.Name) - Used: $($_.UsedStoragePercent)% ($($_.FreeStorageGB)GB / $($_.TotalStorageGB)GB)"
        }) -join ", "
        
        # Exit with appropriate status based on critical and warning repos
        If ($criticalRepos.count -gt 0) {
            $criticalMessage = If ($criticalRepos.count -eq 1) { 
                "$($criticalRepos.count) repository is in critical state" 
            } Else { 
                "$($criticalRepos.count) repositories are in critical state" 
            }
            Exit-Critical "$criticalMessage : $outputCritical|$outputStats"
        }
        ElseIf ($warningRepos.count -gt 0) {
            $warningMessage = If ($warningRepos.count -eq 1) { 
                "$($warningRepos.count) repository is in warning state" 
            } Else { 
                "$($warningRepos.count) repositories are in warning state" 
            }
            Exit-Warning "$warningMessage : $outputWarning|$outputStats"
        }
        Else {
            Exit-OK "All repositories are in ok state|$outputStats"
        }
    
        }Else{
            Exit-Unknown "No repository was found"
        }
} Catch {
    Exit-Critical "An error occurred: $($_.Exception.Message)"
}