# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
# Ce script permet de surveiller l'état de protection des machines virtuelles (VM) 
# dans Veeam Backup & Replication. En comparant la liste des VM dont la sauvegarde est en success
# avec la liste des VMs présente sur le vCenter
#
# L'objectif est de garantir que toutes les VMs sont correctement protégées par des 
# sauvegardes et d'envoyer des alertes aux administrateurs via un système de supervision 
# si des problèmes sont détectés.
#
# Le script offre également la possibilité d'exclure certaines VMs, dossiers, tags, 
# clusters ou centres de données de l'analyse, pour une personnalisation en fonction 
# des besoins de l'environnement.
#
# Veuillez consulter le dépôt GitHub pour plus de détails et de documentation.
#
# ====================================================================


#region Parameters
param (
    [string]$ExcludedVMs = "",
    [string]$ExcludedFolders = "",
    [string]$ExcludedTags = "",
    [string]$ExcludedClusters = "",
    [string]$ExcludedDataCenters = "",
    [int]$RPO = 24
)
#endregion

#region Validate Parameters
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}

# Validate that the parameters are non-empty if they are provided
if ($ExcludedVMs -and $ExcludedVMs -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedVMs' contains invalid characters. Please provide a comma-separated list of VM names."
}
if ($ExcludedFolders -and $ExcludedFolders -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedFolders' contains invalid characters. Please provide a comma-separated list of folder names."
}
if ($ExcludedTags -and $ExcludedTags -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedTags' contains invalid characters. Please provide a comma-separated list of tag names."
}
if ($ExcludedClusters -and $ExcludedClusters -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedClusters' contains invalid characters. Please provide a comma-separated list of cluster names."
}
if ($ExcludedDataCenters -and $ExcludedDataCenters -notmatch "^[\w\.\,\s\*\-_]*$") {
    Exit-Critical "Invalid parameter: 'ExcludedDataCenters' contains invalid characters. Please provide a comma-separated list of data center names."
}
#endregion

#region Functions

# Extracts the version from script content
function Get-VersionFromScript {
    param ([string]$Content)
    if ($Content -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]
    }
    return $null
}

# Functions for exit codes (OK, Warning, Critical, Unknown)
function Exit-OK { param ([string]$message) if ($message) { Write-Host "OK - $message" } exit 0 }
function Exit-Warning { param ([string]$message) if ($message) { Write-Host "WARNING - $message" } exit 1 }
function Exit-Critical { param ([string]$message) if ($message) { Write-Host "CRITICAL - $message" } exit 2 }
function Exit-Unknown { param ([string]$message) if ($message) { Write-Host "UNKNOWN - $message" } exit 3 }

# Ensures connection to the VBR server
function Connect-VBRServerIfNeeded {
    $vbrServer = "localhost"
    $OpenConnection = (Get-VBRServerSession).Server

    if ($OpenConnection -ne $vbrServer) {
        Disconnect-VBRServer
        Try {
            Connect-VBRServer -server $vbrServer -ErrorAction Stop
        } Catch {
            Exit-Critical "Unable to connect to the VBR server."
        }
    }
}

#endregion

#region Update Script
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_ProctectedVMs.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path

# Extract and compare versions to update the script if necessary
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -Content $localScriptContent

$remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -UseBasicParsing
$remoteVersion = Get-VersionFromScript -Content $remoteScriptContent

if ($localVersion -ne $remoteVersion) {
    try {
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
        Write-Warning "Failed to update the script"
    }
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$excludedVMsArray = $ExcludedVMs -split ','
$excludedFoldersArray = $ExcludedFolders -split ','
$excludedTagsArray = $ExcludedTags -split ','
$excludedClustersArray = $ExcludedClusters -split ','
$excludedDCsArray = $ExcludedDataCenters -split ','
$vmTagMapping = @{}
$backupResults = @()
$vmList = @()
$allVMsStatuses = @()
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
