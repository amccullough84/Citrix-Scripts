#Requires -Version 3.0
#This File is in Unicode format.  Do not edit in an ASCII editor.

<#
.SYNOPSIS
    Configured the Citrix VPN Client to connect to the Citrix Gateway VPN
.DESCRIPTION
    Configures the per-user configuration file which contains the Citrix VPN Client configuration. This script will OVERWRITE any exiting user configuration.
    Any existing configuration file will be backed up in the same directory before changes are made.

    Either update the default values for the script parameters, or provide as arguments when running the script. The script
    assumes that users have read access to the local machine certificate store (which they should by default). No elevated 
    permissions should be required.
.PARAMETER VPNGatewayURL Provides the URL for the Gateway for the client to connect to. Should pre pre-fixed with "https://" - this is not validated.
.PARAMETER ConnectionName Provides the Visible name for the VPN Connection - this will be user visible
.PARAMETER CertTemplateOID The OID of the Certificate Template used to issue the Authentication Certificate 
#>

Param(

    [parameter(Mandatory=$False )]
    [string] $VPNGatewayURL="https://citrix.company.co.uk",

    [parameter(Mandatory=$False )]
    [string] $ConnectionName="Company VPN",

    [parameter(Mandatory=$False )]
    [string] $CertTemplateOID="1.3.6.1.4.1.311.21.8.11305749.5660507.9164260.2725761.12092520.75.14548283.14492279",

    [parameter(Mandatory=$False )] 
	[Switch]$Force=$False
)

$ScriptVersion = "0.4"

$strUserName = $env:USERNAME                                      # Gets username of logged on user
$strTemp = $env:TEMP                                              # Gets the path for the user's temp directory
$strLogPath = Join-Path -Path $strTemp -ChildPath "CitrixVPN_UserConfig.log" 
$strConfigFilePath = $env:LOCALAPPDATA + '\Citrix\AGEE\config.js' # Path to config file
$strConfigFolderPath = [System.IO.Path]::GetDirectoryName($strConfigFilePath)

function Write-Log 
{ 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path=$strLogPath, 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber) { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            $NewLogFile = New-Item $Path -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End 
    { 
    } 
}


<#
.SYNOPSIS
 Outputs an object consisting of the template name (Template), an OID (OID), the minor version (MinorVersion), and the major version (MajorVersion).

.DESCRIPTION
 Outputs an object consisting of the template name (Template), an OID (OID), the minor version (MinorVersion), and the major version (MajorVersion).
 This information is derived from the Certificate Extensions.

.PARAMETER Certificate
 A X509Certificate2 object

.EXAMPLE
 Get-ChildItem "Cert:\LocalMachine\My" | Get-CertificateTemplate

.EXAMPLE
 Get-ChildItem "Cert:\LocalMachine\My" | Select-Object Name,Thumbprint,@{Name="Template";Expression={Get-CertificateTemplate $_}}

.INPUTS
 Any X509Certificate2 object

.OUTPUTS
 [PSCustomObject] @{Template=<template name; OID=<oid string>; MajorVersion=<major version num>; MinorVersion=<minor version num> }
