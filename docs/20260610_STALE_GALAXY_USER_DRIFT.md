# Stale Galaxy-user drift — the 401 / "Workflow generation failed" pattern

**Date:** 2026-06-10
**Symptom:** chat-stream returns `"error":"Request failed with status code 401"` for an authenticated BioMate user; Galaxy access log shows `POST /api/ai_assistant/generate_workflow HTTP/1.1 401`.
**Root cause:** the BioMate `users` row points at a Galaxy `galaxyUserId` that no longer exists in Galaxy's user table. The stored `galaxyApiKey` was generated for the missing user, so when the Node proxy threads it into `X-API-Key` for AI-assistant calls Galaxy rejects with 401.

## How it happens

BioMate registration calls Galaxy's `provisionGalaxyUser` which creates the user and persists `(galaxyUserId, galaxyApiKey, galaxyUsername)` in BioMate's Postgres `users` table. The Galaxy user/key live in Galaxy's `universe.sqlite`.

Drift events that decouple the two:

- `scripts/sync_to_dev.sh` swaps Galaxy's `universe.sqlite` from the local repo, wiping Galaxy-side users while BioMate's PG rows stay intact.
- An admin manually deletes a Galaxy user but the BioMate row is left behind.
- A failed re-registration leaves the old row pointing at a now-stale id.

After drift, BioMate's stored `galaxyUserId` points at nothing in Galaxy. Calls that resolve the user by api-key 401; calls that don't (e.g. `/api/version`, `/api/histories` with master key) keep working — making the bug look intermittent and route-specific.

## Diagnosis from this session

Concrete state observed:

| Layer | Value | Notes |
|---|---|---|
| BioMate `users.galaxyUserId` (fixture `lifeifei163361@163.com`) | `534` | Stale |
| BioMate `users.galaxyApiKey` | encrypted blob (86 chars, 2 colons) | Decrypts cleanly |
| Galaxy `/api/users?f_email=lifeifei163361@163.com` | `{id: "b72aa5f4aecd8d13"}` (decoded `530`) | Real current user |
| Direct curl `GET /api/whoami` with master key | 500 | Doesn't trigger old 401-only guard |
| Direct curl `POST /api/ai_assistant/generate_workflow` with stored user key | 401 | The actual user-facing failure |

After `DELETE FROM users WHERE email = 'lifeifei163361@163.com'` + re-registration the BioMate row got freshly provisioned (`galaxyUserId: 530`) and the chat-stream returned `"state":"workflow_ready"` with a full `workflow_ga` in ~51 s.

## Guard hardening shipped today

`frontend/server/auth-service.ts` (login flow) previously probed `/api/whoami` and only treated `401` or no-response as stale. **That guard missed drift cases** because `/api/whoami` silently 500s when the api-key authenticates to a missing user.

The new guard probes `/api/users/current` and treats the key as stale if **any** of:

1. No response (network / timeout).
2. Any non-2xx HTTP status.
3. Galaxy returns a different `id` than `users.galaxyUserId`.
4. Galaxy returns a different `email` than `users.email` (case-insensitive).

In any of those cases, the user row's Galaxy fields are cleared and `provisionGalaxyUser` runs synchronously **before the login JWT is issued**, so the JWT is immediately usable for `/api/ai_assistant/*`.

This is in `frontend/server/auth-service.ts` around line ~411.

## Operational notes

- **Every login** is now an implicit health check. If a teammate runs `sync_to_dev.sh` to refresh `universe.sqlite`, the first time each user logs in their Galaxy account auto-re-provisions. No manual `DELETE FROM users` needed.
- The probe is `GET /api/users/current` with a 5 s timeout. If Galaxy is fully down, the guard treats the key as stale and re-provisions — which will also fail. Login still succeeds (the catch wraps the whole block); the user just gets a non-functional Galaxy session until Galaxy recovers. That is the same failure mode the system already had, not a regression.
- The guard runs only when `user.galaxyApiKey` is already set. New users still flow through the registration provisioning path unchanged.

## What to add if this recurs

If a future drift case sneaks past the new guard (e.g. Galaxy returns 200 with the wrong user shape), wire one more check:

```ts
const probeWorkflowEndpoint = await fetch(`${galaxyUrl}/api/ai_assistant/health`, ...);
```

`/api/ai_assistant/health` would be a tiny new Galaxy endpoint that returns the resolved user id from `trans.user` — and 401 if `trans.user` is None. That is the most precise positive signal that the key works for the call paths the chat orchestrator actually uses.
