# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/ATHEO-TDS/MyVeeamMonitoring
# ====================================================================
#
#
# ====================================================================

#region Parameters
param (
    [string]$ExcludedProxy = ""
)
#endregion

#region Validate Parameters
# Validate that the parameters are non-empty if they are provided
if ($ExcludedProxy -and $ExcludedProxy -notmatch "^[\w\.\,\s\*\-_]*$") {
  Exit-Critical "Invalid parameter: 'ExcludedProxy' contains invalid characters. Please provide a comma-separated list of VM names."
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

# Function to Get Proxy Informations
Function Get-VBRProxyInfo {
  [CmdletBinding()]
  param (
      [Parameter(Position=0, ValueFromPipeline=$true)]
      [PSObject[]]$Proxy
  )

  process {
      foreach ($p in $Proxy) {
          $IPv4 = if ($p.Host.Name -match '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b') {
              $p.Host.Name
          } else {
              [Net.DNS]::GetHostEntry($p.Host.Name).AddressList | 
                  Where-Object { $_.AddressFamily -eq "InterNetwork" } | 
                  Select-Object -First 1 | 
                  ForEach-Object { $_.IPAddressToString }
          }

          $pingInfo = (New-Object system.net.networkinformation.ping).send($IPv4)
          $hostAlive = if ($pingInfo.Status -eq "Success") { "Alive" } else { "Dead" }
          $response = if ($hostAlive -eq "Alive") { $pingInfo.RoundtripTime } else { $null }

          [PSCustomObject]@{
              Name     = $p.Name
              Status   = $hostAlive
              IP       = $IPv4
              Response = $response
              Enabled  = if ($p.IsDisabled) { "False" } else { "True" }
          }
      }
  }
}

#endregion

#region Update Script
$repoURL = "https://raw.githubusercontent.com/ATHEO-TDS/MyVeeamMonitoring/main"
$scriptFileURL = "$repoURL/MVM_Proxies.ps1"
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
$excludedProxyArray = $ExcludedProxy -split ','
#endregion

try {
  # Retrieve proxies informations
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
    Exit-Unknown "No proxy found"
}
}Catch{
  Exit-Critical "An error occurred: $_"
}