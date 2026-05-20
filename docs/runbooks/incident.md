# Runbook: Incident

For when something is on fire and you need to coordinate response, not just
ship a fix.

---

## In the first 5 minutes

1. **Stop the bleeding**: if a recent deploy is actively making things
   worse, trigger a rollback ([rollback.md](rollback.md)).
2. **Open a channel**: post a short message to engineering chat with
   `INCIDENT:` prefix. Include the env, the symptom in user terms, when
   it started.
3. **Acknowledge** any SNS alarm pages so others know someone is on it.

---

## Triage: where to look

| Symptom | First place to look |
|---|---|
| "Site won't load" | Frontend container status: `aws ssm start-session --target <ec2>` → `docker ps`, `docker logs --tail 100 biomate-frontend-deploy` |
| "API errors" | Galaxy backend: `docker logs --tail 200 biomate-galaxy-deploy 2>&1 \| grep -iE "error\|raise"` |
| "Slow" | CloudWatch alarms; check EC2 CPU + RDS CPU; check that the idle alarm isn't masking the inverse problem |
| "Deploy stuck" | GHA workflow run; SSM command history `aws ssm list-commands` |
| "Cost spike" | Check for orphan instances — every EC2 should have an `Env` tag + an idle alarm. The L14 lesson cost $1,400 because dev had neither. |
| "Lost data" | RDS automated backups + manual snapshots. For test env (no backups), restore is from the latest `pre-<release-tag>` snapshot if a major-track gate created one. |

---

## Common root causes (from past incidents in this fork)

| Symptom | Likely cause | Lesson# |
|---|---|---|
| Container missing deps after deploy | Runtime `pip install` from sync_to_dev.sh masking missing requirements | L2 |
| Galaxy crash: `Tool config file not found` | Missing `lib/galaxy/config/sample/*.sample` copy in Dockerfile | L4 |
| Galaxy crash: `RevisionNotFoundError` / `NoVersionTableError` | Galaxy fork's alembic multi-head (Task #19, still open) | — |
| ECR pull timeout from EC2 | VPC interface endpoint SG doesn't allow port 443 from app SG | (P1.3 fix) |
| `docker compose up` ignores updated `.env` | Idempotent up doesn't recreate; need `--force-recreate` | (P2.2 fix) |
| Container "running" but unreachable | Healthcheck only watches container; need external HTTP probe | L21 |

---

## Communication template

Post one of these to the incident channel:

```
INCIDENT: <env> — <one-line user-visible symptom>
Started:  <UTC time>
Owner:    <your handle> — currently triaging
Status:   <one of: investigating | mitigating | mitigated | resolved>
Impact:   <e.g. "users can't log in" / "deploys queued but not running">
Next update in: <15 min>
```

Update every 15 min until resolved. Final update should be the
mitigation summary + a link to the post-mortem doc.

---

## After resolution: post-mortem

Within 48 hours, write a doc at `docs/<YYYYMMDD>_INCIDENT_<short-name>.md`
covering:

1. **Timeline** (UTC timestamps): when it started, when it was detected,
   when each mitigation step ran, when it resolved.
2. **Impact**: scope (which envs, which users), duration, what was lost.
3. **Root cause**: the one specific change or condition that caused this.
4. **What worked**: monitoring/alarms/runbooks that helped.
5. **What didn't**: gaps that delayed detection or response.
6. **Action items**: concrete, owned, dated. Add to the lessons register
   in `docs/20260514_CICD_REBUILD_PLAN.md` §6.3 if it's a class of bug
   the pipeline should now guard against.

The lessons register IS the institutional memory. Every new entry tightens
the next deploy.
