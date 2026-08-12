# VM 143 Provision Report

Generated: 2026-08-10T15:02:48-03:00

## Summary

- PVE host: `bigiron.lan`
- VMID/name: `143` / `pbs-win-wnbd-test`
- Source template: `9022` / `ci-win2022-std-core-en-us`
- Storage: `dstore01`
- Guest IPv4: `10.2.0.147` (DHCP, VLAN 100) — reachable, RDP/3389 open
- Test-signing state: `Yes`
- Secure Boot state: `False` from `Confirm-SecureBootUEFI`
- Code-signing cert subject: `CN=WNBD Test Signing`
- Code-signing cert thumbprint: `29038CDFE6450163D28F118A92D012599E0B0D0A`
- Guest cert/artifact path: `C:\wnbd-test\wnbd-test.cer`, `C:\wnbd-test\wnbd-test.pfx`
- Local credentials file: `/home/ciro/.config/pbs-client-win/vm143.env`

### Post-provision network fix
The clone initially got a link-local address (`169.254.33.174`) — the template's
`net0` has **no VLAN tag**, but this network serves DHCP on **VLAN 100** (matching
build VM 141). Fixed after provisioning:

```sh
qm set 143 --net0 virtio=BC:24:11:E0:86:09,bridge=vmbr0,tag=100,firewall=0
qm guest exec 143 -- cmd /c "ipconfig /renew"
```

Result: DHCP lease `10.2.0.147`. (If the template is later updated, add `tag=100`
to its `net0` so future clones get DHCP directly.)

## Commands Run

### 1. Preflight

```sh
ssh -o BatchMode=yes root@bigiron.lan 'set -e
qm status 143
'
```

Expected failure confirmed:

```text
Configuration file 'nodes/bigiron/qemu-server/143.conf' does not exist
```

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm config 9022 | grep "^template"'
```

```text
template: 1
```

```sh
ssh -o BatchMode=yes root@bigiron.lan 'pvesm status | grep "^dstore01"'
```

```text
dstore01              dir     active      3902387476       769250632      3133136844   19.71%
```

### 2. Clone

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm clone 9022 143 --name pbs-win-wnbd-test --full'
```

Result: full clone completed successfully, including EFI, cloud-init, OS disk, and TPM state disks.

### 3. Base Config

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm set 143 --cores 4 --memory 6144 --onboot 0 --tags windows,wnbd,test,unsigned-driver --description "WNBD unsigned-driver test target. Secure Boot OFF + testsigning ON. Clone of template 9022. Prep-only (no driver installed)."'
```

### 4. Disable Secure Boot

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm set 143 --efidisk0 dstore01:1,efitype=4m,pre-enrolled-keys=0'
```

Result: new VM 143 EFI vars disk was created with `pre-enrolled-keys=0`; TPM was not changed.

### 5. Credentials

```sh
ssh -o BatchMode=yes root@bigiron.lan "qm set 143 --cipassword '<generated-password-redacted>' --ipconfig0 ip=dhcp"
```

Local file created/updated with mode `600`:

```text
/home/ciro/.config/pbs-client-win/vm143.env
```

Stored fields:

```text
VM143_HOST=169.254.33.174
VM143_ADMIN_USER=Administrator
VM143_ADMIN_PASSWORD=<redacted>
VM143_VMID=143
```

### 6. Start

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm start 143'
```

### 7. Initial Guest-Agent Wait And IPv4 Fetch

```sh
ssh -o BatchMode=yes root@bigiron.lan 'for i in $(seq 1 48); do if qm agent 143 ping >/tmp/vm143-agent-ping.out 2>/tmp/vm143-agent-ping.err; then echo "agent-ready attempt=$i"; cat /tmp/vm143-agent-ping.out; exit 0; fi; echo "agent-wait attempt=$i"; sleep 10; done; echo "agent-timeout"; cat /tmp/vm143-agent-ping.err 2>/dev/null || true; exit 1'
```

```text
agent-wait attempt=1
agent-wait attempt=2
agent-ready attempt=3
```

The first immediate network query returned `QEMU guest agent is not running`, so the same bounded wait was repeated:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'for i in $(seq 1 48); do if qm agent 143 ping >/tmp/vm143-agent-ping2.out 2>/tmp/vm143-agent-ping2.err; then echo "agent-ready attempt=$i"; cat /tmp/vm143-agent-ping2.out; exit 0; fi; echo "agent-wait attempt=$i"; sleep 10; done; echo "agent-timeout"; cat /tmp/vm143-agent-ping2.err 2>/dev/null || true; exit 1'
```

