# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
#
# ====================================================================

#region Parameters
param (
    [int]$Warning = 80,
    [int]$Critical = 90,
    [string]$ExcludedTargets = ""
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$remoteScriptURL = "$repoURL/MVM_ReplicaTargets.ps1"
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

# Functions Get-VBRReplicaTarget
Function Get-VBRReplicaTarget {
    [CmdletBinding()]
    param(
      [Parameter(ValueFromPipeline=$true)]
      [PSObject[]]$InputObj
    )
    BEGIN {
      $outputAry = @()
      $dsAry = @()
      If (($null -ne $Name) -and ($null -ne $InputObj)) {
        $InputObj = Get-VBRJob -Name $Name
      }
    }
    PROCESS {
      Foreach ($obj in $InputObj) {
        If (($dsAry -contains $obj.ViReplicaTargetOptions.DatastoreName) -eq $false) {
          $esxi = $obj.GetTargetHost()
          $dtstr =  $esxi | Find-VBRViDatastore -Name $obj.ViReplicaTargetOptions.DatastoreName
          $FreePercentage = [Math]::Round(($dtstr.FreeSpace / $dtstr.Capacity) * 100)
          $UsedPercentage = [Math]::Round(100 - $FreePercentage)
          $objoutput = New-Object -TypeName PSObject -Property @{
                Datastore       = $obj.ViReplicaTargetOptions.DatastoreName
                StorageFree     = [Math]::Round([Decimal]$dtstr.FreeSpace / 1GB, 2)
                StorageTotal    = [Math]::Round([Decimal]$dtstr.Capacity / 1GB, 2)
                FreePercentage  = $FreePercentage
                UsedPercentage  = $UsedPercentage
          }

          $dsAry = $dsAry + $obj.ViReplicaTargetOptions.DatastoreName
          $outputAry = $outputAry + $objoutput
        } Else {
          return
        }
      }
    }
    END {
      $outputAry | Select-Object Target, Datastore, StorageFree, StorageTotal, FreePercentage, UsedPercentage
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
$ExcludedTargetsArray = $ExcludedTargets -split ','
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

$allJobs = Get-VBRJob -WarningAction SilentlyContinue
$allJobsRp = @($allJobs | Where-Object {$_.JobType -eq "Replica"})

$repTargets = $allJobsRp | Get-VBRReplicaTarget | Select-Object @{Name="Name"; Expression = {$_.Datastore}},
      @{Name="Free (GB)"; Expression = {$_.StorageFree}}, @{Name="Total (GB)"; Expression = {$_.StorageTotal}},
      @{Name="Free (%)"; Expression = {$_.FreePercentage}},
      @{Name = "Used (%)"; Expression = {$_.UsedPercentage}},
      @{Name="Status"; Expression = {
        If ($_.UsedPercentage -ge $Critical) {"Critical"}
        ElseIf ($_.UsedPercentage -ge $Warning) {"Warning"}
        Else {"OK"}
        }
      }

$ExcludedTargets_regex = ('(?i)^(' + (($ExcludedTargetsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$filteredrepTargets = $repTargets | Where-Object {$_.Name -notmatch $ExcludedTargets_regex}

If ($filteredrepTargets.count -gt 0) {

    $criticalRepTargets = @($filteredrepTargets | Where-Object {$_.Status -eq "Critical"})
    $warningRepTargets = @($filteredrepTargets | Where-Object {$_.Status -eq "Warning"})
    #$okRepTargets = @($filteredrepTargets | Where-Object {$_.Status -eq "OK"})

    foreach ($target in $filteredrepTargets) {
    $name = $target.Name -replace ' ', '_'
    $totalGB = $target.'Total (GB)'
    $freeGB = $target.'Free (GB)'
    $usedGB = $totalGB - $freeGB 
    $prctUsed = $target.'Used (%)'

    # Convert Warning and Critical thresholds to percentages of the total GB
    $warningGB = [Math]::Round(($Warning / 100) * $totalGB, 2)
    $criticalGB = [Math]::Round(($Critical / 100) * $totalGB, 2)
    
    # Construct strings for the output
    $targetStats = "$name=${usedGB}GB;$warningGB;$criticalGB;0;$totalGB"
    $prctUsedStats = "${name}_prct_used=$prctUsed%;$Warning;$Critical"
    
    # Append to the output array
    $outputStats += "$targetStats $prctUsedStats"}

    $outputCritical = ($criticalRepTargets | Sort-Object { $_.'Free (%)' } | ForEach-Object {"$($_.Name) - Free : $($_.'Free (%)')% ($($_.'Free (GB)')/$($_.'Total (GB)') GB)"}) -join ", "
    $outputWarning = ($warningRepTargets | Sort-Object { $_.'Free (%)' } | ForEach-Object {"$($_.Name) - Free : $($_.'Free (%)')% ($($_.'Free (GB)')/$($_.'Total (GB)') GB)"}) -join ", "
    #$outputOk = ($okRepTargets | Sort-Object { $_.'Free (%)' } | ForEach-Object {"$($_.Name) - Free : $($_.'Free (%)')% ($($_.'Free (GB)')/$($_.'Total (GB)') GB)"}) -join ", "
       
    If ($criticalRepTargets.count -gt 0) {
        Exit-Critical "$($criticalRepTargets.count) replica target(s) are in critical state : $outputCritical|$outputStats"
    }ElseIf ($warningRepTargets.count -gt 0) {
        Exit-Warning "$($warningRepTargets.count) replica target(s) are in warning state : $outputWarning|$outputStats"
    }Else{
        Exit-OK "All replica target(s) are in ok state|$outputStats"
    }

}Else{
    Exit-Unknown "No replica target found"
}