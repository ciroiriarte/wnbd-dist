# Partner Center onboarding (one-time)

To attestation-sign the WNBD driver you need a Microsoft **Hardware Developer
Program** account and an **EV code-signing certificate**. This is the only part
of the pipeline that cannot be bootstrapped from CI — do it once, then CI reuses
the account.

## 1. Get an EV code-signing certificate
- Buy an **Extended Validation (EV)** code-signing cert from a CA (DigiCert,
  Sectigo, etc.). OV/standard certs are **not** accepted for driver submission.
- The private key must stay on an **HSM / hardware token / cloud key service**
  (Azure Key Vault Managed HSM, DigiCert KeyLocker, …). It is never exported.
- Organization validation can take days — start here.

## 2. Register for the Hardware Developer Program
- Sign in to Partner Center with a work/Entra account:
  https://partner.microsoft.com/dashboard/hardware
- Enroll in the **Windows Hardware** program. During enrollment you upload a
  file signed with your EV cert to prove key custody. **Every time the EV cert
  is renewed you must re-do this binding.**
- Roles: the enrolling user needs Partner Center admin; add a second maintainer
  with the **Hardware** role so onboarding isn't a bus-factor of one.

## 3. Create an Entra app for the Hardware Dashboard API (for CI automation)
- Register an Entra ID application; create a client secret **or** (preferred)
  configure **GitHub OIDC / workload identity federation** so CI needs no
  stored secret.
- In Partner Center → Account settings → User management → **Azure AD
  applications**, add the app and grant it a Hardware role such as
  **Driver Submitter**.
- Record `PC_TENANT_ID` and `PC_CLIENT_ID` as GitHub **secrets** in the
  protected `signing` environment. Use OIDC instead of `PC_CLIENT_SECRET`
  where possible.

## 4. First submissions: do them manually
Run the first 1–2 submissions through the portal to prove the CAB is well-formed
before trusting `Submit-Attestation.ps1`:
1. Build + package locally: `New-DriverCab.ps1 -DriverDir ... -SignCommand ...`
2. Portal → **Drivers → Submit new hardware** → upload `release-staging/wnbd.cab`.
3. Choose **attestation** signing, select the target OS versions.
4. Download the signed package, run `Test-DriverSignature.ps1` on it.

Once this round-trips cleanly, enable the automated `release.yml` path.

## References
- Attestation signing: https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-attestation
- Code-signing requirements (EV): https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-reqs
- Hardware Dashboard API: https://learn.microsoft.com/windows-hardware/drivers/dashboard/dashboard-api
