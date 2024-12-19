# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# DESCRIPTION:
# This PowerShell script monitors the protection status of virtual machines (VMs)
# in Veeam Backup & Replication by comparing the successful backups with the VMs
# present in the vCenter. It identifies VMs that are unprotected or in a warning state.
#
# PARAMETERS:
# - RPO: Defines the backup analysis period (in hours). Default is 24 hours.
# - ExcludedVMs: A comma-separated list of VM names to exclude. You can use the '*' wildcard for partial matches.
# - ExcludedFolders: A comma-separated list of folders to exclude. You can use the '*' wildcard for partial matches.
# - ExcludedTags: A comma-separated list of tags to exclude. You can use the '*' wildcard for partial matches.
# - ExcludedClusters: A comma-separated list of clusters to exclude. You can use the '*' wildcard for partial matches.
# - ExcludedDataCenters: A comma-separated list of data centers to exclude. You can use the '*' wildcard for partial matches.
#
# RETURNS:
# - Critical: At least one VM is unprotected (failed or missing backup).
# - Warning: At least one VM is in a warning state.
# - OK: All VMs are protected.
# - Unknown: An error occurred while retrieving backup session data.
#
# ====================================================================


#region Parameters
param (
    [string]$ExcludedVMs = "",   # VMs to exclude from monitoring
    [string]$ExcludedFolders = "",  # Folders to exclude from monitoring
    [string]$ExcludedTags = "",   # Tags to exclude from monitoring
    [string]$ExcludedClusters = "",  # Clusters to exclude from monitoring
    [string]$ExcludedDataCenters = "",  # Data centers to exclude from monitoring
    [int]$RPO = 24  # Recovery Point Objective (hours)
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
#endregion

#region Validate Parameters
# Validate that the RPO parameter is a positive integer
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}

# Validate that the exclusion parameters contain only valid characters
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

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
# Arrays to hold the exclusion lists and backup results
$excludedVMsArray = $ExcludedVMs -split ','
$excludedFoldersArray = $ExcludedFolders -split ','
$excludedTagsArray = $ExcludedTags -split ','
$excludedClustersArray = $ExcludedClusters -split ','
$excludedDCsArray = $ExcludedDataCenters -split ','

$vmTagMapping = @{}  # Dictionary to map VM tags to VM IDs
$backupResults = @()  # Array to hold backup results
$vmList = @()  # Array to hold VM details
$allVMsStatuses = @()  # Array to hold statuses of all VMs
#endregion

#region Data Collection
# Retrieve all virtual machines (VMs) and their associated tags
$vms = Find-VBRViEntity | Where-Object { $_.Type -eq "Vm" }
$tags = Find-VBRViEntity -Tags | Where-Object { $_.Type -eq "Vm" }

# Map tags to VM IDs
foreach ($tag in $tags) {
    $vmTagMapping[$tag.Id] = $tag.Path
}

# Create a list of VMs with details like Name, Path, Folder, and Tags
foreach ($vm in $vms) {
    $vmList += [PSCustomObject]@{
        Name   = $vm.Name
        Path   = $vm.Path
        Folder = $vm.VmFolderName
        Tags   = if ($vmTagMapping[$vm.Id]) { $vmTagMapping[$vm.Id] } else { "None" }
    }
}

$Type = @("Backup")  # Define the backup job type
# Retrieve backup sessions based on the specified RPO
$backupSessions = [Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetAll() | 
    Where-Object {($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -eq "Working") -and $_.JobType -in $Type}

# Fetch task sessions for each backup session
foreach ($session in $backupSessions) {
    $taskSessions = Get-VBRTaskSession -Session $session.Id
    foreach ($task in $taskSessions) {
        # Store backup results
        $backupResults += [PSCustomObject]@{
            Name     = $task.Name
            Status   = $task.Status
            JobName  = $session.JobName
            EndTime  = $session.EndTime
        }
    }
}

# Get the most recent backup results for each VM
$latestBackupResults = $backupResults | Group-Object -Property Name | ForEach-Object { 
    $_.Group | Sort-Object -Property EndTime -Descending | Select-Object -First 1}

# Compare VM list with backup results to determine status (Success, Warning, Missing)
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
#endregion
#region Exclusion Logic
# Create regex patterns to exclude VMs, folders, tags, clusters, and data centers
$excludeVM_regex = ('(?i)^(' + (($excludedVMsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeFolder_regex = ('(?i)^(' + (($excludedFoldersArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeTag_regex = ('(?i)^(' + (($excludedTagsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeCluster_regex = ('(?i)^(' + (($excludedClustersArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeDC_regex = ('(?i)^(' + (($excludedDCsArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"

# Filter out excluded VMs and other items using the regex patterns
$filteredVMsStatuses = $allVMsStatuses | Where-Object {
    ($_.Name -notmatch $excludeVM_regex) -and
    ($_.Folder -notmatch $excludeFolder_regex) -and
    ($_.Tags.Split("\")[2] -notmatch $excludeTag_regex) -and
    ($_.Path.Split("\")[2] -notmatch $excludeCluster_regex) -and
    ($_.Path.Split("\")[1] -notmatch $excludeDC_regex)
}
#endregion

#region Status Evaluation
# Classify VMs into success, warning, and missing states
$successVMs = $filteredVMsStatuses | Where-Object {$_.Status -eq "Success"}
$warnVMs = $filteredVMsStatuses | Where-Object {$_.Status -eq "Warning"}
$missingVMs = $filteredVMsStatuses | Where-Object {$_.Status -in @("Failed", "Missing")}

# Count and output results based on VM statuses
$countVMsStatuses = @{
    WarningVMs     = $warnVMs.Count
    ProtectedVMs   = $successVMs.Count
    UnprotectedVMs = $missingVMs.Count
}

$outputCrit = ($missingVMs.Name) -join ","
$outputWarn = ($warnVMs.Name) -join ","

$statisticsMessage = "'ProtectedVms'=$($countVMsStatuses.ProtectedVMs) 'WarningVMs'=$($countVMsStatuses.WarningVMs) 'UnprotectedVMs'=$($countVMsStatuses.UnprotectedVMs)"

# Exit with appropriate status depending on VM statuses
if ($countVMsStatuses.UnprotectedVMs -gt 0) {
    Exit-Critical "$($countVMsStatuses.UnprotectedVMs) Unprotected VM(s): $outputCrit|$statisticsMessage"
} elseif ($countVMsStatuses.WarningVMs -gt 0) {
    Exit-Warning "$($countVMsStatuses.WarningVMs) VM(s) in warning state: $outputWarn|$statisticsMessage"
} else {
    Exit-Ok "All VMs are protected ($($countVMsStatuses.ProtectedVMs))|$statisticsMessage"
}
#endregion
