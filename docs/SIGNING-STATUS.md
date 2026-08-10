# Signing status

**Current state: Microsoft attestation signing is PARKED (deferred).**

We are pursuing sponsored code signing via **OSSign** instead of buying our own
EV certificate + running the Partner Center attestation flow ourselves. Until
that sponsorship lands, no Microsoft-signed WNBD release will be produced.

The pipeline in this repo (`scripts/`, `.github/workflows/release.yml`) remains
ready; it is simply not run until we have a signing path.

## Interim: develop/test with an UNSIGNED driver
While signing is parked, WNBD work happens on a Windows VM configured to load
unsigned/test-signed kernel drivers:

- Secure Boot **disabled**, `bcdedit /set testsigning on`.
- Self-signed test certificate trusted (Root + TrustedPublisher) for our own
  builds, or the Cloudbase test-signed driver from the Ceph MSI.
- **Never** a production/end-user configuration — test signing shows a desktop
  watermark and weakens driver-signature enforcement.

See the tracking issues in this repo for the parked signing tasks.

## Unpark checklist (when OSSign sponsorship is confirmed)
1. Record what OSSign provides: an EV cert we drive, or do they submit to
   Partner Center on our behalf and return the MS-signed package?
2. If they sign for us → wire their hand-off into `release.yml` (skip local EV
   signing; consume their signed `.sys`/`.cat`).
3. If they provide an EV cert we hold → resume issues #1–#5 as written.
4. Cut the first signed release and flip `pbs-client-win` to the signed driver.
