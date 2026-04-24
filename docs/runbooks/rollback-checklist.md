# Rollback Checklist

## Trigger criteria
- Critical workflow failure with no safe hotfix.
- Data integrity risk detected post-deploy.
- Sustained outage beyond agreed threshold.

## Rollback steps
- Announce rollback start to stakeholders.
- Stop current stack safely.
- Restore previous release manifest/images.
- Restore DB/sites backup from approved checkpoint.
- Restart stack and run smoke checks.

## Post-rollback
- Confirm service restoration and user access.
- Record root cause and impact summary.
- Open incident action items and schedule fix-forward plan.
