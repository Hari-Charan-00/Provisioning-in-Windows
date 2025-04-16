Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false

# Check for required arguments
if ($args.Count -lt 7) {
    Write-Host "Usage: script.ps1 <subdomain> <clientID> <clientSecret> <datastoreName> <vmHost> <vmUser> <vmPassword>"
    exit
}

$subdomain = $args[0]
$clientID = $args[1] | ConvertTo-SecureString -AsPlainText -Force
$clientSecret = $args[2] | ConvertTo-SecureString -AsPlainText -Force
$datastoreName = $args[3]
$vmHost = $args[4]
$vmUser = $args[5]
$vmPassword = $args[6] | ConvertTo-SecureString -AsPlainText -Force

$clientIDPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientID)).Trim()
$clientSecretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecret)).Trim()

# Define the OAuth token URL
$tokenUrl = "https://$subdomain/auth/oauth/token"

# Define the body for the token request
$authData = @{
    'client_id' = $clientIDPlain
    'client_secret' = $clientSecretPlain
    'grant_type' = 'client_credentials'
}

# Define headers for the token request
$tokenHeaders = @{
    'Content-Type' = 'application/x-www-form-urlencoded'
}

# Request the token
Write-Host "Requesting OAuth token..."
try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $authData -Headers $tokenHeaders
    if (-not $tokenResponse.access_token) {
        throw "Token response did not contain an access token."
    }
    $accessToken = $tokenResponse.access_token
    Write-Host "Token generated successfully."
} catch {
    Write-Host "Failed to generate token. Error: $_" -ForegroundColor Red
    exit
}

$packageName = "iso"  
$apiUrl = "https://$subdomain/api/v2/download/gateway/$packageName"

# Download headers for the API call to get the ISO URL
$downloadHeaders = @{
    "Authorization" = "Bearer $accessToken"
    "Accept" = "application/json"
}

# Make the request to retrieve the ISO download URL
Write-Host "Requesting ISO download URL from API..."
try {
    $isoResponse = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $downloadHeaders
    if (-not $isoResponse.URL) {
        throw "ISO response did not contain a valid URL."
    }
    $isoDownloadUrl = $isoResponse.URL
    Write-Host "ISO download URL retrieved: $isoDownloadUrl"
} catch {
    Write-Host "Failed to retrieve ISO download URL. Error: $_" -ForegroundColor Red
    exit
}

# Define the path where the ISO will be temporarily saved locally
$tempIsoLocalPath = "C:\temp\OpsRampGateway2.iso"

# Download the ISO file using the retrieved URL
Write-Host "Downloading ISO from the retrieved URL..."
try {
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($isoDownloadUrl, $tempIsoLocalPath)
    Write-Host "ISO downloaded successfully to $tempIsoLocalPath."
} catch {
    Write-Host "Error downloading ISO: $_" -ForegroundColor Red
    exit
}

# Get user inputs for ESXi connection
$vmPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($vmPassword)).Trim()

Write-Host "Attempting to connect to ESXi host..."
try {
    Connect-VIServer -Server $vmHost -User $vmUser -Password $vmPasswordPlain -ErrorAction Stop -Verbose
    Write-Host "Successfully connected to ESXi host $vmHost."
} catch {
    Write-Host "Failed to connect to ESXi host. Error details: $_" -ForegroundColor Red
    Write-Host "Please check the IP address, username, and password, and try again." -ForegroundColor Red
    exit
}

$isoFolderPath = "ISO"  # Folder in datastore where the ISO will be uploaded

# Get the current date for renaming the ISO
$date = Get-Date
$newFileName = [System.IO.Path]::GetFileNameWithoutExtension($packageName) + "_" + $date.ToString("yyyy-MM-dd") + ".iso"
$datastoreIsoPath = "$isoFolderPath/$newFileName"

# Retrieve the datastore object
$datastore = Get-Datastore -Name $datastoreName
if (-not $datastore) {
    Write-Host "Datastore '$datastoreName' not found. Exiting script."
    Disconnect-VIServer -Confirm:$false
    exit
}

# Remove existing PSDrive if necessary
$existingPSDrive = Get-PSDrive -Name vmstore -ErrorAction SilentlyContinue
if ($existingPSDrive) {
    Remove-PSDrive -Name vmstore -Force
}

# Create a new PSDrive for the datastore
Write-Host "Creating a PSDrive for datastore handling..."
New-PSDrive -Name vmstore -PSProvider VimDatastore -Root "\" -Datastore $datastore

# Define the full path for the ISO folder
$folderPath = "vmstore:\$isoFolderPath"

# Check if the ISO folder exists in the datastore, if not, create it
if (-not (Test-Path -Path $folderPath)) {
    Write-Host "Folder '$isoFolderPath' does not exist. Creating folder..."
    New-Item -Path $folderPath -ItemType Directory
}

# Ensure the datastore path is valid
if (Test-Path $folderPath) {
    Write-Host "Datastore path verified: $folderPath"
} else {
    Write-Host "Datastore path is invalid. Exiting script."
    Disconnect-VIServer -Confirm:$false
    exit
}

# Check if the ISO file already exists in the datastore
$isoExists = Get-ChildItem -Path $folderPath -Name | Where-Object { $_ -eq $newFileName }
if ($isoExists) {
    Write-Host "ISO file '$newFileName' already exists in the datastore." -ForegroundColor Yellow
} else {
    Write-Host "Uploading ISO file to datastore..."
    try {
        # Upload the ISO file to the datastore
        Copy-DatastoreItem -Item $tempIsoLocalPath -Destination "$folderPath\$newFileName" -Force -ErrorAction Stop
        Write-Host "ISO file uploaded successfully as $newFileName to $folderPath."
    } catch {
        Write-Host "Failed to upload ISO file. Error: $_" -ForegroundColor Red
        Disconnect-VIServer -Confirm:$false
        exit
    }
}

# Clean up the temporary ISO file from local machine
if (Test-Path $tempIsoLocalPath) {
    Remove-Item -Path $tempIsoLocalPath -Force
}

# Disconnect from the ESXi host
Write-Host "Disconnecting from ESXi host..."
Disconnect-VIServer -Confirm:$false
