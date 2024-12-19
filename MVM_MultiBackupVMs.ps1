# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.0
# Creation Date: 2024-11-29
# Last Update: 2024-12-19
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# DESCRIPTION:
# This PowerShell script identifies VMs backed up by multiple jobs within a specified time window (RPO).
# It evaluates backup sessions completed in the last $RPO hours and flags VMs associated with more than one backup job. 
#
# PARAMETERS:
# - RPO: Defines the backup analysis period (in hours). Default is 24 hours.
# - ExcludedVMs: A comma-separated list of VM names to exclude from monitoring.
#
# RETURNS:
# - OK: No VMs are found with multiple backup jobs within the specified RPO.
# - Critical: At least one VM is found being backed up by multiple jobs within the specified RPO.
# - Unknown: Indicates an issue retrieving backup session information.
#
# ====================================================================

#region Arguments
param (
    [int]$RPO = 24, # Recovery Point Objective (hours)
    [string]$ExcludedVMs = "" # Comma-separated list of VM names to exclude from monitoring
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

# Retrieves all VMs backed up by multiple jobs within the past $RPO hours
function Get-VMsBackedUpByMultipleJobs {
    # Retrieve all backup sessions matching the criteria (RPO, job type, and status)
    $backupSessions = ([Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetAll()) | 
        Where-Object { 
            ($_.JobType -eq "Backup") -and 
            ($_.EndTime -ge (Get-Date).AddHours(-$RPO) -or 
            $_.CreationTime -ge (Get-Date).AddHours(-$RPO) -or 
            $_.State -eq "Working") 
        }

    # Retrieve task sessions associated with the backup sessions
    $taskSessions = $backupSessions | ForEach-Object {
        Get-VBRTaskSession -Session $_.Id
    }

    # Process and filter task sessions to identify VMs associated with multiple jobs
    $taskSessions | Select-Object Name, 
        @{Name="VMID"; Expression = {$_.Info.ObjectId}}, 
        JobName -Unique |
        Group-Object Name, VMID | 
        Where-Object {$_.Count -gt 1} |
        Select-Object -ExpandProperty Group
}
#endregion

#region Validate Parameters
# Validate that the RPO parameter is a positive integer
if ($RPO -lt 1) {
    Exit-Critical "Invalid parameter: 'RPO' must be greater than or equal to 1 hour. Please provide a valid value."
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$ExcludedVMsArray = $ExcludedVMs -split ',' # Parse the excluded VMs into an array
$jobsByVM = @{} # Dictionary to store job names by VM
#endregion

try {
    # Retrieve VMs backed up by multiple jobs, excluding those specified in $ExcludedVMs
    $vmWithMultipleBackups = Get-VMsBackedUpByMultipleJobs | Where-Object { -not ($_.Name -in $ExcludedVMsArray) }

    if (-not $vmWithMultipleBackups) {
        # Exit with OK status if no VMs are found
        Exit-OK "No VMs found with multiple backup jobs within RPO."
    }
    
    # Process the results and group job names by VM
    foreach ($job in $vmWithMultipleBackups) {
        if (-not $jobsByVM.ContainsKey($job.Name)) {
            $jobsByVM[$job.Name] = @($job.JobName)
        } else {
            $jobsByVM[$job.Name] += $job.JobName
        }
    }

    # Prepare output for VMs flagged as critical
    $outputcrit = @()
    foreach ($vm in $jobsByVM.Keys) {
        $jobNames = $jobsByVM[$vm] -join "," # Combine job names into a single string
        $outputcrit += "[$vm : $jobNames]" # Format for reporting
    }
    
    # Exit with Critical status, reporting flagged VMs
    Exit-Critical "VMs Backed Up by Multiple Jobs within RPO: $($outputcrit -join ",")"
    
}Catch{
    # Exit with Critical status if an error occurs
    Exit-Critical "An error occurred while retrieving VMs: $($_.Exception.Message)"
}