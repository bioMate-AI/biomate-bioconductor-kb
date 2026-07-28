# Billing UI 401 — Root Cause: stale `GALAXY_JWT_SECRET` on the dev frontend

**Date:** 2026-07-27
**Status:** ✅ RESOLVED on dev 2026-07-28 (removed stale `GALAXY_JWT_SECRET` from `/opt/biomate/.env`
+ recreated `biomate-dev-frontend`). `/api/billing/{quota,usage}` now return **200** through the
public proxy. **Follow-ups still open:** (1) remove/correct the stale `GALAXY_JWT_SECRET` in the dev
**GitHub secret** so it doesn't return on the next full redeploy; (2) verify the invariant in **prod**.
**Severity:** Billing page + any `/api/billing/*` call was broken on **dev** for every user
**Scope:** dev environment config only — **not** a code bug, **not** related to the Lago drop

> **Verification (2026-07-28):** after the env fix, `GET https://dev-public.biomate.ai/api/billing/quota`
> with a fixture Bearer → `200 {"used_usd":5.224686,"quota_usd":null,"over_quota":false}`;
> `/api/billing/usage` → `200` with the full internal breakdown (llm $3.98 / 906 calls, compute
> $1.25 / 148 jobs) — all from the internal ledger, Lago-free.

---

## Symptom

Every `/api/billing/*` request on dev returns:

```
HTTP 401  {"detail":"Invalid token: Signature verification failed"}
```

The billing page (`client/src/pages/billing.tsx`) turns this into a **"Not authenticated"**
error in the Usage panel. (The page isn't currently routed — `/billing` is commented out in
`App.tsx` — but the moment it's enabled, it will fail.)

## How the auth actually flows

1. Node signs the user's session JWT with `JWT_SECRET` (`server/auth-service.ts:18`).
2. The Node billing proxy (`server/routes.ts:14011`) **re-signs** a fresh Galaxy JWT and forwards it:
   ```js
   const _GALAXY_JWT_SECRET = process.env.GALAXY_JWT_SECRET || process.env.JWT_SECRET || 'dev-only…';
   const galaxyToken = jwt.sign({ user_id, email }, _GALAXY_JWT_SECRET, { expiresIn: '1h' });
   ```
3. Galaxy validates it with **its** `JWT_SECRET`, HS256, expecting a `user_id` claim
   (`billing_router.py:106,169`).

`"Signature verification failed"` is specifically a **secret/algorithm** mismatch (algorithm and
claim are correct here), so the signing secret the proxy uses ≠ Galaxy's `JWT_SECRET`.

## Root cause (measured on dev, read-only)

Secret checksums across the two containers (`cksum` — equal cksum ⇒ equal value):

| Secret | Container | cksum | bytes |
|---|---|---|---|
| `JWT_SECRET` | `biomate-galaxy-dev` | `2510801473` | 64 |
| `JWT_SECRET` | `biomate-dev-frontend` | `2510801473` | 64 | ← **already identical to Galaxy** |
| `GALAXY_JWT_SECRET` | `biomate-dev-frontend` | `250748822` | 44 | ← **different (stale/wrong)** |

The proxy signs with `GALAXY_JWT_SECRET || JWT_SECRET`. Because `GALAXY_JWT_SECRET` **is set** (to a
wrong 44-byte value), the proxy uses it instead of the `JWT_SECRET` that **already matches** Galaxy
→ Galaxy rejects the signature.

**Positive confirmation:** minting a token with the shared `JWT_SECRET` and calling Galaxy's billing
endpoint directly (inside the container, bind `0.0.0.0:8080`) returns **HTTP 200**:

```
{"user_id":"1","quota_usd":null,"used_usd":0.002995,"quota_pct":null,"over_quota":false}
```

So the endpoint and the (Lago-free) quota/usage logic are fine — only the proxy's signing secret is wrong.

## The invariant being violated

`GALAXY_JWT_SECRET` (on the Node frontend) **must equal** `JWT_SECRET` on the Galaxy backend — it
exists only to bridge environments where Node's and Galaxy's `JWT_SECRET` differ. On dev they do
**not** differ (both 64-byte, cksum `2510801473`), so a *separate* `GALAXY_JWT_SECRET` is both
redundant and, as set, wrong.

## Fix (ops / env — cannot be applied via `sync_to_dev.sh`)

`GALAXY_JWT_SECRET` is set on the instance from the external secret source (referenced in
`scripts/setup_github_env.sh:66`), not from a synced repo file. Pick one:

- **Simplest — unset it** on `biomate-dev-frontend` (the fallback to the already-matching
  `JWT_SECRET` then works), **and** remove the stale `GALAXY_JWT_SECRET` from the dev GitHub
  env/secret so it doesn't come back on redeploy.
- **Or set it correctly** — `GALAXY_JWT_SECRET` = Galaxy's `JWT_SECRET` (the 64-byte value).

After the env change, restart/redeploy the frontend container and verify:

```
GET https://dev-public.biomate.ai/api/billing/quota   (with a fixture Bearer/cookie)
→ 200 {"quota_usd":…, "used_usd":…}   # not 401
```

**Not doing a code change:** the proxy code is correct; the env is misconfigured. Changing the
`GALAXY_JWT_SECRET || JWT_SECRET` precedence could break prod if prod legitimately runs different
Node/Galaxy secrets. The durable fix is to correct the env/secret so the invariant holds.

## Prod check (do before enabling the billing UI)

Verify the same invariant in **prod**: `GALAXY_JWT_SECRET` (frontend) == `JWT_SECRET` (galaxy). If
prod has the same stale override, the billing page will 401 there too once routed.
