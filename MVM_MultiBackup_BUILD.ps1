# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
#REMPLIR DESCRIPTION
#
# ====================================================================

#region Arguments
param (
    [int]$RPO # Recovery Point Objective (hours)
)
#endregion

#region Validate Parameters
# Validate the $RPO parameter to ensure it's a positive integer
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}
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


  