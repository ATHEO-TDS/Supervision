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
    [int]$RPO
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_MultiBackup.ps1"
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


  ########## EN COURS DE DEV 

$vmMultiJobs = Get-VBRBackupSession |
    Where-Object {
        ($_.JobType -eq "Backup") -and (
            $_.EndTime -ge (Get-Date).AddHours(-$RPO) -or
            $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or
            $_.State -eq "Working"
        )
    } |
    Get-VBRTaskSession |
    Select-Object Name, @{Name="VMID"; Expression = {$_.Info.ObjectId}}, JobName -Unique |
    Group-Object Name, VMID |
    Where-Object { $_.Count -gt 1 } |
    Select-Object -ExpandProperty Group

$multiJobs = @(Get-MultiJob)

if ($multiJobs.Count -gt 0) {
    $jobsByVM = @{}

    foreach ($job in $multiJobs) {
        if (-not $jobsByVM.ContainsKey($job.Name)) {
            $jobsByVM[$job.Name] = @($job.JobName)
        } else {
            $jobsByVM[$job.Name] += $job.JobName
        }
    }

    $outputcrit = @()
    foreach ($vm in $jobsByVM.Keys) {
        $jobNames = $jobsByVM[$vm] -join ","
        $outputcrit += "[$vm : $jobNames]"
    }
    
    handle_critical "VMs Backed Up by Multiple Jobs within RPO: $($outputcrit -join ",")"
}
elseif ($multiJobs.Count -eq 0) {handle_ok "No VMs backed up by multiple jobs within RPO."}
else {handle_unknown "Unknown issue occurred."}


  