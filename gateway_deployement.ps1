# Define variables
$vmHost = Read-Host "Enter the ESXi host IP"
$vmUser = Read-Host "Enter the user name"
$vmPassword = Read-Host "Enter the ESXi password" -AsSecureString

$vmPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($vmPassword)).Trim()

Write-Host "Attempting to connect to ESXi host..."
try {
    Connect-VIServer -Server $vmHost -User $vmUser -Password $vmPasswordPlain -ErrorAction Stop
    Write-Host "Successfully connected to ESXi host $vmHost."
} catch {
    Write-Host "Failed to connect to ESXi host. Error details: $_" -ForegroundColor Yellow
    Write-Host "Please check the IP address, username, and password, and try again." -ForegroundColor Yellow
    exit
}

Get-VMHost -Name "$vmHost" | Get-Datastore

$datastoreName = Read-Host "Enter the DS name"
$vmName = Read-Host "Enter the VM name"
$vmMemoryGB = Read-Host "Enter the memory (e.g: 4)"
$vmCpu = Read-Host "Enter the num of cpu (e.g: 2)"
$vmDiskGB = Read-Host "Enter the disk capacity (e.g: 40)"
$vmNetwork = Read-Host "Enter the VM network"
$adapterTypeInput = Read-Host "Enter the network adapter type (e.g., Vmxnet3 or E1000)" -Default "Vmxnet3"
Write-Host "Selected network adapter type: $adapterType"
$date = Get-Date
$isoFileName = "OpsRampGateway.iso"
$isoFileName1 = [System.IO.Path]::GetFileNameWithoutExtension($isoFileName) + "_" + $date.ToString("yyyy-MM-dd") + ".iso"
$isoFolderPath = "ISO"

	
# Check if the vmstore PSDrive exists and remove it
if (Get-PSDrive -Name vmstore -ErrorAction SilentlyContinue) {
    Remove-PSDrive -Name vmstore
}

# Create a new PSDrive for the datastore
Write-Host "Creating PSDrive for datastore..."
New-PSDrive -Name vmstore -PSProvider VimDatastore -Root "\" -Datastore (Get-Datastore -Name $datastoreName)

# Check if ISO folder exists in datastore
$datastoreIsoFolderPath = "vmstore:\$isoFolderPath"
Write-Host "Checking for ISO folder in datastore path: $datastoreIsoFolderPath"
if (Test-Path $datastoreIsoFolderPath) {
    Write-Host "ISO folder exists in the datastore."
} else {
    Write-Host "ISO folder not found in the datastore. Exiting script."
    Disconnect-VIServer -Confirm:$false
    exit
}

# List files in the folder for debugging
#Write-Host "Listing files in the folder for debugging..."
#Get-ChildItem -Path $datastoreIsoFolderPath

# Correct ISO file path
$datastoreIsoPath = "vmstore:\$isoFolderPath\$isoFileName1"

# Check if ISO file exists in the datastore
Write-Host "Checking for ISO file in datastore path: $datastoreIsoPath"
if (-not (Test-Path $datastoreIsoPath)) {
    Write-Host "ISO file not found in datastore. Exiting script."
    Disconnect-VIServer -Confirm:$false
    exit
} else {
    Write-Host "ISO file found in datastore: $datastoreIsoPath"
}

# Define variables for VM creation
$datastoreIsoPath = "[$datastoreName] $isoFolderPath/$isoFileName1"

# Create the VM with CD/DVD drive and attach ISO
Write-Host "Creating VM..."
$vm = New-VM -Name $vmName -ResourcePool (Get-ResourcePool) -Datastore (Get-Datastore -Name $datastoreName) -MemoryGB $vmMemoryGB -NumCpu $vmCpu -DiskGB $vmDiskGB -GuestId "ubuntu64Guest" -NetworkName $vmNetwork

Write-Host "VM '$vmName' created successfully."

# Validate adapter type input and set the adapter type directly as string
$validAdapterTypes = @("E1000", "E1000E", "Vmxnet2", "Vmxnet3")
if ($validAdapterTypes -contains $adapterTypeInput) {
    $adapterType = $adapterTypeInput
} else {
    Write-Host "Invalid adapter type specified. Defaulting to Vmxnet3."
    $adapterType = "Vmxnet3"
}

# Add the network adapter of user-defined type
Write-Host "Adding network adapter to VM..."
$networkAdapter = Get-VM -Name $vmName | New-NetworkAdapter -NetworkName $vmNetwork -Type $adapterType

# Check the network adapter added
if ($networkAdapter) {
    Write-Host "Network adapter added to VM '$vmName' of type '$adapterType'."
} else {
    Write-Host "Failed to add network adapter to VM '$vmName'."
}

# Add CD/DVD drive to the VM and attach ISO
Write-Host "Attaching ISO to VM..."
$cdDrive = New-CDDrive -VM $vm -IsoPath $datastoreIsoPath -StartConnected:$true

Write-Host "ISO attached to VM '$vmName'."

# Start the VM
Write-Host "Starting VM..."
Start-VM -VM $vm

Write-Host "VM '$vmName' started."

# Disconnect from ESXi host
Write-Host "Disconnecting from ESXi host..."
Disconnect-VIServer -Confirm:$false
