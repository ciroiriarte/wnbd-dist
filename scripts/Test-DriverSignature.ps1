#Requires -Version 5.1
<#
.SYNOPSIS
    Verify that the returned driver package is Microsoft-signed and loadable.
.DESCRIPTION
    Run this on the Microsoft-signed output (release-staging/signed) BEFORE
    publishing a release. It confirms the catalog is signed by the Microsoft
    Windows Hardware Compatibility Publisher and that the .sys matches the .cat.

    Also (optionally, on a throwaway VM with HVCI on) validate HVCI compatibility
    with Driver Verifier:
        verifier.exe /flags 0x02000000 /driver wnbd.sys   # code-integrity checks
.EXAMPLE
    ./scripts/Test-DriverSignature.ps1 -SignedDir release-staging/signed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SignedDir
)
$ErrorActionPreference = 'Stop'
$SignedDir = (Resolve-Path $SignedDir).Path

$signtool = (Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object FullName -match 'x64' | Sort-Object FullName -Descending | Select-Object -First 1).FullName
if (-not $signtool) { $signtool = 'signtool.exe' }

$sys = Get-ChildItem $SignedDir -Recurse -Filter 'wnbd.sys' | Select-Object -First 1
$cat = Get-ChildItem $SignedDir -Recurse -Filter 'wnbd.cat' | Select-Object -First 1
if (-not $sys -or -not $cat) { throw "wnbd.sys and/or wnbd.cat not found under $SignedDir" }

Write-Host "Verifying catalog signature (kernel policy) ..."
& $signtool verify /kp /v $cat.FullName
if ($LASTEXITCODE -ne 0) { throw "Catalog signature verification FAILED." }

Write-Host "Verifying .sys against catalog ..."
& $signtool verify /pa /ph /v /c $cat.FullName $sys.FullName
if ($LASTEXITCODE -ne 0) { throw ".sys/.cat verification FAILED." }

# Confirm the signer is Microsoft's hardware publisher, not our own EV cert.
$sig = Get-AuthenticodeSignature $cat.FullName
$subject = $sig.SignerCertificate.Subject
Write-Host "Catalog signer: $subject"
if ($subject -notmatch 'Windows Hardware Compatibility Publisher') {
    throw "Catalog is NOT signed by Microsoft Windows Hardware Compatibility Publisher. Got: $subject"
}

Write-Host "OK: driver package is Microsoft-attestation-signed and internally consistent."