```text
agent-wait attempt=1
agent-ready attempt=2
```

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest cmd 143 network-get-interfaces'
```

Initial Ethernet IPv4: `169.254.33.174`.

### 8. Guest Configuration

Enable test-signing:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- cmd /c bcdedit /set testsigning on'
```

Raw output:

```json
{
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "The operation completed successfully.\r\n"
}
```

Create cert, export CER/PFX, and import trust:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- powershell -NoProfile -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Force C:\\wnbd-test | Out-Null; \$c = New-SelfSignedCertificate -Subject '\''CN=WNBD Test Signing'\'' -Type CodeSigningCert -CertStoreLocation Cert:\\LocalMachine\\My -KeyUsage DigitalSignature -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(5); Export-Certificate -Cert \$c -FilePath C:\\wnbd-test\\wnbd-test.cer | Out-Null; Import-Certificate -FilePath C:\\wnbd-test\\wnbd-test.cer -CertStoreLocation Cert:\\LocalMachine\\Root | Out-Null; Import-Certificate -FilePath C:\\wnbd-test\\wnbd-test.cer -CertStoreLocation Cert:\\LocalMachine\\TrustedPublisher | Out-Null; Export-PfxCertificate -Cert \$c -FilePath C:\\wnbd-test\\wnbd-test.pfx -Password (ConvertTo-SecureString '\''wnbdtest'\'' -AsPlainText -Force) | Out-Null; \$c.Subject + '\''|'\'' + \$c.Thumbprint"'
```

Raw output:

```json
{
   "err-data" : "Import-Certificate : Access is denied. (Exception from HRESULT: 0x80070005 (E_ACCESSDENIED))\r\nAt line:1 char:459\r\n+ ... | Out-Null; Import-Certificate -FilePath C:\\wnbd-test\\wnbd-test.cer - ...\r\n+                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\r\n    + CategoryInfo          : NotSpecified: (:) [Import-Certificate], UnauthorizedAccessException\r\n    + FullyQualifiedErrorId : System.UnauthorizedAccessException,Microsoft.CertificateServices.Commands.ImportCertific \r\n   ateCommand\r\n \r\n",
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "CN=WNBD Test Signing|29038CDFE6450163D28F118A92D012599E0B0D0A\r\n"
}
```

Because PowerShell emitted an access-denied error for one trust-store import, `certutil` was used to complete TrustedPublisher store creation/import from the already-created CER:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- cmd /c "certutil -addstore Root C:\\wnbd-test\\wnbd-test.cer && certutil -addstore TrustedPublisher C:\\wnbd-test\\wnbd-test.cer"'
```

Raw output:

```json
{
   "exitcode" : -2147024894,
   "exited" : 1,
   "out-data" : "Root \"Trusted Root Certification Authorities\"\r\nSignature matches Public Key\r\nRelated Certificates:\r\n\r\nExact match:\r\nElement 8:\r\nSerial Number: 773bda7a3959e0944232fc22a183b685\r\nIssuer: CN=WNBD Test Signing\r\n NotBefore: 8/10/2026 5:51 PM\r\n NotAfter: 8/10/2031 6:01 PM\r\nSubject: CN=WNBD Test Signing\r\nSignature matches Public Key\r\nRoot Certificate: Subject matches Issuer\r\nCert Hash(sha1): 29038cdfe6450163d28f118a92d012599e0b0d0a\r\n\r\nCertificate \"WNBD Test Signing\" already in store.\r\nCertUtil: -addstore command completed successfully.\r\nTrustedPublisher \"Trusted Publishers\"\r\nCannot open existing Cert store.  Use -f option to force Cert store creation.\r\nCertUtil: -addstore command FAILED: 0x80070002 (WIN32: 2 ERROR_FILE_NOT_FOUND)\r\nCertUtil: The system cannot find the file specified.\r\n"
}
```

Forced TrustedPublisher store creation/import:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- cmd /c "certutil -f -addstore TrustedPublisher C:\\wnbd-test\\wnbd-test.cer"'
```

Raw output:

```json
{
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "TrustedPublisher \"Trusted Publishers\"\r\nSignature matches Public Key\r\nCertificate \"WNBD Test Signing\" added to store.\r\nCertUtil: -addstore command completed successfully.\r\n"
}
```

### 9. Reboot

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- cmd /c shutdown /r /t 3'
```

