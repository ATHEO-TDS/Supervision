# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
#
#
# ====================================================================

# Update-Script.psm1
function Update-Script {
    param (
        [string]$localScriptPath,
        [string]$remoteScriptURL
    )

    #region Module Update
    $gitModuleURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main/MVM_UpdateScript.psm1"
    $localModulePath = "./MVM_UpdateScript.psm1"
    write-host "localModulePath $localModulePath"

    # Fetch local module version
    $localModuleContent = Get-Content -Path $localModulePath -Raw
    $localModuleVersion = Get-ScriptVersion -ScriptContent $localModuleContent

    # Fetch git module version
    $gitModuleContent = Invoke-RestMethod -Uri $gitModuleURL -UseBasicParsing
    $gitModuleVersion = Get-ScriptVersion -ScriptContent $gitModuleContent

    # Update module if versions differ
    if ($localModuleVersion -ne $gitModuleVersion) {
        try {
            $gitModuleContent | Set-Content -Path $localModulePath -Encoding UTF8 -Force
        } catch {
            Write-Host "Error updating update module."
            Write-Host "Details: $($_.Exception.Message)"
        }
    }
    #endregion

    #region Script Udpate
    # Fetch local script version
    $localScriptContent = Get-Content -Path $localScriptPath -Raw
    $localVersion = Get-ScriptVersion -Content $localScriptContent

    # Fetch remote script version
    $remoteScriptContent = Invoke-RestMethod -Uri $remoteScriptURL -UseBasicParsing
    $remoteVersion = Get-ScriptVersion -Content $remoteScriptContent

    # Update script if versions differ
    if ($localVersion -ne $remoteVersion) {
        try {
            $remoteScriptContent | Set-Content -Path $localScriptPath -Encoding UTF8 -Force
        } catch {
            Write-Host "Error updating script."
            Write-Host "Details: $($_.Exception.Message)"
        }
    }
    #endregion
}

# Function to extract version from a script file
function Get-ScriptVersion {
    param (
        [string]$Content
    )
    if ($Content -match "# Version\s*:\s*([\d\.]+)") {
        return $matches[1]
    } else {
        return $null
    }
}
