# Requirement: make the `GALAXY_JWT_SECRET` billing fix durable (dev) + verify prod

**Date:** 2026-07-28
**Owner:** _(assign — infra/ops colleague)_
**Priority:** P1 for prod check (blocks enabling the billing page); P2 for the dev GitHub-secret cleanup
**Est. effort:** ~20 min
**Background:** `docs/20260727_BILLING_PROXY_JWT_401_ROOTCAUSE.md`

---

## Context (1 paragraph)

The Node billing proxy (`frontend/server/routes.ts`) re-signs the JWT it forwards to the Galaxy
backend using `GALAXY_JWT_SECRET || JWT_SECRET`. Galaxy validates that token with **its** `JWT_SECRET`.
So the **invariant** is: **`GALAXY_JWT_SECRET` on the frontend must equal `JWT_SECRET` on the Galaxy
backend** (or be unset, in which case the proxy falls back to the frontend's `JWT_SECRET`). On dev,
`GALAXY_JWT_SECRET` had drifted to a stale 44-byte value while `JWT_SECRET` already matched Galaxy
(64-byte) — so **every `/api/billing/*` call returned `401 "Signature verification failed"`**.

A **live-container** fix was already applied to dev on 2026-07-28 (stale var removed from
`/opt/biomate/.env`, `biomate-dev-frontend` recreated; `/api/billing/{quota,usage}` now return 200).
**That fix is NOT durable** — a full from-scratch redeploy re-injects env from the GitHub secret, which
still holds the stale value. This requirement makes it durable and checks prod.

---

## Task 1 — Fix the dev GitHub secret (make dev durable)  · P2

The dev env comes from a GitHub secret (see `scripts/setup_github_env.sh` manifest; the container is
started with `--env-file /opt/biomate/.env` which is regenerated from those secrets on a full deploy).

**Do one of:**
- **Preferred — delete** the `GALAXY_JWT_SECRET` secret for the **dev** environment. Since the
  frontend and Galaxy already share the same `JWT_SECRET` on dev, the proxy's fallback to `JWT_SECRET`
  is correct and the override is unnecessary.
- **Or set it correctly** — `GALAXY_JWT_SECRET` = the dev Galaxy backend's `JWT_SECRET` value
  (64-byte). Get it from the running container:
  `aws ssm ... "docker exec biomate-galaxy-dev printenv JWT_SECRET"` (do not paste the value anywhere
  public).

**Acceptance:** after a subsequent full redeploy (or immediately, by re-checking `/opt/biomate/.env`),
`GALAXY_JWT_SECRET` is either absent or equals Galaxy's `JWT_SECRET`.

---

## Task 2 — Verify (and fix if needed) the invariant in PROD  · P1

The billing UI (`/billing`) is currently unrouted, but the moment it's enabled the same 401 will hit
prod if prod has the same drift. Verify **before** enabling billing.

**Check (read-only)** — compare the two secrets by checksum, do NOT print the values. Substitute the
prod instance id / container names:

```bash
GC=<prod-galaxy-container>      # e.g. biomate-galaxy-prod
FE=<prod-frontend-container>    # e.g. biomate-prod-frontend
docker exec $GC sh -lc 'printf "galaxy JWT_SECRET        cksum: "; printf %s "$JWT_SECRET" | cksum'
docker exec $FE sh -lc '[ -n "$GALAXY_JWT_SECRET" ] && { printf "fe GALAXY_JWT_SECRET   cksum: "; printf %s "$GALAXY_JWT_SECRET" | cksum; } || echo "fe GALAXY_JWT_SECRET: UNSET (ok — falls back to JWT_SECRET)"'
docker exec $FE sh -lc 'printf "fe JWT_SECRET            cksum: "; printf %s "$JWT_SECRET" | cksum'
```

**Pass condition:** either
- `fe GALAXY_JWT_SECRET` is **UNSET** and `fe JWT_SECRET` cksum == `galaxy JWT_SECRET` cksum, **or**
- `fe GALAXY_JWT_SECRET` cksum == `galaxy JWT_SECRET` cksum.

**If it fails** (drifted), fix the prod GitHub secret the same way as Task 1 (delete, or set to
Galaxy's `JWT_SECRET`) and redeploy/recreate the prod frontend so it re-reads env.

---

## End-to-end verification (both envs)

With a valid user JWT (login as any real user), the billing endpoints must return **200**, not 401:

```bash
curl -s https://<env-host>/api/billing/quota  -H "Authorization: Bearer <JWT>" -w '\n%{http_code}\n'
curl -s https://<env-host>/api/billing/usage  -H "Authorization: Bearer <JWT>" -w '\n%{http_code}\n'
# Expect 200 + a JSON usage breakdown (llm/compute/storage). 401 "Signature verification failed" = still drifted.
```

---

## Guardrail (already merged)

`scripts/setup_github_env.sh` now documents this invariant inline above the `SECRETS` manifest, so the
next person provisioning env sees the constraint. No code change is needed — the proxy code is
correct; this is purely an env/secret-hygiene issue.

## Out of scope / do NOT do

- Do **not** change the `GALAXY_JWT_SECRET || JWT_SECRET` precedence in `routes.ts` — it's correct and
  altering it could break an env that legitimately runs different frontend/Galaxy secrets.
- This is unrelated to the flat-tier / Lago-drop change (that's shipped and verified separately).