Raw output:

```json
{
   "exitcode" : 0,
   "exited" : 1
}
```

Post-reboot agent wait:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'for i in $(seq 1 48); do if qm agent 143 ping >/tmp/vm143-agent-ping3.out 2>/tmp/vm143-agent-ping3.err; then echo "agent-ready attempt=$i"; cat /tmp/vm143-agent-ping3.out; exit 0; fi; echo "agent-wait attempt=$i"; sleep 10; done; echo "agent-timeout"; cat /tmp/vm143-agent-ping3.err 2>/dev/null || true; exit 1'
```

```text
agent-wait attempt=1
agent-ready attempt=2
```

## Raw Verify Output

### Test-Signing

Command:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- cmd /c bcdedit /enum {current}'
```

Output:

```json
{
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "\r\nWindows Boot Loader\r\n-------------------\r\nidentifier              {current}\r\ndevice                  partition=C:\r\npath                    \\Windows\\system32\\winload.efi\r\ndescription             Windows Server\r\nlocale                  en-US\r\ninherit                 {bootloadersettings}\r\nrecoverysequence        {087e79de-91a1-11f1-993c-ba205f659781}\r\ndisplaymessageoverride  Recovery\r\nrecoveryenabled         Yes\r\ntestsigning             Yes\r\nisolatedcontext         Yes\r\nallowedinmemorysettings 0x15000075\r\nosdevice                partition=C:\r\nsystemroot              \\Windows\r\nresumeobject            {087e79da-91a1-11f1-993c-ba205f659781}\r\nnx                      OptOut\r\n"
}
```

### Secure Boot

Command:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- powershell -NoProfile -Command "try { Confirm-SecureBootUEFI } catch { \$_.Exception.Message }"'
```

Output:

```json
{
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "False\r\n"
}
```

### TrustedPublisher Cert

Command:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest exec 143 -- powershell -NoProfile -Command "Get-ChildItem Cert:\\LocalMachine\\TrustedPublisher | Where-Object Subject -match '\''WNBD Test Signing'\'' | Select-Object -Expand Thumbprint"'
```

Output:

```json
{
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "29038CDFE6450163D28F118A92D012599E0B0D0A\r\n"
}
```

### Final Network Interfaces

Command:

```sh
ssh -o BatchMode=yes root@bigiron.lan 'qm guest cmd 143 network-get-interfaces'
```

Output:

```json
[
   {
      "hardware-address" : "bc:24:11:e0:86:09",
      "ip-addresses" : [
         {
            "ip-address" : "fe80::c99:a1eb:527b:21ae%4",
            "ip-address-type" : "ipv6",
            "prefix" : 64
         },
         {
            "ip-address" : "169.254.33.174",
            "ip-address-type" : "ipv4",
            "prefix" : 16
         }
      ],
      "name" : "Ethernet",
      "statistics" : {
         "rx-bytes" : 3517,
         "rx-dropped" : 51,
         "rx-errs" : 0,
         "rx-packets" : 0,
         "tx-bytes" : 6334,
         "tx-dropped" : 0,
         "tx-errs" : 0,
         "tx-packets" : 0
      }
   },
   {
      "ip-addresses" : [
         {
            "ip-address" : "::1",
            "ip-address-type" : "ipv6",
            "prefix" : 128
         },
         {
            "ip-address" : "127.0.0.1",
            "ip-address-type" : "ipv4",
            "prefix" : 8
         }
      ],
      "name" : "Loopback Pseudo-Interface 1",
      "statistics" : {
         "rx-bytes" : 0,
         "rx-dropped" : 0,
         "rx-errs" : 0,
         "rx-packets" : 0,
         "tx-bytes" : 0,
         "tx-dropped" : 0,
         "tx-errs" : 0,
         "tx-packets" : 0
      }
   }
]
```

## Install A WNBD Driver Later

Prep only was performed; no WNBD driver was installed.

Later, copy `wnbd.sys`, `wnbd.inf`, and `wnbd.cat` into the guest. If using a local build, sign it with `C:\wnbd-test\wnbd-test.pfx` using PFX password `wnbdtest`. Then install with:

```cmd
pnputil /add-driver wnbd.inf /install
```
