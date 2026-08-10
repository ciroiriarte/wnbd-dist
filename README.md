# wnbd-dist

Build, **Microsoft-attestation-sign**, and publish the [WNBD][wnbd] Windows
kernel driver (`wnbd.sys`) so downstream projects can bundle a signed driver
that loads on stock Windows 10/11 with Secure Boot enabled.

Primary consumer: the [`pbs-client-win`][pbs] Proxmox Backup Server client, for
on-demand block-device mount of restored images.

> **Why this repo exists.** A kernel-mode driver will not load on a normal
> Windows machine unless the driver package is signed by Microsoft (attestation
> or WHQL). A self-signed / ordinary Authenticode cert — the kind used for an
> MSI or EXE — is **not** sufficient. Upstream WNBD ships only test-signed
> binaries (the Microsoft-signed build lives solely inside the Ceph-for-Windows
> MSI), so a downstream distributor must produce its own MS-signed build. See
> [cloudbase/wnbd#89][issue89].

## What this is (and isn't)

- **Is:** a thin *distribution* wrapper — it pins upstream WNBD as a submodule
  and adds build + CAB packaging + signing + release tooling.
- **Isn't:** a fork. No driver source is modified unless a patch exists under
  [`patches/`](patches/); each such change is marked in its patch file.

## Layout

```text
wnbd-dist/
├── vendor/wnbd/          # git submodule — cloudbase/wnbd pinned to a tag (0.7.0)
├── patches/              # optional git-format-patch files applied before build
├── scripts/
│   ├── apply-patches.ps1        # apply patches/ onto the submodule
│   ├── Invoke-EwdkBuild.ps1     # build Release|x64 via the EWDK
│   ├── New-DriverCab.ps1        # InfVerif + Inf2Cat + CAB + EV-sign
│   ├── Submit-Attestation.ps1   # Partner Center Hardware API submit + download
│   └── Test-DriverSignature.ps1 # verify MS signature on the returned package
├── .github/workflows/
│   ├── build.yml         # CI: build + validate, unsigned artifact (review only)
│   └── release.yml       # tag vX.Y.Z: build → EV-sign → attest → verify → Release
├── docs/
│   ├── partner-center-onboarding.md
│   └── downstream-msi-guide.md
├── LICENSE               # LGPL-2.1 (matches upstream)
└── NOTICE.txt            # attribution + LGPL source offer
```

## Status

Scaffolding is complete and the pipeline is wired end-to-end, but **it has not
yet produced a signed release** — that requires the one-time prerequisites below
and a first real run. Nothing here is verified against a live Partner Center
account yet.

## Prerequisites (one-time)

1. **EV code-signing certificate** on an HSM / cloud key service (not exportable).
2. **Microsoft Hardware Developer Program** account in Partner Center.
3. **EWDK** (Enterprise WDK) for building — pin a specific version for
   reproducibility. Upstream targets VS2019 build tools + WDK 10.0.20348.
4. For CI automation: an **Entra ID app** with a Partner Center *Driver
   Submitter* role.

Full walkthrough: [`docs/partner-center-onboarding.md`](docs/partner-center-onboarding.md).

## Build + sign (local)

```powershell
git submodule update --init --recursive
./scripts/apply-patches.ps1
./scripts/Invoke-EwdkBuild.ps1 -EwdkRoot 'D:\EWDK'          # or -EwdkIso <path>
./scripts/New-DriverCab.ps1 -DriverDir vendor/wnbd/vstudio/x64/Release/driver `
    -SignCommand 'AzureSignTool sign -kvu $env:AKV_URL -kvc wnbd-ev -kvi $env:AZ_ID -kvs $env:AZ_SECRET -tr http://timestamp.digicert.com -td sha256 -fd sha256 {CAB}'
# First time: upload release-staging/wnbd.cab in the Partner Center portal.
# Once proven, automate with Submit-Attestation.ps1.
./scripts/Test-DriverSignature.ps1 -SignedDir release-staging/signed
```

CI does the same on a `vX.Y.Z` tag and publishes a GitHub Release. Signing runs
only inside the protected `signing` environment; the EV key is never a plain
secret.

## Bumping the pinned WNBD version

```bash
cd vendor/wnbd && git fetch --tags && git checkout <newtag> && cd ../..
git add vendor/wnbd && git commit -m "bump WNBD to <newtag>"
git tag v<newtag> && git push --tags   # triggers release.yml
```

## Rebuilding from source (LGPL-2.1)

Every release bundles `wnbd-source.tar.gz` (the exact pinned upstream commit)
plus any `patches.zip`. You may rebuild and replace `wnbd.sys` with your own
compatible build using the scripts above. See [`NOTICE.txt`](NOTICE.txt).

## License

Build/packaging tooling and this repo: LGPL-2.1, matching upstream WNBD, which
is © Cloudbase Solutions Srl and contributors. WNBD source is not modified
except via clearly-marked patches.

[wnbd]: https://github.com/cloudbase/wnbd
[pbs]: https://github.com/ciroiriarte/pbs-client-win
[issue89]: https://github.com/cloudbase/wnbd/issues/89
