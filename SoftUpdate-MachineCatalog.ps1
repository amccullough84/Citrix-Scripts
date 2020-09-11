#Script to perform a "Soft Update" of an MCS machine catalog
#Version: 1.0
#Author: Andy McCullough (@andymc84)
#Acknowledgements: Portions of the script are derived from Aaron Parker (@StealthPuppy) blog 
#post https://stealthpuppy.com/xendesktop-update-mcs-machine-catalog-powershell/
#Requirements - Citrix Script requires Citrix PowerShell SDK (either Cloud on On-Prem depending on your environment



###### VARIABLES #######
#Update the customer ID to your customer ID to use secureclient authentication 
$CustomerID = "xxxxxxxxxx"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
#This is the path to the secureclient.csv file to use if you want to authenticate to Citrix Cloud using a secure 
#client. If this is not present then you will be prompted for authentication
$SecureClient = Join-Path -Path $scriptDir -ChildPath "secureclient.csv"
$CredProfileName = "CatalogUpdate"
#Set Cloud to $True if you are using Citrix Cloud services, otherwise set to $false to use on-prem powershell SDK
$Cloud = $true

#### INITIALISE ####

Add-PSSnapin Citrix*

#### AUTHENTICATION ####
If ($Cloud) {
  If (Test-Path -Path $SecureClient) {
    Set-XDCredentials -CustomerId $CustomerID  -SecureClientFile $SecureClient -ProfileType CloudApi -StoreAs $CredProfileName
    #Authenticate to Citrix Cloud using the Secure Client Key
    Get-XDAuthentication -ProfileName $CredProfileName
  } Else {
    Get-XDAuthentication
  }
}



### GET OBJECTS ###
#region catalogs
$Catalogs = Get-BrokerCatalog | Where-Object {$_.ProvisioningType -eq "MCS"}

If (!($Catalogs.Count -gt 0)) {
  Write-Error "No Machine Catalogs were found to update"
}

#Select the catalog to update
$SelectedCatalog = ""
  
  Write-Host "Select which Machine Catalog you want to update:" -ForegroundColor Green
  Write-Host ""
          for($i = 0; $i -lt $Catalogs.count; $i++){
            Write-Host "[$($i)]: $($Catalogs[$i].Name)" -ForegroundColor Green
        }
  Write-Host ""
  $SelectedCatalogNumber = Read-Host "Enter Catalog Number"
  $SelectedCatalog = $Catalogs[$SelectedCatalogNumber]
  $CatalogConfirm = Read-Host "You selected catalog: $($SelectedCatalog.Name) - Is this correct? [Y/N]"
  If ($CatalogConfirm.ToLower() -ne "y") {
    Write-Error "Cancelled Update Deployment"
    Exit
  }
#endregion catalogs

#region provscheme
$ProvisioningScheme = Get-ProvScheme -ProvisioningSchemeUid $SelectedCatalog.ProvisioningSchemeId
[String]$MasterImage = $ProvisioningScheme.MasterImageVM
$HostingConnectionQualified = $MasterImage.Split("\")[0..2] -Join "\"
$MasterImageVMQualified = $MasterImage.Split("\")[0..3] -Join "\"
$HostingConnectionName = Split-Path $HostingConnectionQualified -Leaf
$CurrentMasterImage = (Split-Path $MasterImageVMQualified -Leaf).Split(".")[0]
$CurrentSnapshot = [IO.Path]::GetFileNameWithoutExtension((Split-Path $MasterImage -Leaf))
Write-Host ""
Write-Host "Current Catalog Configuration is:-" -ForegroundColor Green
Write-Host ""
Write-Host "Hosting Connection: $HostingConnectionName"
Write-Host "Master Image VM: $CurrentMasterImage"
Write-Host "Deployed Snapshot: $CurrentSnapshot" 
Write-Host ""
#endregion provscheme


#region master image selection


#endregion master image selection
  $UseSameMasterConfirm = Read-Host "Do you want to select a snapshot from the same master image? [Y/N]"
  If ($UseSameMasterConfirm.ToLower() -ne "y") {
    #Select another VM
    $VMObjects = Get-ChildItem $HostingConnectionQualified | Where-Object {$_.IsMachine -eq $true}
    $SelectedVM = ""
    Write-Host ""
    Write-Host "Select which Master Image VM you want to use:" -ForegroundColor Green
    Write-Host ""
            for($i = 0; $i -lt $VMObjects.count; $i++){
              Write-Host "[$($i)]: $($VMObjects[$i].Name)" -ForegroundColor Green
          }
    Write-Host ""
    $SelectedVMNumber = Read-Host "Enter VM Number"
    $SelectedVM = $VMObjects[$SelectedVMNumber]
    $VMConfirm = Read-Host "You selected VM: $($SelectedVM.Name) - Is this correct? [Y/N]"
    If ($VMConfirm.ToLower() -ne "y") {
      Write-Error "Cancelled Update Deployment"
      Exit
    }
    $MasterImageVMPath = $SelectedVM.FullPath
    $MasterImageName = $SelectedVM.Name
  } Else {
    $MasterImageName = $CurrentMasterImage
    $MasterImageVMPath = $MasterImageVMQualified
  }


#region select snapshot
$SnapShots = Get-ChildItem $MasterImageVMPath -Recurse
$SelectedSnapshot = ""
if ($SnapShots) {
  Write-Host ""
  Write-Host "Select which Snapshot of $MasterImageName you want to deploy:" -ForegroundColor Green
  Write-Host ""
          for($i = 0; $i -lt $SnapShots.count; $i++){
            Write-Host "[$($i)]: $([IO.Path]::GetFileNameWithoutExtension($Snapshots[$i].FullName))" -ForegroundColor Green
        }
  Write-Host ""
  $SelectedNumber = Read-Host "Enter Snapshot Number"
  $SelectedSnapshot = $Snapshots[$SelectedNumber]
  $SnapConfirm = Read-Host "You selected snapshot: $([IO.Path]::GetFileNameWithoutExtension($SelectedSnapshot.FullName)) - Is this correct [Y/N]"
  If ($SnapConfirm.ToLower() -ne "y") {
    Write-Error "Cancelled Update Deployment" -ForegroundColor Red
    Exit
  }
} Else {
  Write-Error "No snapshots were found for the selected VM. Please create a snapshot then re-run the script."
  Exit
}
#endregion select snapshot

#region deployment
    Write-Host ""
    $DeployConfirm = Read-Host "You are about to deploy snapshot - $([IO.Path]::GetFileNameWithoutExtension($SelectedSnapshot.FullName)) - to the catalog - $($SelectedCatalog.Name). Do you wish to proceed? [Y/N]"
    
    If ($DeployConfirm.ToLower() -eq "y") {
      $PubTask = Publish-ProvMasterVmImage -MasterImageVM $SelectedSnapshot.FullPath -ProvisioningSchemeName $ProvisioningScheme.ProvisioningSchemeName -RunAsynchronously 
      $provTask = Get-ProvTask -TaskId $PubTask

      $totalPercent = 0
      While ( $provTask.Active -eq $True ) {
        Try { $totalPercent = If ( $provTask.TaskProgress ) { $provTask.TaskProgress } Else {0} } Catch { }

        Write-Progress -Activity "Provisioning image update" -Status "$totalPercent% Complete:" -percentcomplete $totalPercent
        Sleep 15
        $provTask = Get-ProvTask -TaskId $PubTask
      }

      Write-Host $provTask.Status
    } Else {
    Write-Error "Update deployment cancelled"
    Exit
    }

#endregion deployment
