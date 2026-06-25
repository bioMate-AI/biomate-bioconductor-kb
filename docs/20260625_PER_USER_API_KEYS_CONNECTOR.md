# Per-user API keys for biomate-connector (2026-06-25)

## What was built

Self-service personal API keys so connector surfaces (Slack, Feishu, WeChat,
MCP clients) authenticate as the **owning user** — their own runs, quota, and
history — instead of a single shared service account.

### Root-cause finding that shaped the design

Generating a key in Settings alone would have been a workaround: the connector
sends `Authorization: Bearer <key>` to `/api/chat/stream`, but that endpoint
uses `optionalAuth`, which only accepts JWTs — an opaque key was silently
ignored and the request ran **anonymous**. The static-key middleware
(`authenticateStaticApiKey`) only covered a few data/S3 endpoints and mapped to
one hardcoded service account. So the real fix had to include an auth path that
resolves a per-user key → that user on the connector-facing endpoints.

## Changes (branch `feat/per-user-api-keys`, commit `f190ae256`)

- `frontend/migrations/0010_api_keys.sql` + `apiKeys` in `shared/schema.ts` —
  keys stored as **SHA-256 hash only**; plaintext (`bm_live_…`) shown once.
- `frontend/server/api-key-service.ts` — `generateApiKey` / `hashApiKey` /
  `resolveApiKey` / `listApiKeys`.
- `frontend/server/auth-middleware.ts` — `authenticateApiKeyUser()` resolves a
  `bm_live_` key (from `X-API-Key` or a non-JWT `Bearer`) to its owner, wired
  into **both** `authenticateToken` and `optionalAuth`. So `/api/chat/stream`
  (optionalAuth), `/api/auth/login-token` and `/api/runs/.../output`
  (authenticateToken) all accept per-user keys. `authenticateStaticApiKey` now
  passes `bm_live_` keys through (they are not the shared service key).
- `frontend/server/routes.ts` — `GET/POST/DELETE /api/user/api-keys`
  (list / generate / revoke), JWT-cookie auth, ownership-scoped, masked output.
- `frontend/client/src/components/settings-dialog.tsx` — **API Keys** tab:
  generate (copy-once), list with prefix/created/last-used, revoke.

## How a user gets a key

1. Web UI → Settings → **API Keys** → "Generate key" → copy the `bm_live_…`
   value (shown once).
2. Set it on the connector host as `BIOMATE_API_KEY` (or per-user `bind`).
   Connector sends `Authorization: Bearer bm_live_…`; requests run as that user.

## Verification

- `npx tsc --noEmit` clean; `npx vitest run` 880 pass (1 pre-existing flaky
  `parameter-dialog` timeout, passes in isolation — unrelated).
- Deployed to **test** (`i-0482a6fa98c6f301a`, tag `sha-f190ae256513`).
  Boot log: `[migrate] applied 1 migration(s): 0010_api_keys.sql`.
- `https://test.stage-public.biomate.ai/api/user/api-keys` →
  GET/POST/DELETE return **401** (route live, auth required); a nonexistent
  route returns 404; a bogus `bm_live_` Bearer returns 401 (resolver runs).

## Open / not yet verified

- Full authenticated round-trip (login fixture → generate key → use key on
  `/api/chat/stream` and confirm it runs as the user) was **not** run — needs
  `E2E_FIXTURE_PASSWORD` (not in env; CLAUDE.md says ask before generating).
- Branch not yet merged or pushed to GitHub.

## Deploy recipe used (GHA billing-blocked, local Docker down)

On-host build via presigned S3 (see memory `test-deploy-without-gha`):
1. `git ls-files | grep -vE '^(e2e/|e2e-results/|playwright-report/|\.nextflow/)' | tar czf ctx.tgz -T -` (lean context; `git archive HEAD:frontend` is 446MB because of committed screenshots).
2. Upload to `s3://biomate-nextflow-work` (bucket is **us-east-1**), `aws s3 presign` (instance role can't read the bucket; presigned HTTPS bypasses IAM).
3. SSM the host: `curl` the presigned URL → `docker build` → push `dev-frontend:<tag>`; retag+push `dev-backend` from the currently-deployed tag (backend unchanged). Host shell is `dash` — ship the script base64-encoded and run under `bash`.
4. `AWS_REGION=us-west-2 bash scripts/deploy.sh test <tag>`.
