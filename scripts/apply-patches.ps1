#Requires -Version 5.1
<#
.SYNOPSIS
    Apply optional local patches to the pinned WNBD submodule before building.
.DESCRIPTION
    Patches live in ../patches/*.patch as `git format-patch` output. They are
    applied in filename order onto the checked-out submodule at vendor/wnbd.
    This keeps the LGPL source delta explicit: the released source is
    (submodule commit) + (patches/) and nothing else.

    Idempotent: patches already present in the working tree are skipped
    (`git apply --check` gate). Run after `git submodule update --init`.
.NOTES
    No-op (exit 0) when patches/ is empty.
#>
[CmdletBinding()]
param(
    [string]$SubmodulePath = (Join-Path $PSScriptRoot '..' 'vendor' 'wnbd'),
    [string]$PatchDir      = (Join-Path $PSScriptRoot '..' 'patches')
)
$ErrorActionPreference = 'Stop'

$patches = @(Get-ChildItem -Path $PatchDir -Filter '*.patch' -ErrorAction SilentlyContinue | Sort-Object Name)
if ($patches.Count -eq 0) {
    Write-Host "No patches in $PatchDir — using pristine upstream source."
    exit 0
}

foreach ($p in $patches) {
    Write-Host "Applying $($p.Name) ..."
    # --check first so a partially-applied patch doesn't corrupt the tree.
    & git -C $SubmodulePath apply --check $p.FullName 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Already applied? Verify by reverse-check; if that succeeds, skip.
        & git -C $SubmodulePath apply --reverse --check $p.FullName 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "  already applied, skipping."; continue }
        throw "Patch $($p.Name) does not apply cleanly to the pinned submodule."
    }
    & git -C $SubmodulePath apply $p.FullName
    if ($LASTEXITCODE -ne 0) { throw "Failed applying $($p.Name)." }
}
Write-Host "All patches applied."
