# Consuming the signed driver from the PBS client MSI

The `pbs-client-win` installer bundles the Microsoft-signed WNBD driver produced
by this repo. Do **not** rebuild or re-sign the driver in the client repo —
recompiling invalidates Microsoft's signature. Consume the exact published
artifact.

## 1. Fetch the signed artifact at build time
Pin a released version and download it during the client's installer build:

```powershell
$ver = '0.7.0'   # keep in lockstep with a wnbd-dist release tag
gh release download "v$ver" --repo ciroiriarte/wnbd-dist `
    --pattern 'wnbd-signed-*.zip' --dir build/wnbd
Expand-Archive build/wnbd/wnbd-signed-*.zip build/wnbd/extracted -Force
```

Verify before bundling (fail the build if it isn't MS-signed):

```powershell
signtool verify /kp /v build/wnbd/extracted/wnbd.cat
```

## 2. Install via INF/CAT — not by copying the .sys
Copying `wnbd.sys` into `System32\drivers` does **not** bind Microsoft's catalog
into the Driver Store and the service will fail to start. Install the driver
package proper.

WiX (`installer/Package.wxs`) options:
- **`pnputil` on install** (simplest): run
  `pnputil /add-driver wnbd.inf /install` from a deferred custom action, and
  `pnputil /delete-driver wnbd.inf /uninstall` on removal.
- **WiX `difx:Driver`** element (DIFxApp) if you prefer declarative driver
  install.

Ship all of `wnbd.sys`, `wnbd.inf`, `wnbd.cat` together — the catalog is what
carries the Microsoft signature.

## 3. Runtime
Only after install + service start can the app open `\\.\wnbd`. If service start
fails with `0xC0000428` the bundled driver is not properly MS-signed — re-check
step 1.

## Version coupling
Record the consumed `wnbd-dist` tag in the client repo (e.g. a `WNBD_VERSION`
build variable) so the driver version shipped is always traceable to a specific
signed release.
