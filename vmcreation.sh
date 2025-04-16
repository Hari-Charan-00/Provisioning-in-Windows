Install-Module -Name VMware.PowerCLI -Scope CurrentUser
 
$esxiHost = ""
$esxiUser = ""
$esxiPassword = ""
Connect-VIServer -Server $esxiHost -User $esxiUser -Password $esxiPassword
 
$vmName = "TestVM"
$datastore = "datastore1"
$networkAdapter = ""
$vmHost = Get-VMHost -Name $esxiHost
$isoPath = ""
 
New-VM -Name $vmName -VMHost $vmHost -Datastore $datastore -NetworkName $networkAdapter -NumCpu 2 -MemoryGB 4 -DiskGB 40
 
New-CDDrive -VM $vmName -IsoPath $isoPath -StartConnected $true
 
# Configure the VM to boot from the CD/DVD drive
Set-VM -VM $vmName -BootDevice CD
 
# Power on the VM
Start-VM -VM $vmName
 
# Disconnect from the ESXi host
Disconnect-VIServer -Server $esxiHost -Confirm:$false