#>
function Get-CertificateTemplate {
  [CmdletBinding(SupportsShouldProcess=$false)]
  [OutputType([string])]
  Param([Parameter(Mandatory=$true, ValueFromPipeline=$true)] [ValidateNotNull()] [Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

  Process {
    $regExPrimary=[System.Text.RegularExpressions.Regex]::new("Template=([\w\s\d\.]+)\(((?:\d+.)+)\), Major Version Number=(\d+), Minor Version Number=(\d+)",[System.Text.RegularExpressions.RegexOptions]::None)
    $regExSecondary=[System.Text.RegularExpressions.Regex]::new("Template=((?:\d+.)+), Major Version Number=(\d+), Minor Version Number=(\d+)",[System.Text.RegularExpressions.RegexOptions]::None)

    $temp = $Certificate.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Certificate Template Name" }
    if ($temp -eq $null) {
      Write-Verbose "Did not find 'Certificate Template Name' extension"
      $temp=$Certificate.Extensions | Where-Object { $_.Oid.Value -eq "1.3.6.1.4.1.311.21.7" }
    }
    else { Write-Verbose "Found 'Certificate Template Name' extension" }

    $Matches=$regExPrimary.Matches($temp.Format($false))
    if ($Matches.Count -gt 0) {
      $object=@{Template=$Matches[0].Groups[1].Value; OID=$Matches[0].Groups[2].Value; 
                MajorVersion=$Matches[0].Groups[3].Value; MinorVersion=$Matches[0].Groups[4].Value;
                Thumbprint=$Certificate.Thumbprint }
    }
    else {
      $Matches=$regExSecondary.Matches($temp.Format($false))
      if ($Matches.Count -gt 0) {
        Write-Verbose "Found certificate without a valid Template Name"
        $object=@{Template=$Matches[0].Groups[1].Value; OID=$Matches[0].Groups[1].Value; 
                  MajorVersion=$Matches[0].Groups[2].Value; MinorVersion=$Matches[0].Groups[3].Value;
                  Thumbprint=$Certificate.Thumbprint }

      }
      else {
        Write-Verbose "Found root certificate"
        $object=@{Template="Root Certificate"; OID=""; MajorVersion=""; MinorVersion=""; Thumbprint=$Certificate.Thumbprint }
      }
    }
    return [PSCustomObject]$object
  }
}

Write-Log -Message "Starting Script Execution"
Write-Log -Message "Setting Location to local machine certificate store"

Set-Location cert:\LocalMachine\My
Write-Log -message "Done"

$certs = get-childitem
Write-Log -Message "Available certificates: $certs"

#Create Object Array for matching certificates
[System.Collections.ArrayList]$MatchingCerts = @()

If ($certs.Count -gt 0) {
  Write-Log -Message "Found some certificates: $($certs.Count)"
  foreach ($cert in $certs) {
  Write-Log -Message "Checking Certificate: $($cert)"
  #Get Template Info
  Write-Log -Message "Querying template info"
  $TemplateInfo = Get-CertificateTemplate -Certificate $cert
  Write-Log -Message "Done"
  Write-Log -Message "Checking if $($templateInfo.OID) matches $CertTemplateOID"
  If ($TemplateInfo.OID -eq $CertTemplateOID) {
    Write-Log -Message "Found a match"
    #Get Issuer Identity
    $Issuer = $Cert.IssuerName.RawData
    $RawIssuer = [System.BitConverter]::ToString($Issuer)
    [String]$IssuerHex = $RawIssuer -replace "-",""
    Write-log -Message "Got Issuer information, bitconverted to string: $IssuerHex"
    #Get Cert Serial Number
    $SerialNumber = $cert.SerialNumber
    Write-Log -Message "Got Serial Number: $SerialNumber"
    [String]$tempSerial = $SerialNumber
    [String]$reOrderedSerial = ""
    [Int]$charCounter = 0

    #Loop through the temp Serial Number variable selecting two characters at a time
    Do {
    #Write-Host "NEW LOOP" -ForegroundColor Green
    #Write-Host "Current char counter is: " $charcounter
    $Length = $tempSerial.Length - 1
    #Write-Host "Length of TempSerial is: " $Length

    If ($Length -gt 1) {
     # Write-Host "Will select 2 characters"
      $charsToSelect = 2
    } Else {
      #Write-Host "Will select 1 character"
      $charsToSelect = 1
    }
    #Write-Host "Current Temp String is: " $tempSerial
    $chars = $tempSerial.Substring(0,$charsToSelect)
    #Write-Host "Selected characters are: " $chars
    $reOrderedSerial = "$($Chars)$($reOrderedSerial)"
    #Write-Host "Current Re-ordered string is: " $reOrderedSerial
    $tempSerial = $tempSerial.Substring($charsToSelect)
    #Write-Host "Trimmed Temp Serial is: " $tempSerial
    } until ($tempSerial.Length -eq 0)


    Write-Log -Message "reformatted Serial into Citrix wonky version: $reOrderedSerial"
    Write-Log -Message "Creating an object to add to results array"

    #Create Custom Object containing Certificate Data
    $CertObject = [PSCustomObject]@{

    Name = $cert.GetName()
    IssuerHex  = $IssuerHex
    CitrixWonkySerialNumber = $reOrderedSerial
    Issuer = $cert.Issuer
    ExpiryDate = $cert.NotAfter
    IssueDate = $cert.NotBefore

    }
    
    $MatchingCerts.Add($CertObject) | Out-Null
  }

  Write-Log -Message "Checking if we have any matching certificates..."
  If ($MatchingCerts.Count -gt 0) {
    Write-Log -Message "We do!"
    
    Write-Log -Message "Selecting the one with the latest expiry date..."
    $SelectedCertificate = $MatchingCerts | Sort-Object -Property ExpiryDate -Descending | Select-Object -First 1
    Write-Log -Message "$SelectedCertificate"
  } Else {
    Write-Log -Message "No matching certificates found"
    
  }
  #If we have a selected certificate then...
  If ($SelectedCertificate) {

  $CertificateHint = "$($SelectedCertificate.IssuerHex.ToLower()),$($SelectedCertificate.CitrixWonkySerialNumber.ToLower())"
  Write-Log -Message "Generated Certificate Hint based on the identified certificate: $CertificateHint"

  }

}
}

$strCertificateHint = $CertificateHint

If ($strCertificateHint) {

Write-Log -Message "Checking to see if $strConfigFilePath-Updated-v$ScriptVersion.flg exists"
If (!(test-path("$strConfigFilePath-Updated-v$ScriptVersion.flg")) -or ($Force -eq $true)) {
  Write-Log -Message "Does not exist"
  #Check if folder exists and if not then create it
  If (!(test-path($strConfigFolderPath))) {
    Write-Log -Message "Creating folder $strConfigFolderPath"
    New-Item -Path $strConfigFolderPath -ItemType directory | out-null
  }
  
  
  # Build connection string
  $strConnectionString = "{`"auto open homepage`":null,`"connectingTo`":`"$VPNGatewayURL`",`"connections`":[{`"devCert`":`"$strCertificateHint`",`"name`":`"$ConnectionName`",`"url`":`"$VPNGatewayURL`"}],`"debug logging`":true,`"epaTopMost`":true,`"language`":null,`"lastUserName`":`"$strUserName`",`"local lan access`":`"true`"}"
  Write-Log -Message "Built connection string: $strConnectionString"
  # Backup current config if it exists
  If (test-path($strConfigFilePath)) {
    Write-log -Message "Backing up current configuration file to: $strConfigFilePath-$ScriptVersion.backup"
    Copy-Item $strConfigFilePath "$strConfigFilePath-$ScriptVersion.backup" -Force
  }

  # Install new config
  Write-Log -Message "Creating new configuration file"
  Out-File -FilePath $strConfigFilePath -InputObject $strConnectionString -Encoding ascii

  Write-Log -Message "Creating flag file to show execution for this script version: $strConfigFilePath-Updated-v$ScriptVersion.flg"
  #Create Flag file to prevent future executions of this script version
  Out-File -FilePath "$strConfigFilePath-Updated-v$ScriptVersion.flg"

 

  # Stop VPN Process; NOTE: This will process will restart itself with the new config
  Write-log -Message "Restarting nsload to reload configuration"
  If (get-process -Name nsload -ErrorAction SilentlyContinue){
    Stop-Process -Name nsload
  }
  Write-Log "Finished Restarting"
}
}


Write-Log -Message "End of Script Execution"

