# ====================================================================
# Auteur : Tiago DA SILVA - ATHEO INGENIERIE
# Version : 1.0.0
# Date de création : 2024-11-29
# Dernière mise à jour : 2024-12-02
# Dépôt GitHub : https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
#
# ====================================================================

#region Parameters
param (
    [string]$ExcludedProxy
)
#endregion

#region Update Configuration
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$remoteScriptURL = "$repoURL/MVM_Proxies.ps1"
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

# Function to Get Proxy Informations
Function Get-VBRProxyInfo {
    [CmdletBinding()]
    param (
      [Parameter(Position=0, ValueFromPipeline=$true)]
      [PSObject[]]$Proxy
    )
    Begin {
      $outputAry = @()  # Crée un tableau vide pour les résultats
      Function Add-Object {
        param ([PsObject]$inputObj)
        $ping = New-Object system.net.networkinformation.ping
        $isIP = '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'
        If ($inputObj.Host.Name -match $isIP) {
          $IPv4 = $inputObj.Host.Name
        } Else {
          $DNS = [Net.DNS]::GetHostEntry("$($inputObj.Host.Name)")
          $IPv4 = ($DNS.get_AddressList() | Where-Object {$_.AddressFamily -eq "InterNetwork"} | Select-Object -First 1).IPAddressToString
        }
        $pinginfo = $ping.send("$($IPv4)")
        If ($pinginfo.Status -eq "Success") {
          $hostAlive = "Alive"
          $response = $pinginfo.RoundtripTime
        } Else {
          $hostAlive = "Dead"
          $response = $null
        }
        If ($inputObj.IsDisabled) {
          $enabled = "False"
        } Else {
          $enabled = "True"
        }
        $vPCFuncObject = New-Object PSObject -Property @{
          Name = $inputObj.Name
          Status  = $hostAlive
          IP = $IPv4
          Response = $response
          Enabled = $enabled
        }
        Return $vPCFuncObject
      }
    }
    Process {
      foreach ($p in $Proxy) {
        $outputObj = Add-Object $p
        $outputAry += $outputObj  # Ajoute l'objet au tableau
      }
    }
    End {
      return $outputAry  # Retourne un tableau d'objets
    }
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
$excludedProxyArray = $ExcludedProxy -split ','
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

$proxyList = @(Get-VBRViProxy | Get-VBRProxyInfo)

If ($proxyList.count -gt 0) {
    $excludeProxy_regex = ('(?i)^(' + (($excludedProxyArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
    $filteredProxyList = $proxyList | Where-Object {$_.Name -notmatch $excludeProxy_regex}
    $aliveProxy = $filteredProxyList | Where-Object {$_.Status -eq "Alive"}
    $deadProxy = $filteredProxyList | Where-Object {$_.Status -eq "Dead"}
    $outputOk = ($aliveProxy.Name) -join ","
    $outputCrit = ($deadProxy.Name) -join ","    

    if ($deadProxy.count -gt 0) {
        Exit-Critical "$($deadProxy.count) proxies are dead: $outputCrit"
    }else {
        Exit-Ok "All the listed proxies are alive: $outputOk"
    }

}Else{
    Exit-Unknown "No Proxy Found"

}