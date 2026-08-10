#Requires -Version 5.1
<#
.SYNOPSIS
    Submit an EV-signed CAB to the Microsoft Partner Center Hardware dashboard
    for attestation signing, poll until signed, and download the result.
.DESCRIPTION
    Automates the Hardware Dashboard (Microsoft Hardware) REST API flow:
      1. Create a product (once) / reuse an existing productId.
      2. Create a submission (type = attestation).
      3. Upload the signed CAB to the returned SAS blob URI.
      4. Commit the submission.
      5. Poll submission status until 'completed' (or failed).
      6. Download the signed package (contains MS-signed wnbd.sys + wnbd.cat).

    AUTH: Microsoft Entra ID app (client credentials) whose service principal
    holds a Hardware role (e.g. Driver Submitter) in Partner Center. Prefer
    GitHub OIDC / workload identity federation over a stored client secret.

    This is the fully-automated path. It is normal to run the FIRST few
    submissions manually in the Partner Center portal (see
    docs/partner-center-onboarding.md) until the Entra app + roles are proven,
    then switch CI to this script.
.NOTES
    API base: https://manage.devcenter.microsoft.com/v2.0/my/hardware
    Docs:     https://learn.microsoft.com/windows-hardware/drivers/dashboard/dashboard-api
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CabPath,
    [Parameter(Mandatory)] [string]$ProductName,   # e.g. "wnbd 0.7.0"
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,  # prefer OIDC; secret shown for completeness
    [string]$OutDir = (Join-Path $PSScriptRoot '..' 'release-staging'),
    [int]$PollSeconds = 30,
    [int]$TimeoutMinutes = 60
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $CabPath)) { throw "CAB not found: $CabPath" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$apiBase  = 'https://manage.devcenter.microsoft.com/v2.0/my/hardware'
$resource = 'https://manage.devcenter.microsoft.com'

# --- 1. Entra token (client credentials) ---
Write-Host "Acquiring Entra token ..."
$token = (Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/token" `
    -Body @{ grant_type='client_credentials'; client_id=$ClientId; client_secret=$ClientSecret; resource=$resource }).access_token
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

# --- 2. Create product ---
Write-Host "Creating product '$ProductName' ..."
$product = Invoke-RestMethod -Method Post -Uri "$apiBase/products" -Headers $headers -Body (@{
    productName          = $ProductName
    testHarness          = 'attestation'
    deviceType           = 'internal'
    requestedSignatures  = @('WINDOWS_v100_X64_RS5_FULL')  # tune to target OSes
    firmwareVersion      = '0'
} | ConvertTo-Json)
$productId = $product.id

# --- 3. Create submission ---
Write-Host "Creating submission ..."
$submission = Invoke-RestMethod -Method Post -Uri "$apiBase/products/$productId/submissions" -Headers $headers -Body (@{
    name = $ProductName
    type = 'initial'
} | ConvertTo-Json)
$submissionId = $submission.id
$sasUri       = ($submission.downloads.items | Where-Object type -eq 'initialPackage').url

# --- 4. Upload CAB to the SAS blob ---
Write-Host "Uploading CAB ..."
Invoke-RestMethod -Method Put -Uri $sasUri -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } `
    -InFile $CabPath -ContentType 'application/octet-stream' | Out-Null

# --- 5. Commit ---
Write-Host "Committing submission ..."
Invoke-RestMethod -Method Post -Uri "$apiBase/products/$productId/submissions/$submissionId/commit" -Headers $headers | Out-Null

# --- 6. Poll ---
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
do {
    Start-Sleep -Seconds $PollSeconds
    $s = Invoke-RestMethod -Method Get -Uri "$apiBase/products/$productId/submissions/$submissionId" -Headers $headers
    $state = $s.workflowStatus.currentStep
    Write-Host "  status: $state"
    if ((Get-Date) -gt $deadline) { throw "Timed out waiting for attestation signing." }
} until ($state -eq 'finished' -or $s.workflowStatus.state -eq 'failed')

if ($s.workflowStatus.state -eq 'failed') { throw "Partner Center reported a failed submission." }

# --- 7. Download signed package ---
$signedUrl = ($s.downloads.items | Where-Object type -eq 'signedPackage').url
$signedZip = Join-Path $OutDir 'wnbd-signed.zip'
Write-Host "Downloading signed package ..."
Invoke-WebRequest -Uri $signedUrl -OutFile $signedZip
Expand-Archive -Path $signedZip -DestinationPath (Join-Path $OutDir 'signed') -Force

Write-Host "Signed package extracted to $OutDir\signed"
Write-Output (Join-Path $OutDir 'signed')
