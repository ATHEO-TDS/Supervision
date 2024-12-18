# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
#
# Evolution : ajout des repo SOBR
# ====================================================================

#region Parameters
param (
    [int]$Warning = 80,
    [int]$Critical = 90,
    [string]$ExcludedRepos = ""
)
#endregion

#region Validate Parameters
# Validate that the Critical threshold is greater than the Warning threshold
if ($Critical -le $Warning) {
    Exit-Critical "Invalid parameter: Critical threshold ($Critical) must be greater than Warning threshold ($Warning)."
}
# Validate that the parameters are non-empty if they are provided
if ($ExcludedRepos -and $ExcludedRepos -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedTargets' contains invalid characters. Please provide a comma-separated list of VM names."
  }
#endregion

#region Functions
# Functions for exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Ensures connection to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"
    .\key.xml"
    
    $OpenConnection = (Get-VBRServerSession).Server
    
    if ($OpenConnection -ne $vbrServer) {
        Disconnect-VBRServer
        
        if (Test-Path $credentialPath) {
            # Load credentials from the XML file
            try {
                $credential = Import-Clixml -Path $credentialPath
                Connect-VBRServer -server $vbrServer -Credential $credential -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to load credentials from the XML file."
            }
        } else {
            # Connect without credentials
            try {
                Connect-VBRServer -server $vbrServer -ErrorAction Stop
            } Catch {
                Exit-Critical "Unable to connect to the VBR server."
            }
        }
    }
}

# Retrieves all repository informations
Function Get-VBRRepoInfo {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [PSObject[]]$InputObj
    )

    BEGIN {
        $outputAry = @()
        $repAry = @()
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
                Repository      = $obj.Name
                StorageFree     = $StorageFree
                StorageUsed     = $StorageUsed
                StorageTotal    = $StorageTotal
                FreePercentage  = $FreePercentage
                UsedPercentage  = $UsedPercentage
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

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$ExcludedReposArray = $ExcludedRepos -split ','
$outputStats = @()
#endregion

try {
    # Get all Repositories
    $repoList = Get-VBRBackupRepository | Get-VBRRepoInfo | Select-Object @{Name='Name'; Expression={$_.Target}},
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

    $ExcludedRepos_regex = ('(?i)^(' + (($ExcludedReposArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
    $filteredRepos= $repoList | Where-Object {$_.Name -notmatch $ExcludedRepos_regex}

    If ($filteredRepos.count -gt 0) {

        $criticalRepos = @($filteredRepos | Where-Object {$_.Status -eq "Critical"})
        $warningRepos = @($filteredRepos | Where-Object {$_.Status -eq "Warning"})
    
        foreach ($repo in $filteredRepos) {
            $name = $repo.Name -replace ' ', '_'
            $totalGB = $repo.TotalStorageGB
            $freeGB = $repo.FreeStorageGB
            $usedGB = $totalGB - $freeGB 
            $prctUsed = $repo.UsedStoragePercent
    
            # Convert Warning and Critical thresholds to percentages of the total GB
            $warningGB = [Math]::Round(($Warning / 100) * $totalGB, 2)
            $criticalGB = [Math]::Round(($Critical / 100) * $totalGB, 2)
            
            # Construct strings for the output
            $repoStats = "$name=${usedGB}GB;$warningGB;$criticalGB;0;$totalGB"
            $prctUsedStats = "${name}_prct_used=$prctUsed%;$Warning;$Critical"
            
            # Append to the output array
            $outputStats += "$repoStats $prctUsedStats"
        }
    
        $outputCritical = ($criticalRepos | Sort-Object { $_.FreeStoragePercent } | ForEach-Object {
            "$($_.Name) - Used: $($_.UsedStoragePercent)% ($($_.FreeStorageGB)GB / $($_.TotalStorageGB)GB)"
        }) -join ", "
        
        $outputWarning = ($warningRepos | Sort-Object { $_.FreeStoragePercent } | ForEach-Object {
            "$($_.Name) - Used: $($_.UsedStoragePercent)% ($($_.FreeStorageGB)GB / $($_.TotalStorageGB)GB)"
        }) -join ", "
        
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
            Exit-Unknown "No repository was found."
        }
}Catch{
    Exit-Critical "An error occurred: $_"
}