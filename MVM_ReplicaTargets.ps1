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
    [int]$Warning,
    [int]$Critical,
    [string]$ExcludedTargets
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
          $objoutput = New-Object -TypeName PSObject -Property @{
            Datastore = $obj.ViReplicaTargetOptions.DatastoreName
            StorageFree = [Math]::Round([Decimal]$dtstr.FreeSpace/1GB,2)
            StorageTotal = [Math]::Round([Decimal]$dtstr.Capacity/1GB,2)
            FreePercentage = [Math]::Round(($dtstr.FreeSpace/$dtstr.Capacity)*100)
          }
          $dsAry = $dsAry + $obj.ViReplicaTargetOptions.DatastoreName
          $outputAry = $outputAry + $objoutput
        } Else {
          return
        }
      }
    }
    END {
      $outputAry | Select-Object Target, Datastore, StorageFree, StorageTotal, FreePercentage
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
      @{Name="Status"; Expression = {
        If ($_.FreePercentage -lt $Critical) {"Critical"}
        ElseIf ($_.StorageTotal -eq 0)  {"Warning"}
        ElseIf ($_.FreePercentage -lt $Warning) {"Warning"}
        ElseIf ($_.FreePercentage -eq "Unknown") {"Unknown"}
        Else {"OK"}
        }
      }


########### TEST

$repTargets = @(
    [PSCustomObject]@{
        Name          = "Target01"
        'Free (GB)'   = 50
        'Total (GB)'  = 1000
        'Free (%)'    = 5
        Status        = "Critical"
    },
    [PSCustomObject]@{
        Name          = "Target02"
        'Free (GB)'   = 200
        'Total (GB)'  = 1000
        'Free (%)'    = 20
        Status        = "Warning"
    },
    [PSCustomObject]@{
        Name          = "Target03"
        'Free (GB)'   = 500
        'Total (GB)'  = 1000
        'Free (%)'    = 50
        Status        = "OK"
    },
    [PSCustomObject]@{
        Name          = "Target04"
        'Free (GB)'   = 0
        'Total (GB)'  = 0
        'Free (%)'    = "Unknown"
        Status        = "Unknown"
    }
)

$repTargets


########### TEST



If ($repTargets.count -gt 0) {

    $ExcludedTargets_regex = ('(?i)^(' + (($ExcludedTargetsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
    $filteredrepTargets = $repTargets | Where-Object {$_.Name -notmatch $ExcludedTargets_regex}
    $criticalRepTargets = $filteredrepTargets | Where-Object {$_.Status -eq "Critical"}
    $warningRepTargets = $filteredrepTargets | Where-Object {$_.Status -eq "Warning"}
    $unknownRepTargets = $filteredrepTargets | Where-Object {$_.Status -eq "Unknown"}
    $okRepTargets = $filteredrepTargets | Where-Object {$_.Status -eq "OK"}

    $outputCritical = $criticalRepTargets | ForEach-Object {"$($_.Name) - Free : $($_.'Free (%)')% ($($_.'Free (GB)')/$($_.'Total (GB)') GB)"} -join ", "
    $outputWarning = $warningRepTargets | ForEach-Object {"$($_.Name) - Free : $($_.'Free (%)')% ($($_.'Free (GB)')/$($_.'Total (GB)') GB)"} -join ", "
    $outputUnknown = $unknownRepTargets | ForEach-Object {$($_.Name)} -join ", "
    $outputOk = $okRepTargets | ForEach-Object {"$($_.Name) - Free : $($_.'Free (%)')% ($($_.'Free (GB)')/$($_.'Total (GB)') GB)"} -join ", "
       
    If ($criticalRepTargets.count -gt 0) {
        Exit-Critical "$($criticalRepTargets.count) replica target(s) are in critical state : $outputCrit"
    }ElseIf ($warningRepTargets.count -gt 0) {
        Exit-Warning ""
    }ElseIf($unknownRepTargets.count -gt 0 ){
        Exit-Unknown ""
    }Else{
        Exit-OK ""
    }

}Else{
    Exit-Unknown "No replica target found"
}











If ($repTargets.status -match "Critical") {
    handle_critical "Veeam Repository Status : $output"
} ElseIf ($repTargets.status -match "Warning") {
    handle_warning "Veeam Repository Status : $output"  
} ElseIf ($repTargets.status -match "OK") {
    handle_ok "Veeam Repository Status : $output"
} Else {
    handle_unknown "Unknown Status"
}