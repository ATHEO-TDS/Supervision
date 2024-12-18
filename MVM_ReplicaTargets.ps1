# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
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

#region Validate Parameters
# Validate that the Critical threshold is greater than the Warning threshold
if ($Critical -le $Warning) {
    Exit-Critical "Invalid parameter: Critical threshold ($Critical) must be greater than Warning threshold ($Warning)."
}
# Validate that the parameters are non-empty if they are provided
if ($ExcludedTargets -and $ExcludedTargets -notmatch "^[\w\.\,\s\*\-_]*$") {
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

# Retrieves all replica target informations
Function Get-VBRReplicaTarget {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true)]
        [PSObject[]]$InputObj
    )

    BEGIN {
        $outputAry = @()
        $dsAry = @()
    }

    PROCESS {
        foreach ($obj in $InputObj) {
            # Skip if the datastore has already been processed
            if ($dsAry -contains $obj.ViReplicaTargetOptions.DatastoreName) {
                continue
            }

            # Retrieve the datastore and calculate storage usage
            $esxi = $obj.GetTargetHost()
            $dtstr = $esxi | Find-VBRViDatastore -Name $obj.ViReplicaTargetOptions.DatastoreName
            $StorageFree = [Math]::Round([Decimal]$dtstr.FreeSpace / 1GB, 2)
            $StorageTotal = [Math]::Round([Decimal]$dtstr.Capacity / 1GB, 2)
            $StorageUsed = $StorageTotal - $StorageFree
            $FreePercentage = [Math]::Round(($dtstr.FreeSpace / $dtstr.Capacity) * 100)
            $UsedPercentage = 100 - $FreePercentage

            # Prepare the output object
            $objoutput = [PSCustomObject]@{
                Datastore       = $obj.ViReplicaTargetOptions.DatastoreName
                StorageFree     = $StorageFree
                StorageUsed     = $StorageUsed
                StorageTotal    = $StorageTotal
                FreePercentage  = $FreePercentage
                UsedPercentage  = $UsedPercentage
            }

            # Add the datastore name to the list and the result to the output array
            $dsAry += $obj.ViReplicaTargetOptions.DatastoreName
            $outputAry += $objoutput
        }
    }

    END {
        # Return the output
        $outputAry | Select-Object Datastore, StorageFree, StorageUsed, StorageTotal, FreePercentage, UsedPercentage
    }
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$ExcludedTargetsArray = $ExcludedTargets -split ','
$outputStats = @()
#endregion

try {
    # Retrieve all replica target informations
    $repTargets = Get-VBRJob -WarningAction SilentlyContinue | 
    Where-Object {$_.JobType -eq "Replica"} | 
    Get-VBRReplicaTarget | 
    Select-Object @{Name="Name"; Expression={$_.Datastore}},
                    @{Name='UsedStorageGB'; Expression={$_.StorageUsed}},
                    @{Name="FreeStorageGB"; Expression={$_.StorageFree}},
                    @{Name="TotalStorageGB"; Expression={$_.StorageTotal}},
                    @{Name="FreeStoragePercent"; Expression={$_.FreePercentage}},
                    @{Name="UsedStoragePercent"; Expression={$_.UsedPercentage}},
                    @{Name="Status"; Expression={
                    if ($_.UsedPercentage -ge $Critical) { "Critical" }
                    elseif ($_.UsedPercentage -ge $Warning) { "Warning" }
                    else { "OK" }
                    }}

    $ExcludedTargets_regex = ('(?i)^(' + (($ExcludedTargetsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
    $filteredrepTargets = $repTargets | Where-Object {$_.Name -notmatch $ExcludedTargets_regex}

    If ($filteredrepTargets.count -gt 0) {

        $criticalRepTargets = @($filteredrepTargets | Where-Object {$_.Status -eq "Critical"})
        $warningRepTargets = @($filteredrepTargets | Where-Object {$_.Status -eq "Warning"})

        foreach ($target in $filteredrepTargets) {
            $name = $target.Name -replace ' ', '_'
            $totalGB = $target.TotalStorageGB
            $usedGB = $target.UsedStorageGB
            $prctUsed = $target.UsedStoragePercent
        
            # Convert Warning and Critical thresholds to percentages of the total GB
            $warningGB = [Math]::Round(($Warning / 100) * $totalGB, 2)
            $criticalGB = [Math]::Round(($Critical / 100) * $totalGB, 2)
            
            # Construct strings for the output
            $targetStats = "$name=${usedGB}GB;$warningGB;$criticalGB;0;$totalGB"
            $prctUsedStats = "${name}_prct_used=$prctUsed%;$Warning;$Critical"
            
            # Append to the output array
            $outputStats += "$targetStats $prctUsedStats"
        }

        $outputCritical = ($criticalRepTargets | Sort-Object { $_.FreeStoragePercent } | ForEach-Object {
            "$($_.Name) - Used: $($_.UsedStoragePercent)% ($($_.FreeStorageGB)GB / $($_.TotalStorageGB)GB)"
        }) -join ", "
        
        $outputWarning = ($warningRepTargets | Sort-Object { $_.FreeStoragePercent } | ForEach-Object {
            "$($_.Name) - Used: $($_.UsedStoragePercent)% ($($_.FreeStorageGB)GB / $($_.TotalStorageGB)GB)"
        }) -join ", "

        If ($criticalRepTargets.count -gt 0) {
            Exit-Critical "$($criticalRepTargets.count) replica target(s) are in critical state : $outputCritical|$outputStats"
        }ElseIf ($warningRepTargets.count -gt 0) {
            Exit-Warning "$($warningRepTargets.count) replica target(s) are in warning state : $outputWarning|$outputStats"
        }Else{
            Exit-OK "All replica target(s) are in ok state|$outputStats"
        }
    }Else{
        Exit-Unknown "No replica target was found"
    }
}Catch{
    Exit-Critical "An error occurred: $_"
}