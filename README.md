# MyVeeamMonitoring

**MyVeeamMonitoring** is a set of PowerShell scripts designed to simplify the monitoring of Veeam Backup & Replication (VBR). These scripts help administrators track key Veeam metrics, detect issues quickly, and ensure smooth operations.

## Features

ADD LIST OF FEATURES 

## Requirements

- Veeam Backup & Replication installed and configured.
- PowerShell 5.1 or later.
- Access to Veeam Backup & Replication PowerShell module.

## Installation

1. Download the `Install-MyVeeamMonitoring.ps1` script from this repository.
2. Run the script with the appropriate parameters to set up the environment and create a scheduled task for daily script updates:

   ```powershell
   .\Install-MyVeeamMonitoring.ps1 -InstallDir "C:\Path\To\Directory"

## Usage
The scripts can now be run through the NRPE client, and they are configured to update automatically each day. To manually execute any script, use the following commands:

```powershell
.\MVM_AgentSessions.ps1 -RPO "$ARG1$"
.\MVM_BackupConfig.ps1 -RPO "$ARG1$"
.\MVM_CopySessions.ps1 -RPO "$ARG1$"
.\MVM_BackupSessions.ps1 -RPO "$ARG1$"
.\MVM_License.ps1 -Warning "$ARG1$" -Critical "$ARG2$"
.\MVM_MultiBackupVMs.ps1 -RPO "$ARG1$" -ExcludedVMs "$ARG2$"
.\MVM_ProtectedVMs.ps1 -RPO "$ARG1$" -ExcludedVMs "$ARG2$" -ExcludedFolders "$ARG3$" -ExcludedTags "$ARG4$" -ExcludedClusters "$ARG5$" -ExcludedDataCenters "$ARG6$" 
.\MVM_Proxies.ps1 -ExcludedProxy "$ARG1$"
.\MVM_ReplicaSessions.ps1 -RPO "$ARG1$"
.\MVM_ReplicaTargets.ps1 -Warning "$ARG1$" -Critical "$ARG2$" -ExcludedTargets "$ARG3$" 
.\MVM_Repositories.ps1 -Warning "$ARG1$" -Critical "$ARG2$" -ExcludedRepos "$ARG3$" 
.\MVM_SureBackupSessions.ps1 -RPO "$ARG1$"
.\MVM_TapeSessions.ps1 -RPO "$ARG1$"
