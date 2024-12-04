# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.1
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
# 
# Ce script permet de surveiller l'état des licences installées sur un serveur Veeam Backup & Replication.
# Il vérifie le type de licence, la date d'expiration, ainsi que le nombre de jours restants avant l'expiration.
# Des seuils de warning et critique peuvent être configurés pour générer des alertes en fonction des jours restants.
#
# ====================================================================

#region Arguments
param (
    [int]$Warning,
    [int]$Critical
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_License.ps1"
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

    #region Fonction Get-VeeamSupportDate
    Function Get-VeeamSupportDate {
        # Query for license info
        $licenseInfo = Get-VBRInstalledLicense
        if (-not $licenseInfo) {
            Exit-Unknown "Unable to retrieve Veeam license information." 
        }
    
        # Extract license type
        $type = $licenseInfo.Type
        $date = $null
    
        # Determine expiration date based on license type
        switch ($type) {
            'Perpetual'    { $date = $licenseInfo.SupportExpirationDate }
            'Evaluation'   { $date = $null } # Evaluation licenses have no defined expiration
            'Subscription' { $date = $licenseInfo.ExpirationDate }
            'Rental'       { $date = $licenseInfo.ExpirationDate }
            'NFR'          { $date = $licenseInfo.ExpirationDate }
            default        { Exit-Critical "Unknown license type: $type" }
        }
    
        # Create custom object with details
        [PSCustomObject]@{
            LicType    = $type
            ExpDate    = if ($date) { $date.ToShortDateString() } else { "No Expiration" }
            DaysRemain = if ($date) { ($date - (Get-Date)).Days } else { "Unlimited" }
        }
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

#region Check params
if ($Warning -le $Critical) {
    Exit-Critical "Invalid parameters: 'Warning' must be greater than 'Critical'. Please provide valid values."
}

if ($Critical -le 0 -or $Warning -le 0) {
    Exit-Critical "Invalid parameters: 'Warning' and 'Critical' values must be greater than 0."
}
#endregion

# Get License Info
$arrLicense = Get-VeeamSupportDate | Select-Object `
    @{Name = "Type"; Expression = { $_.LicType }},
    @{Name = "Expiry Date"; Expression = { $_.ExpDate }},
    @{Name = "Days Remaining"; Expression = { $_.DaysRemain }},
    @{Name = "Status"; Expression = {
        if ($_.LicType -eq "Evaluation") {"OK"}
        elseif ($_.DaysRemain -lt $Critical) {"Critical"}
        elseif ($_.DaysRemain -lt $Warning) {"Warning"}
        else {"OK"}
    }}

# Process license status
if ($arrLicense.Type -ne "Evaluation") {
    $status = $arrLicense.Status
    $remainingDays = $arrLicense.'Days Remaining'

    switch ($status) {
        "OK"        {Exit-OK "Support License Days Remaining: $remainingDays."}
        "Warning"   {Exit-Warning "Support License Days Remaining: $remainingDays."}
        "Critical"  {Exit-Critical "Support License Days Remaining: $remainingDays."}
        default     {Exit-Critical "Support License is expired or in an invalid state."}
    }
} else {
    Exit-OK "Evaluation License is active with no expiration."
}