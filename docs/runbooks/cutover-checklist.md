# Cutover Checklist

## Pre-cutover
- Confirm approved release manifest and signed tag.
- Confirm backup completed and verified off-host copy exists.
- Confirm migration rehearsal report is approved.
- Confirm user communication and downtime window are published.

## Cutover window
- Freeze non-critical changes.
- Deploy target compose version.
- Run schema migrations/patches.
- Restore/import planned datasets as required.
- Execute smoke test script and manual login check.

## Post-cutover
- Validate key workflows (admissions, student profile, finance read path).
- Confirm background workers and scheduler are healthy.
- Monitor logs and queue depth for first 60 minutes.
- Send go-live confirmation to stakeholders.
