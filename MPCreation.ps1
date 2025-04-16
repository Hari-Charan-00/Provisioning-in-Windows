# Ignore SSL warnings
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Base URL
$BASE_URL = "https://netenrich.opsramp.com/"

# Function to handle errors and stop execution
function Stop-OnError {
    param (
        [string]$ErrorMessage
    )
    Write-Host "Error: $ErrorMessage" -ForegroundColor Red
    throw $ErrorMessage
}

# User Input for client_key and client_secret
$client_key = Read-Host "Enter the client key" -AsSecureString
$client_secret = Read-Host "Enter the client secret" -AsSecureString

# Ensure input is valid, otherwise stop script
if (-not $client_key) {
    Stop-OnError "Client key cannot be empty."
}
if (-not $client_secret) {
    Stop-OnError "Client secret cannot be empty."
}

# Convert SecureString to plain text
try {
    $clientIDPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($client_key)).Trim()
    $clientSecretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($client_secret)).Trim()
} catch {
    Stop-OnError "Error converting secure string to plain text: $_"
}

# Function to get OAuth Token
function Get-Token {
    param (
        [string]$clientIDPlain,
        [string]$clientSecretPlain
    )
    
    $token_url = "$BASE_URL/auth/oauth/token"
    $auth_data = @{
        'grant_type'    = 'client_credentials'
        'client_secret' = $clientSecretPlain
        'client_id'     = $clientIDPlain
    }
    
    try {
        $response = Invoke-RestMethod -Uri $token_url -Method POST -Body $auth_data -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -ErrorAction Stop
        return $response.access_token
    } catch {
        Stop-OnError "Error getting access token: $_"
    }
}

# Function to create a profile
function Create-Profile {
    param (
        [string]$access_token,
        [string]$profile_name,
        [string]$tenant_id
    )
    
    $headers = @{
        'Authorization' = "Bearer $access_token"
        'Content-Type'  = 'application/json'
    }

    $api_url = "$BASE_URL/api/v2/tenants/$tenant_id/managementProfiles"
    $payload = @{
        name = $profile_name
        type = 'Gateway'
    }

    try {
        $response = Invoke-RestMethod -Uri $api_url -Method POST -Headers $headers -Body ($payload | ConvertTo-Json) -UseBasicParsing -ErrorAction Stop
        Write-Host "Management Profile created successfully" -ForegroundColor Green
    } catch {
        Stop-OnError "Unable to create the management profile: $_"
    }
}

# Function to search for a profile
function Search-Profile {
    param (
        [string]$access_token,
        [string]$profile_name,
        [string]$tenant_id
    )
    
    $headers = @{
        'Authorization' = "Bearer $access_token"
        'Content-Type'  = 'application/json'
    }
    
    $api_url = "$BASE_URL/api/v2/tenants/$tenant_id/managementProfiles/search"
    
    try {
        $response = Invoke-RestMethod -Uri $api_url -Method GET -Headers $headers -UseBasicParsing -ErrorAction Stop
        $profiles = $response.results
        
        foreach ($profile in $profiles) {
            if ($profile.name -eq $profile_name) {
                $profileID = $profile.id
                #Write-Host "Profile ID for '$profile_name' is: $profileID" -ForegroundColor Green
                return $profileID
            }
        }
        Write-Host "Mentioned profile name was not found." -ForegroundColor Yellow
        return $null
    } catch {
        Stop-OnError "Unable to search management profiles: $_"
    }
}

# Function to detach profile
function Detach-Profile {
    param (
        [string]$access_token,
        [string]$profileID,
        [string]$tenant_id
    )
    
    if (-not $profileID) {
        Stop-OnError "Invalid profile ID. Cannot detach profile."
    }

    $headers = @{
        'Authorization' = "Bearer $access_token"
        'Content-Type'  = 'application/json'
    }

    $api_url = "$BASE_URL/api/v2/tenants/$tenant_id/managementProfiles/$profileID/detach"
    
    try {
        $response = Invoke-RestMethod -Uri $api_url -Method GET -Headers $headers -UseBasicParsing -ErrorAction Stop
        #Write-Host "Profile detached successfully!" -ForegroundColor Green
    } catch {
        Stop-OnError "Unable to detach the profile: $_"
    }
}

# Function to attach profile
function Attach-Profile {
    param (
        [string]$access_token,
        [string]$profileID,
        [string]$tenant_id
    )
    
    if (-not $profileID) {
        Stop-OnError "Invalid profile ID. Cannot attach profile."
    }

    $headers = @{
        'Authorization' = "Bearer $access_token"
        'Content-Type'  = 'application/json'
    }

    $api_url = "$BASE_URL/api/v2/tenants/$tenant_id/managementProfiles/$profileID/attach"
    
    try {
        $response = Invoke-RestMethod -Uri $api_url -Method GET -Headers $headers -UseBasicParsing -ErrorAction Stop
        #Write-Host "Profile attached successfully!" -ForegroundColor Green
        $activation_token = $response.activationToken
        Write-Host "Activation token: $activation_token" -ForegroundColor Cyan
    } catch {
        Stop-OnError "Unable to attach the profile: $_"
    }
}

# Main script logic
$tenant_id = Read-Host "Enter the tenant ID"

# Get access token
$access_token = Get-Token -clientIDPlain $clientIDPlain -clientSecretPlain $clientSecretPlain

# If token is valid, proceed with profile creation and management
if ($access_token) {
    $profile_name = Read-Host "Enter the profile name to create"
    Create-Profile -access_token $access_token -profile_name $profile_name -tenant_id $tenant_id
    $profileID = Search-Profile -access_token $access_token -profile_name $profile_name -tenant_id $tenant_id
    if ($profileID) {
        Detach-Profile -access_token $access_token -profileID $profileID -tenant_id $tenant_id
        Attach-Profile -access_token $access_token -profileID $profileID -tenant_id $tenant_id
    }
}
