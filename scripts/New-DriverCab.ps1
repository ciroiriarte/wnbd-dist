#Requires -Version 5.1
<#
.SYNOPSIS
    Package the built driver into an attestation CAB and EV-sign it.
.DESCRIPTION
    Microsoft attestation signing requires a CAB whose files sit in a single
    SUBFOLDER (not at the CAB root):

        cabroot/
          wnbd/
            wnbd.inf
            wnbd.sys
            wnbd.pdb
            wnbd.cat

    Steps:
      1. Validate the INF (InfVerif) and (re)generate the catalog (Inf2Cat).
      2. Stage the four files under a single subfolder.
      3. Emit a .ddf and build the CAB with MakeCab.
      4. EV-sign the CAB with signtool (RFC-3161 timestamp).

    NOTE ON SIGNING: the EV private key must live on an HSM / hardware token /
    cloud signing service — never an exportable PFX in a CI secret. Pass the
    signing invocation via -SignCommand so this script stays key-custody
    agnostic (SignTool + KSP, AzureSignTool, DigiCert KeyLocker, etc.).
.EXAMPLE
    ./scripts/New-DriverCab.ps1 -DriverDir vendor/wnbd/vstudio/x64/Release/driver `
        -SignCommand 'AzureSignTool sign -kvu $env:AKV_URL -kvc wnbd-ev -kvi $env:AZ_ID -kvs $env:AZ_SECRET -tr http://timestamp.digicert.com -td sha256 -fd sha256 {CAB}'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$DriverDir,
    [string]$OutDir   = (Join-Path $PSScriptRoot '..' 'release-staging'),
    [string]$CabName  = 'wnbd.cab',
    # OS targets requested at Partner Center — keep in sync with your submission.
    [string]$Inf2CatOs = '10_X64,10_RS5_X64,ServerRS5_X64',
    # Command that EV-signs the CAB. '{CAB}' is replaced with the CAB path.
    # If omitted, the CAB is left UNSIGNED (build/test only).
    [string]$SignCommand
)
$ErrorActionPreference = 'Stop'

$DriverDir = (Resolve-Path $DriverDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

function Find-Tool([string]$name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    # Fall back to the newest copy under the Windows Kits root.
    $hit = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter $name -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    throw "Required tool '$name' not found (install the WDK, or run inside the EWDK shell)."
}

$infverif = Find-Tool 'InfVerif.exe'
$inf2cat  = Find-Tool 'Inf2Cat.exe'
$makecab  = 'makecab.exe'  # in-box

# 1. Validate INF + regenerate catalog in place.
Write-Host "InfVerif ..."
& $infverif /v (Join-Path $DriverDir 'wnbd.inf')
if ($LASTEXITCODE -ne 0) { throw "InfVerif failed." }

Write-Host "Inf2Cat (os=$Inf2CatOs) ..."
& $inf2cat "/driver:$DriverDir" "/os:$Inf2CatOs"
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat failed." }

# 2. Stage files under a single subfolder 'wnbd'.
$stage = Join-Path $OutDir 'cabroot'
$sub   = Join-Path $stage 'wnbd'
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $sub | Out-Null
foreach ($f in 'wnbd.inf', 'wnbd.sys', 'wnbd.cat', 'wnbd.pdb') {
    $src = Join-Path $DriverDir $f
    if (Test-Path $src) { Copy-Item $src $sub }
    elseif ($f -ne 'wnbd.pdb') { throw "Missing required file for CAB: $f" }
}

# 3. Build the CAB via a generated .ddf.
$cabPath = Join-Path $OutDir $CabName
$ddf = Join-Path $OutDir 'wnbd.ddf'
@"
.OPTION EXPLICIT
.Set CabinetNameTemplate=$CabName
.Set DiskDirectoryTemplate=$OutDir
.Set CompressionType=MSZIP
.Set Cabinet=on
.Set Compress=on
.Set DestinationDir=wnbd
$(Get-ChildItem $sub | ForEach-Object { "`"$($_.FullName)`"" } | Out-String)
"@ | Set-Content -Path $ddf -Encoding ASCII

Write-Host "MakeCab ..."
& $makecab /f $ddf
if ($LASTEXITCODE -ne 0) { throw "MakeCab failed." }
if (-not (Test-Path $cabPath)) { throw "CAB not produced at $cabPath." }

# 4. EV-sign the CAB (or warn).
if ($SignCommand) {
    $invocation = $SignCommand.Replace('{CAB}', "`"$cabPath`"")
    Write-Host "EV-signing CAB ..."
    & cmd.exe /c $invocation
    if ($LASTEXITCODE -ne 0) { throw "CAB signing failed." }
} else {
    Write-Warning "No -SignCommand given: CAB is UNSIGNED. Partner Center will reject it."
}

Write-Host "CAB ready: $cabPath"
Write-Output $cabPath
