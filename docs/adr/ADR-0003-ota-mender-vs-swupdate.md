# ADR-0003: Over-the-Air Update System — Mender vs SWUpdate

Date: 2026-05-14
Status: Proposed
Supersedes: Open decision "Mender vs SWUpdate for OTA" in `/eng` page (2026-05-14)

## Context

The device fleet (OSD62x-PM + IWR6843AOP, Yocto-based rootfs, ~8 GB eMMC) needs a remote update path before Production phase. The decision is high-urgency per the /eng board.

Three independent constraints shape the choice:

1. **21 CFR 820 (FDA Quality System Regulation)** applies because this is a medical device. The Design History File requires an auditable record of every firmware version deployed to every device, including who initiated the rollout, what failed, and what rolled back. The OTA system must produce or feed that record.

2. **Pilot facility install workflow.** MOH 301–312 is the launch site. Devices ship pre-flashed to a base image; first OTA is the first call home. Field updates must be hands-off — nurses cannot do anything beyond plugging in the device.

3. **BSP origin.** The board runs TI Processor SDK 11.02.08.02. Mender is the **default OTA system** in that SDK's reference Yocto layer. SWUpdate is supported but requires building from `meta-swupdate` and replacing the SDK's default mender artifact recipes.

Two candidates are widely used in production Linux embedded:

- **Mender** (Northern.tech, GPLv3 client / Apache server) — full-stack: client + server + delta updates + signed images + state scripts + rollback.
- **SWUpdate** (sbabic, MIT) — single client binary; pairs with any HTTPS endpoint you build, or a paid hawkBit-style server.

The /eng one-liner hint ("Mender adds ~8 MB to rootfs; SWUpdate is lighter but less managed") implies the team is weighing size vs. management overhead. Both numbers are accurate but neither is load-bearing for this product.

## Decision

Use **Mender** with **self-hosted artifact delivery** from `ambientintel/ambientcloud` (S3 + signed URLs via existing url-minter pattern). Do **not** subscribe to Mender Hosted; run mender-server self-hosted alongside the existing CDK stacks, or use the simpler "static artifact URLs + Mender client polling" pattern.

Rationale:

- **BSP path of least resistance.** TI SDK 11 ships meta-mender wired up. Swapping in SWUpdate is a Yocto layer rebuild plus ~2 weeks of integration work that adds zero product value for this fleet size and update model.
- **21 CFR 820 audit trail is built in.** Mender's deployment-by-deployment log (which devices accepted, which rolled back, which failed signature check) is what an FDA auditor expects to see. SWUpdate has to grow that out of `journald` + custom server-side log shipping.
- **A/B partition + rollback-on-failed-boot is built in.** Mender's `bootcount` + grub/u-boot integration auto-rolls back if the device fails to fully boot after an update. SWUpdate supports this too but requires hand-wiring it into the bootloader.
- **Self-hosted, not subscription.** Mender's GPL client is free; the server is Apache-licensed. We can run the server on EKS or skip it entirely and use static signed S3 URLs (mender supports this — "remote terminal" features are the only piece that require the full server). No Mender Inc. dependency.
- **8 MB rootfs footprint is irrelevant** on an 8 GB eMMC device. Even at 1000× our planned fleet density, this is not a constraint that should drive the choice.

## Alternatives Considered

### SWUpdate + self-built backend (rejected)

