# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
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

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$remoteScriptURL = "$repoURL/MVM_Repositories.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path
#endregion

#region Functions
# Function to extract version from a script file
function Get-ScriptVersion {
    param (
        [string]$ScriptContent
    )
    if ($ScriptContent -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]
    } else {
        return $null
    }
}

# Functions for NRPE-style exit codes
function Exit-OK {
    param ([string]$Message)
    Write-Host "OK - $Message"
    exit 0
}

function Exit-Warning {
    param ([string]$Message)
    Write-Host "WARNING - $Message"
    exit 1
}

function Exit-Critical {
    param ([string]$Message)
    Write-Host "CRITICAL - $Message"
    exit 2
}

function Exit-Unknown {
    param ([string]$Message)
    Write-Host "UNKNOWN - $Message"
    exit 3
}

# Function Get-VBRRepoInfo
Function Get-VBRRepoInfo {
    [CmdletBinding()]
    param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [PSObject[]]$Repository
    )

    Begin {
        $outputAry = @()
        Function Add-Object {
            param($name, $free, $total)
            $freePercentage = [Math]::Round(($free / $total) * 100)
            $usedPercentage = [Math]::Round(100 - $FreePercentage)
            $repoObj = New-Object -TypeName PSObject -Property @{
                Target = $name
                StorageUsed = [Math]::Round([Decimal]($total - $free) / 1GB, 2)
                StorageFree = [Math]::Round([Decimal]$free / 1GB, 2)
                StorageTotal = [Math]::Round([Decimal]$total / 1GB, 2)
                FreePercentage = $freePercentage
                UsedPercentage = $usedPercentage
            }
            Return $repoObj
        }
    }

    Process {
        Foreach ($r in $Repository) {
            # Refresh Repository Size Info
            [Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb($r, $true)
            $outputObj = Add-Object $r.Name $r.GetContainer().CachedFreeSpace.InBytes $r.GetContainer().CachedTotalSpace.InBytes
        }
        $outputAry += $outputObj
    }

    End {
        $outputAry
    }
}
#endregion

#region Script Update
# Fetch local script version
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-ScriptVersion -ScriptContent $localScriptContent

# Fetch remote script version
$remoteScriptContent = Invoke-RestMethod -Uri $remoteScriptURL -UseBasicParsing
$remoteVersion = Get-ScriptVersion -ScriptContent $remoteScriptContent

# Update script if versions differ
if ($localVersion -ne $remoteVersion) {
    try {
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
    }
}
#endregion

#region Variables
$vbrServer = "localhost"
$ExcludedReposArray = $ExcludedRepos -split ','
$outputStats = @()
#endregion

#region check params
if ($Critical -le $Warning) {
    Exit-Critical "Critical threshold ($Critical) must be greater than Warning threshold ($Warning)."
}
#endregion

#region Connect to VBR Server
if ((Get-VBRServerSession).Server -ne $vbrServer) {
    Disconnect-VBRServer
    try {
        Connect-VBRServer -Server $vbrServer -ErrorAction Stop
    } catch {
        Exit-Critical "Unable to connect to VBR server."
    }
}
#endregion

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
    $outputStats += "$repoStats $prctUsedStats"}

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
        Exit-Unknown "No replica target found"
    }