# ====================================================================
# Author: Tiago DA SILVA - ATHEO INGENIERIE
# Version: 1.0.1
# Creation Date: 2024-11-29
# Last Update: 2024-12-02
# GitHub Repository: https://github.com/TiagoDSLV/MyVeeamMonitoring
# ====================================================================
#
# DESCRIPTION:
# This PowerShell script monitors the status of Veeam Backup & Replication proxies,
# checking if they are alive or dead by performing a network ping test.
# It also supports excluding certain proxies from the monitoring by specifying
# the proxy names in the input parameter.
#
# PARAMETERS:
# - ExcludedProxy: A comma-separated list of proxy names to exclude from monitoring.
#                   You can use the '*' wildcard for partial matches.
#
# RETURNS:
# - OK: All listed proxies are alive.
# - Critical: At least one proxy is dead.
# - Unknown: No proxies found or an error occurred during execution.
#
# ====================================================================

#region Parameters
param (
    [string]$ExcludedProxy = ""  # List of proxies to exclude from monitoring
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

# Function to get Proxy Information
Function Get-VBRProxyInfo {
  [CmdletBinding()]
  param (
      [Parameter(Position=0, ValueFromPipeline=$true)]
      [PSObject[]]$Proxy
  )

  process {
      foreach ($p in $Proxy) {
        # Check if the proxy's IP is in IPv4 format or resolve the DNS name to an IP
          $IPv4 = if ($p.Host.Name -match '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b') {
              $p.Host.Name
          } else {
              [Net.DNS]::GetHostEntry($p.Host.Name).AddressList | 
                  Where-Object { $_.AddressFamily -eq "InterNetwork" } | 
                  Select-Object -First 1 | 
                  ForEach-Object { $_.IPAddressToString }
          }

          # Perform a ping test to check if the proxy is alive
          $pingInfo = (New-Object system.net.networkinformation.ping).send($IPv4)
          $hostAlive = if ($pingInfo.Status -eq "Success") { "Alive" } else { "Dead" }
          $response = if ($hostAlive -eq "Alive") { $pingInfo.RoundtripTime } else { $null }

          # Output the proxy information as a custom object
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

#region Validate Parameters
# Validate that the parameters are non-empty if they are provided
if ($ExcludedProxy -and $ExcludedProxy -notmatch "^[\w\.\,\s\*\-_]*$") {
  Exit-Critical "Invalid parameter: 'ExcludedProxy' contains invalid characters. Please provide a comma-separated list of proxy names."
}
#endregion

#region Connection to VBR Server
Connect-VBRServerIfNeeded
#endregion

#region Variables
$excludedProxyArray = $ExcludedProxy -split ','  # Split the excluded proxies into an array
#endregion

try {
  # Retrieve proxy information and perform the check
  $proxyList = @(Get-VBRViProxy | Get-VBRProxyInfo)

  If ($proxyList.count -gt 0) {
    # Filter proxies to exclude those specified in the ExcludedProxy parameter
    $excludeProxy_regex = ('(?i)^(' + (($excludedProxyArray | ForEach-Object {[regex]::escape($_)}) -join "|") + ')$') -replace "\\\*", ".*"
    $filteredProxyList = $proxyList | Where-Object {$_.Name -notmatch $excludeProxy_regex}

    # Separate the proxies based on their status (alive or dead)
    $aliveProxy = $filteredProxyList | Where-Object {$_.Status -eq "Alive"}
    $deadProxy = $filteredProxyList | Where-Object {$_.Status -eq "Dead"}

    # Prepare the output strings for alive and dead proxies
    $outputOk = ($aliveProxy.Name) -join ","
    $outputCrit = ($deadProxy.Name) -join ","    

    # If any proxies are dead, exit with a critical status, otherwise OK
    if ($deadProxy.count -gt 0) {
        Exit-Critical "$($deadProxy.count) proxies are dead: $outputCrit"
    }else {
        Exit-Ok "All the listed proxies are alive: $outputOk"
    }
    
  }Else{
    Exit-Unknown "No proxy found"  # Exit with unknown if no proxies are found
}
}Catch{
  Exit-Critical "An error occurred: $($_.Exception.Message)"  # Exit with critical error in case of exception
}
