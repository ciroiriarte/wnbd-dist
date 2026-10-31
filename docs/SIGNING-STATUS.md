# Signing status

**Current state: no Microsoft-signed release yet. Target path is WHQL (HLK)
through OSSign, so the driver loads on Windows Server.**

## Decision (2026-10-31)

`pbs-client-win` must support **Windows Server** (2019 / 2022 / 2025). That
decides the signing route:

| Route | Loads on Windows 10/11 | Loads on Windows Server 2016+ | Notes |
|---|---|---|---|
| Attestation signing | yes | **no** | Free and quick, but Microsoft does not accept it on Server. Interim only. |
| WHQL (HLK-tested) | yes | **yes** | Requires passing HLK test runs per OS version/architecture. **Target.** |
| Test signing | only with `testsigning on` | only with `testsigning on` | Dev/test VMs only. Never for end users. |

So a WHQL signature is the release goal. Attestation is worth having only as an
interim release for Windows 10/11 users.

## Who does what (per OSSign, CREF#991034, 2026-10-29)

OSSign (ossign.org) sponsors signing for open-source projects. Their terms:

- **Eligibility**: public GitHub repo with **more than 6 months of documented
  history** and an OSI-approved licence. Applications are closed, but they
  queue projects that send details and meet the bar.
  `pbs-client-win` and this repo became public on 2026-10-31, so the earliest
  likely date is around **2027-04-30**.
- **WHQL** also needs **substantial community engagement** with the driver
  repo before they take it on.
- **HLK testing is our job.** OSSign does not run HLK. We run every required
  test (one per OS version and architecture) and hand them a complete
  **`.hlkx` package plus the exact sources** used to build the tested driver.
- **Attestation**: they build the driver themselves from our source and
  build instructions, then submit it. The process is manual and done as needed.
- **Signatures are OSSign's** (Microsoft Hardware Program certificate,
  referencing their backing company). There is no per-project certificate. A
  different company name requires our own Microsoft hardware partner account.
- Drivers should live in a **separate repo** from the main project. This
  already holds: source in `ciroiriarte/wnbd`, build tooling here.

This means we likely **don't need our own EV certificate or Partner Center
account** (issues #1, #3, #4), as long as OSSign submits on our behalf.

## What we need to build: the HLK pipeline

1. **HLK lab**
   - An HLK **controller** (Windows Server) with HLK Studio.
   - **Test machines** for each target OS: Windows Server 2019, 2022 and 2025
     (x64), plus a Windows 11 client. Each OS version needs its matching HLK kit.
   - Hosted as VMs on the Proxmox cluster, if Microsoft's rules allow VM-based
     testing for this driver class (to confirm).
2. **Test selection**: WNBD is a virtual Storport miniport. Confirm which HLK
   feature tests and playlist apply to it (to confirm; it affects effort a lot).
3. **Runs**: install the driver built from a pinned `ciroiriarte/wnbd` commit,
   run the playlist on each OS, and fix failures in the fork.
4. **Package**: merge the per-OS results into one `.hlkx` along with the driver
   package and the exact source commit, then hand it to OSSign.
5. **Repeat for every driver release.** Tens to hundreds of hours per release,
   per OSSign, so driver releases should be rare and deliberate.

## Interim: develop and test with an unsigned driver

Until a signed release exists, WNBD work happens on a Windows VM configured to
load unsigned or test-signed kernel drivers:

- Secure Boot **disabled**, `bcdedit /set testsigning on`.
- Self-signed test certificate trusted (Root + TrustedPublisher) for our own
  builds, or the Cloudbase test-signed driver from the Ceph MSI.
- **Never** a production/end-user configuration. Test signing shows a desktop
  watermark and weakens driver-signature enforcement.

Reference VM: VM143 (Windows Server 2022 Core), see
[`vm143-provision-report.md`](vm143-provision-report.md).

## Checklist

- [x] Make the repos public (`pbs-client-win`, `wnbd-dist`, `wnbd`): 2026-10-31.
- [ ] Reply to OSSign with project details and the WHQL/HLK plan; get queued.
- [ ] Publish build instructions in `ciroiriarte/wnbd` itself, since OSSign
      builds attestation submissions from source.
- [ ] Build community engagement: contribute back on cloudbase/wnbd#89 and
      coordinate with the Ceph-on-Windows effort before calling the fork canonical.
- [ ] Confirm the HLK test selection for a virtual Storport miniport, and
      whether VMs are acceptable test machines.
- [ ] Stand up the HLK lab (controller + Server 2019/2022/2025 + Windows 11).
- [ ] First full HLK pass on a pinned fork commit, producing a merged `.hlkx`.
- [ ] Submit through OSSign and cut the first WHQL-signed release.
- [ ] Optional interim: an attestation-signed release for Windows 10/11 only.
- [ ] Flip `pbs-client-win` to the signed driver (its issue #23).

## Impact on the existing pipeline

`scripts/` and `.github/workflows/release.yml` were written for the
self-managed attestation route (our EV certificate, our Partner Center
submission). Under the OSSign route:

- `Invoke-EwdkBuild.ps1` and `New-DriverCab.ps1` stay useful, as the documented
  build that OSSign and our HLK lab both reproduce.
- `Submit-Attestation.ps1` and the EV-signing steps are not needed unless we
  later register our own hardware partner account.
- `Test-DriverSignature.ps1` stays, for verifying what OSSign returns.
- Issues #1–#5 need re-scoping to match (EV certificate and Partner Center
  steps parked; HLK lab and `.hlkx` packaging added).
