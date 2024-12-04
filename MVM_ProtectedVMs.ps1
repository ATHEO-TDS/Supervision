# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.2
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
#REMPLIR DESCRIPTION
#
# ====================================================================

#region Parameters
param (
    [string]$ExcludedVMs,
    [string]$ExcludedFolders,
    [string]$ExcludedTags,
    [string]$ExcludedClusters,
    [string]$ExcludedDataCenters,
    [int]$RPO
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$remoteScriptURL = "$repoURL/MVM_ProtectedVMs.ps1"
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
$excludedVMsArray = $ExcludedVMs -split ','
$excludedFoldersArray = $ExcludedFolders -split ','
$excludedTagsArray = $ExcludedTags -split ','
$excludedClustersArray = $ExcludedClusters -split ','
$excludedDCsArray = $ExcludedDataCenters -split ','

$vmTagMapping = @{}
$backupResults = @()
$vmList = @()
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

#region Data Collection
# Fetch VMs and their tags
$vms = Find-VBRViEntity | Where-Object { $_.Type -eq "Vm" }
$tags = Find-VBRViEntity -Tags | Where-Object { $_.Type -eq "Vm" }

foreach ($tag in $tags) {
    $vmTagMapping[$tag.Id] = $tag.Path
}

foreach ($vm in $vms) {
    $vmList += [PSCustomObject]@{
        Name   = $vm.Name
        Path   = $vm.Path
        Folder = $vm.VmFolderName
        Tags   = if ($vmTagMapping[$vm.Id]) { $vmTagMapping[$vm.Id] } else { "None" }
    }
}

$Type = @("Backup")
# Fetch backup sessions
$backupSessions = [Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetAll() | 
    Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -eq "Working") -and $_.JobType -in $Type}

foreach ($session in $backupSessions) {
    $taskSessions = Get-VBRTaskSession -Session $session.Id
    foreach ($task in $taskSessions) {
        $backupResults += [PSCustomObject]@{
            Name     = $task.Name
            Status   = $task.Status
            JobName  = $session.JobName
            EndTime  = $session.EndTime
        }
    }
}

$latestBackupResults = $backupResults | Group-Object -Property Name | ForEach-Object { 
    $_.Group | Sort-Object -Property EndTime -Descending | Select-Object -First 1}

foreach ($vm in $vmList) {
        $statusObject = $latestBackupResults | Where-Object { $_.Name -eq $vm.Name }
        $status = if ($statusObject) { $statusObject.Status } else { "Missing" }

        $allVMsStatuses += [PSCustomObject]@{
            Name   = $vm.Name
            Path   = $vm.Path
            Folder = $vm.Folder
            Tags   = $vm.Tags
            Status = $status
        }
    
}

$excludeVM_regex = ('(?i)^(' + (($excludedVMsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeFolder_regex = ('(?i)^(' + (($excludedFoldersArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeTag_regex = ('(?i)^(' + (($excludedTagsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeCluster_regex = ('(?i)^(' + (($excludedClustersArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeDC_regex = ('(?i)^(' + (($excludedDCsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"

$filteredVMsStatuses = $allVMsStatuses | Where-Object {
    ($_.Name -notmatch $excludeVM_regex) -and
    ($_.Folder -notmatch $excludeFolder_regex) -and
    ($_.Tags.Split("\")[2] -notmatch $excludeTag_regex) -and
    ($_.Path.Split("\")[2] -notmatch $excludeCluster_regex) -and
    ($_.Path.Split("\")[1] -notmatch $excludeDC_regex)
}

$successVMs = $filteredVMsStatuses | Where-Object {$_.Status -eq "Success"}
$warnVMs = $filteredVMsStatuses | Where-Object {$_.Status -eq "Warning"}
$missingVMs = $filteredVMsStatuses | Where-Object {$_.Status -in @("Failed", "Missing")}

$countVMsStatuses = @{
    WarningVMs     = $warnVMs.Count
    ProtectedVMs   = $successVMs.Count
    UnprotectedVMs = $missingVMs.Count
}

$outputCrit = ($missingVMs.Name) -join ","
$outputWarn = ($warnVMs.Name) -join ","

$statisticsMessage = "'ProtectedVms'=$($countVMsStatuses.ProtectedVMs) 'WarningVMs'=$($countVMsStatuses.WarningVMs) 'UnprotectedVMs'=$($countVMsStatuses.UnprotectedVMs)"

if ($countVMsStatuses.UnprotectedVMs -gt 0) {
    Exit-Critical "$($countVMsStatuses.UnprotectedVMs) Unprotected VM(s): $outputCrit|$statisticsMessage"
} elseif ($countVMsStatuses.WarningVMs -gt 0) {
    Exit-Warning "$($countVMsStatuses.WarningVMs) VM(s) in warning state: $outputWarn|$statisticsMessage"
} else {
    Exit-Ok "All VMs are protected ($($countVMsStatuses.ProtectedVMs))|$statisticsMessage"
}
