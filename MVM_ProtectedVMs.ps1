# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
#REMPLIR DESCRIPTION
#
# ====================================================================

#region Arguments
param (
    [string]$excludeVM,
    [string]$excludeFolder,
    [string]$excludeTag,
    [string]$excludeCluster,
    [string]$excludeDC,
    [int]$RPO
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_ProtectedVMs.ps1"
$localScriptPath = $MyInvocation.MyCommand.Path
#endregion

#region Functions      
    #region Fonction Get-VersionFromScript
        function Get-VersionFromScript {
            param (
                [string]$scriptContent
            )
            # Recherche une ligne contenant '#Version X.Y.Z'
            if ($scriptContent -match "# Version\s*:\s*([\d\.]+)") {
                return $matches[1]
            } else {
                Write-Error "Impossible de trouver la version dans le script."
                return $null
            }
        }
    #endregion

    #region Fonctions Exit NRPE
        function Exit-OK {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "OK - $message"
            }
            exit 0
        }

        function Exit-Warning {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "WARNING - $message"
            }
            exit 1
        }

        function Exit-Critical {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "CRITICAL - $message"
            }
            exit 2
        }

        function Exit-Unknown {
            param (
                [string]$message
            )

            if ($message) {
                Write-Host "UNKNOWN - $message"
            }
            exit 3
        }
    #endregion

#endregion

#region Update 
# --- Extraction de la version locale ---
$localScriptContent = Get-Content -Path $localScriptPath -Raw
$localVersion = Get-VersionFromScript -scriptContent $localScriptContent

# --- Récupération du script distant ---
$remoteScriptContent = Invoke-RestMethod -Uri $scriptFileURL -Headers $headers -UseBasicParsing

# --- Extraction de la version distante ---
$remoteVersion = Get-VersionFromScript -scriptContent $remoteScriptContent

# --- Comparaison des versions et mise à jour ---
if ($localVersion -ne $remoteVersion) {
    try {
        # Écrase le script local avec le contenu distant
        $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
    } catch {
    }
}
#endregion

#region Variables
$vbrServer = "localhost"
$excludeVMarray = @()
$excludeFolderarray = @()
$excludeTagArray = @()
$excludeClusterarray = @()
$excludeDCarray = @()
$excludeVM_regex = ""
$excludeFolder_regex = ""
$excludeTag_regex = ""
$excludeVMarray = $excludeVM -split ','
$excludeFolderarray = $excludeFolder -split ','
$excludeTagArray = $excludeTag -split ','
$excludeClusterarray = $excludeCluster -split ','
$excludeDCarray = $excludeDC -split ','
$vmWithTags = @()
$tagDictionary = @{}
$backupVmList = @()
$vmStatus = @()
#endregion

#region Connect to VBR server
$OpenConnection = (Get-VBRServerSession).Server
If ($OpenConnection -ne $vbrServer){
    Disconnect-VBRServer
    Try {
        Connect-VBRServer -server $vbrServer -ErrorAction Stop
    } Catch {
        Exit-Critical "Unable to connect to the VBR server."
    exit
    }
}
#endregion

$vms = Find-VBRViEntity | Where-Object { $_.Type -eq "Vm" }
$tags = Find-VBRViEntity -Tags | Where-Object { $_.Type -eq "Vm" }

foreach ($tag in $tags) {
    $tagDictionary[$tag.Id] = $tag.Path
}

foreach ($vm in $vms) {
    $vmWithTags += [PSCustomObject]@{
        Name = $vm.Name
        Path = $vm.Path
        Folder = $vm.VmFolderName
        Tags = if ($tagDictionary.ContainsKey($vm.Id)) { $tagDictionary[$vm.Id] } else { "None" }
    }
}

$backupJobTypes = @("Backup")
foreach ($session in ([Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetAll()) | Where-Object {
    ($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or $_.State -eq "Working") -and $_.JobType -in $backupJobTypes
}) {
    $taskSession = Get-VBRTaskSession -Session $session.Id
    $taskSession | ForEach-Object {
        $backupVmList += [PSCustomObject]@{
            Name     = $_.Name
            Status   = $_.Status
            JobName  = $session.JobName
            EndTime  = $session.EndTime
        }
    }
}

$latestBackupVmList = $backupVmList | 
    Group-Object -Property Name | 
    ForEach-Object {
        $_.Group | Sort-Object -Property EndTime -Descending | Select-Object -First 1
    }

foreach ($vm in $vmWithTags) {
        $status = ($latestBackupVmList | Where-Object { $_.Name -eq $vm.Name }).Status
        $vmStatus += [PSCustomObject]@{
            Name   = $vm.Name
            Path   = $vm.Path
            Folder = $vm.Folder
            Tags   = $vm.Tags
            Status = if ($status) { $status } else { "Failed" }
        }
    
}

$excludeVM_regex = ('(?i)^(' + (($excludeVMarray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeFolder_regex = ('(?i)^(' + (($excludeFolderarray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeTag_regex = ('(?i)^(' + (($excludeTagArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeCluster_regex = ('(?i)^(' + (($excludeClusterarray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
$excludeDC_regex = ('(?i)^(' + (($excludeDCarray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"

$filteredVmTable = $vmStatus | Where-Object {
    ($_.Name -notmatch $excludeVM_regex) -and
    ($_.Folder -notmatch $excludeFolder_regex) -and
    ($_.Tags.Split("\")[2] -notmatch $excludeTag_regex) -and
    ($_.Path.Split("\")[2] -notmatch $excludeCluster_regex) -and
    ($_.Path.Split("\")[1] -notmatch $excludeDC_regex)
}

$successVMs = @($filteredVmTable | Where-Object {$_.Status -eq "Success"})
$warnVMs = @($filteredVmTable | Where-Object {$_.Status -eq "Warning"})
$missingVMs = @($filteredVmTable | Where-Object {$_.Status -eq "Failed"})

$vbrMasterHash = @{
    WarningVM = @($warnVMs).Count
    ProtectedVM = @($successVMs).Count
    UnprotectedVM = @($missingVMs).Count
}

$outputCrit = ($missingVMs | ForEach-Object { "$($_.Name)" }) -join ","
$outputWarn = ($warnVMs | ForEach-Object { "$($_.Name)" }) -join ","

$vbrMasterObj = New-Object -TypeName PSObject -Property $vbrMasterHash

if ($vbrMasterObj.UnprotectedVM -gt 0) {Exit-Critical "Unprotected VM : $($vbrMasterObj.UnprotectedVM), ($($outputCrit))"} 
elseif ($vbrMasterObj.UnprotectedVM -eq 0) {
    if ($warningCount -gt 0) {Exit-warning "VM in warning : $($vbrMasterObj.WarningVM),($($outputWarn))"}
    else {Exit-ok "All VM are protected ($($vbrMasterObj.ProtectedVM))"}} 
else {Exit-unknown "Unknown issue occurred"}