- Pros: ~2 MB on-device, more flexible update format (rootfs + bootloader + DTB + per-application in one CPIO), MIT license vs. GPLv3 (relevant if proprietary client mods are ever needed — they aren't here).
- Rejected because:
  - TI SDK 11 doesn't ship the wiring; meta-swupdate integration is real work
  - The "less managed" framing is a feature in some contexts (when you have specialists who want low-level control) but a liability here — the team is small, time-to-market is critical, and the rollback/audit/signing pieces are exactly the parts you want batteries-included
  - The 21 CFR 820 audit trail would have to be built. Not infeasible, but redundant when Mender does it.

### Mender Hosted (subscription) (rejected)

- Pros: Zero infra ops, dashboard included, multi-tenant device groups, support contracts.
- Rejected because:
  - Mender Inc. would join the BAA list and the IRB protocol's data-flow diagram — adding a vendor with device-side access to the PHI boundary is a real compliance cost
  - Recurring cost per device — even free tier limits make this expensive at fleet scale
  - We already have AWS-side artifact hosting (S3 + KMS + signed URLs) — operationally cheap

### RAUC (Pengutronix) (rejected without deep evaluation)

- Pros: Solid alternative, similar audit/signing/rollback model, widely used in industrial Linux.
- Rejected for the same BSP reason as SWUpdate — TI SDK 11 doesn't ship it wired. Worth revisiting if the OEM stack changes.

### Cloud-Init / one-shot remote shell (rejected)

- Pros: Trivial to build a v0.
- Rejected: No rollback, no audit trail, no atomicity. Fails any 21 CFR 820 audit on day one.

## Architecture

```
Device                                AWS account 741448953538
─────────                              ──────────────────────────
mender-client (in rootfs)              ambient-prod-firmware S3 bucket
  ├─ polls every 30 min                  └─ artifacts/<version>.mender (KMS-encrypted)
  │  HEAD against signed URL                  └─ signed with internal X.509 cert
  ├─ A/B partitions                                 └─ verified on device
  │  /dev/mmcblk0p2 ↔ /dev/mmcblk0p3
  ├─ bootcount auto-rollback           ambient-prod-ota-controller Lambda
  │  (u-boot integration)                ├─ generates per-device signed URLs (15 min TTL)
  └─ deployment log → JSON               ├─ enforces device cohort policy
     POST to /api/ota/report             └─ writes deployment record → DDB
                                       
                                       ambient-prod-ota-reports DDB
                                         └─ per-device, per-version, per-outcome
                                            (the 21 CFR 820 audit trail)
```

Three new AWS-side pieces; all are small additions to the existing ambientcloud stacks:

- S3 bucket + KMS encryption (mirrors `parquet-data` bucket pattern)
- Lambda mints signed URLs (mirrors `url-minter` pattern — same X.509-cert-on-device auth model)
- DDB table for deployment reports (mirrors `alerts`, `daily-updates` tables)

## Consequences

### Positive
- BSP integration effort: ~1–2 days (mender is already in the Yocto config; just wire up the server endpoint env var and signing key).
- 21 CFR 820 audit trail comes for free — Mender deployment records + DDB-stored device reports compose into the FDA-acceptable artifact.
- Rollback-on-failed-boot works on day one with no custom bootloader code.
- Same AWS-side patterns (S3 + KMS + signed URLs + DDB) as everything else — operationally familiar.

### Negative
- GPLv3 client means any modifications to the mender-client binary itself must be open-sourced. Not a real constraint — we won't modify it.
- ~8 MB rootfs cost. Negligible.
- One more SBOM line (mender-client + its Go deps) for the FDA submission. Minor admin overhead.

### Out of scope for this ADR (track separately)
- Choice of bootloader signing key infrastructure (existing AWS KMS asymmetric keys or new HSM-backed PKI?)
- Cohort/canary rollout policy (1 device → 10% → 100%?)
- Update cadence (weekly? on-incident only?)
- How to handle a device that fails 3 sequential updates (alert → ticket → physical service call)

## Implementation Steps (post-decision)

1. Confirm mender-client is included in current Yocto build: `bitbake -e core-image | grep MENDER`
2. Set `MENDER_SERVER_URL` to a placeholder local-dev value; verify polling works
3. Generate signing key pair; commit public key to firmware repo, store private in AWS Secrets Manager
4. Stand up the three AWS pieces (S3 bucket, Lambda, DDB) — new `OtaStack` in ambientcloud
5. End-to-end test: build artifact → upload → device polls → update applies → rolls back on forced failure
6. Document deployment-record schema for FDA DHF (decision-record + binary build hash + signature + per-device outcome)

## References

- Mender architecture: <https://docs.mender.io/architecture/overview>
- TI SDK 11 Mender recipe: `meta-arago/recipes-mender/`
- 21 CFR 820 §820.30 (design controls) — DHF inclusion of OTA log
- Existing patterns to mirror: `services/url-minter/` (signed-URL minting), `infra/stacks/data_stack.py` (KMS-encrypted DDB table)
