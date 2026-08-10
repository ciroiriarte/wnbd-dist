#Requires -Version 5.1
<#
.SYNOPSIS
    Build the WNBD driver (Release|x64) from the pinned submodule using the EWDK.
.DESCRIPTION
    Uses the Enterprise WDK (EWDK) — an install-free, command-line build
    environment — so builds are reproducible on any Windows host or CI runner
    without a full Visual Studio + WDK install.

    Two ways to provide the EWDK:
      * -EwdkRoot <path>  : an already-extracted/mounted EWDK (contains
                            BuildEnv\SetupBuildEnv.cmd and LaunchBuildEnv.cmd).
      * -EwdkIso <path>   : an EWDK ISO; it is mounted, used, then dismounted.

    Upstream build facts (cloudbase/wnbd @ 0.7.0):
      * Solution : vendor/wnbd/vstudio/wnbd.sln
      * Driver   : vstudio/driver.vcxproj (WindowsKernelModeDriver10.0, x64, WDM)
      * Output   : vendor/wnbd/vstudio/x64/Release/driver/{wnbd.sys,wnbd.inf,wnbd.cat,wnbd.pdb}
      * Deps     : get_dependencies.ps1 runs automatically during the build.
.EXAMPLE
    ./scripts/Invoke-EwdkBuild.ps1 -EwdkRoot 'D:\EWDK'
.EXAMPLE
    ./scripts/Invoke-EwdkBuild.ps1 -EwdkIso 'C:\iso\EWDK_ni_release_svc_prod1_24H2.iso'
#>
[CmdletBinding(DefaultParameterSetName = 'Root')]
param(
    [Parameter(ParameterSetName = 'Root', Mandatory)] [string]$EwdkRoot,
    [Parameter(ParameterSetName = 'Iso',  Mandatory)] [string]$EwdkIso,
    [ValidateSet('Release', 'Debug')] [string]$Configuration = 'Release',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference = 'Stop'

$sln = Join-Path $RepoRoot 'vendor/wnbd/vstudio/wnbd.sln'
if (-not (Test-Path $sln)) {
    throw "Solution not found at $sln. Did you run 'git submodule update --init --recursive'?"
}

$mountedIso = $null
try {
    if ($PSCmdlet.ParameterSetName -eq 'Iso') {
        Write-Host "Mounting EWDK ISO: $EwdkIso"
        $mountedIso = Mount-DiskImage -ImagePath $EwdkIso -PassThru
        $vol = ($mountedIso | Get-Volume).DriveLetter
        $EwdkRoot = "${vol}:\"
    }

    $launch = Join-Path $EwdkRoot 'LaunchBuildEnv.cmd'
    if (-not (Test-Path $launch)) { throw "LaunchBuildEnv.cmd not found under EWDK root '$EwdkRoot'." }

    # LaunchBuildEnv sets the compiler/WDK env, then we hand off to MSBuild.
    # /m parallel build; PnpLockdown INF stays as-is from upstream.
    $msbuildArgs = "`"$sln`" /m /p:Configuration=$Configuration /p:Platform=x64 /nologo /v:minimal"
    $cmd = "call `"$launch`" && msbuild $msbuildArgs"

    Write-Host "Building $Configuration|x64 via EWDK ..."
    & cmd.exe /c $cmd
    if ($LASTEXITCODE -ne 0) { throw "MSBuild failed (exit $LASTEXITCODE)." }

    $outDir = Join-Path $RepoRoot "vendor/wnbd/vstudio/x64/$Configuration/driver"
    foreach ($f in 'wnbd.sys', 'wnbd.inf', 'wnbd.cat') {
        $fp = Join-Path $outDir $f
        if (-not (Test-Path $fp)) { throw "Expected build artifact missing: $fp" }
    }
    Write-Host "Build OK. Driver artifacts in: $outDir"
    Write-Output $outDir
}
finally {
    if ($mountedIso) { Dismount-DiskImage -ImagePath $EwdkIso | Out-Null }
}
