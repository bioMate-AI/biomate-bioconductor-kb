# BioMate — MFA Implementation Plan

**Date:** 2026-04-27
**Status:** Planning
**Priority:** High (SOC2 CC6.2 / HIPAA §164.312(d))
**Closes gap:** #1 from `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`

---

## Related: AWS Bedrock closes Anthropic BAA gap

Before MFA: one open security gap can be closed with a config change.

**Gap #2 — No BAA with Anthropic:** Route Claude API calls through **AWS Bedrock** instead of the direct Anthropic API. AWS has an existing BAA covering all Bedrock services (including Claude models). This makes BioMate HIPAA-eligible for PHI workloads without needing a separate Anthropic BAA.

How to switch:
- Replace `import Anthropic from '@anthropic-ai/sdk'` with `import AnthropicBedrock from '@anthropic-ai/bedrock-sdk'`
- Model IDs change format: e.g., `claude-sonnet-4-6` → `anthropic.claude-sonnet-4-5-20251001-v1:0` (check Bedrock console for current model IDs)
- Auth: SDK reads `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` — same credentials already used for Batch/S3
- No other code changes needed; request/response API is identical

This is a one-afternoon task and closes a High-severity gap immediately.

---

## MFA Overview

### Why TOTP (not SMS, not email OTP)

| Method | Cost | Phishing-resistant | No 3rd-party dependency | Audit-friendly |
|---|---|---|---|---|
| **TOTP (Google Authenticator / Authy)** | Free | ✅ | ✅ | ✅ |
| SMS | ~$0.01/msg, Twilio dependency | ❌ SIM-swap risk | ❌ | ✅ |
| Email OTP | Free | ❌ | ❌ (email delivery) | ✅ |
| AWS Cognito | Managed, adds cost + complexity | ✅ | ❌ (Cognito dependency) | ✅ |

**Recommendation: TOTP via `speakeasy` + `qrcode` npm packages.** Standard, free, works with every authenticator app, no SIM-swap or email delivery risk.

---

## Current Auth State

- File: `frontend/server/auth-service.ts`
- Schema: `frontend/shared/schema.ts` (`users` table)
- Login flow: `POST /api/auth/login` → bcrypt verify → JWT issued → `httpOnly` cookie set
- No MFA fields in `users` table today

---

## Phase 1 — Database Changes

### New columns on `users` table

```ts
// In frontend/shared/schema.ts, add to the users pgTable:
mfaSecret: text("mfa_secret"),                          // TOTP secret (base32, encrypted at rest)
mfaEnabled: boolean("mfa_enabled").default(false),      // Whether MFA is active for this user
mfaVerifiedAt: timestamp("mfa_verified_at"),            // When MFA setup was completed
mfaRecoveryCodes: text("mfa_recovery_codes"),           // JSON array of bcrypt-hashed recovery codes
```

### Drizzle migration

Create `frontend/server/migrations/0007_add_mfa.sql`:

```sql
ALTER TABLE users
  ADD COLUMN mfa_secret TEXT,
  ADD COLUMN mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN mfa_verified_at TIMESTAMPTZ,
  ADD COLUMN mfa_recovery_codes TEXT;
```

The `mfa_secret` column should be encrypted at the application layer using `MFA_ENCRYPTION_SECRET` env var (AES-256-GCM), the same pattern recommended for `galaxy_api_key`.

---

## Phase 2 — Backend: MFA Setup Flow

### 2.1 New endpoints (add to `frontend/server/routes.ts`)

```
POST /api/auth/mfa/setup         → generate TOTP secret, return QR code + manual entry key
POST /api/auth/mfa/verify-setup  → verify first TOTP code, activate MFA, return recovery codes
POST /api/auth/mfa/disable       → disable MFA (requires password + TOTP confirmation)
GET  /api/auth/mfa/status        → { enabled: boolean, verifiedAt: string | null }
```

### 2.2 `/api/auth/mfa/setup`

```ts
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';

// POST /api/auth/mfa/setup  (requires authenticated user)
const secret = speakeasy.generateSecret({
  name: `BioMate (${user.email})`,
  issuer: 'BioMate',
  length: 20,
});

// Store encrypted secret temporarily (not yet activated — user must verify first)
await db.update(users)
  .set({ mfaSecret: encrypt(secret.base32) })
  .where(eq(users.id, userId));

const qrCodeDataUrl = await QRCode.toDataURL(secret.otpauth_url!);

return { qrCode: qrCodeDataUrl, manualKey: secret.base32 };
```

### 2.3 `/api/auth/mfa/verify-setup`

```ts
// POST /api/auth/mfa/verify-setup  body: { token: string }
const user = await db.query.users.findFirst({ where: eq(users.id, userId) });
const secret = decrypt(user.mfaSecret);

const verified = speakeasy.totp.verify({
  secret,
  encoding: 'base32',
  token: body.token,
  window: 1,  // allow 30s clock drift
});

if (!verified) return res.status(400).json({ error: 'Invalid code' });

// Generate 8 recovery codes
const plainCodes = Array.from({ length: 8 }, () =>
  crypto.randomBytes(5).toString('hex').toUpperCase().match(/.{1,5}/g)!.join('-')
);
const hashedCodes = await Promise.all(plainCodes.map(c => bcrypt.hash(c, 10)));

await db.update(users).set({
  mfaEnabled: true,
  mfaVerifiedAt: new Date(),
  mfaRecoveryCodes: JSON.stringify(hashedCodes),
}).where(eq(users.id, userId));

// Return plaintext codes ONCE — never stored in plaintext
return { recoveryCodes: plainCodes };
```

### 2.4 Modified login flow (`authService.login`)

Current flow: password verify → JWT issued.

New flow:

```
1. Verify password (bcrypt) — same as today
2. If user.mfaEnabled === false → issue JWT immediately (same as today)
3. If user.mfaEnabled === true  → issue a short-lived MFA challenge token (5 min, not a full session JWT)
                                    → return HTTP 202 + { mfaRequired: true, challengeToken: <short-lived JWT> }
4. Client shows TOTP input screen
5. POST /api/auth/mfa/challenge  body: { token: string, challengeToken: string }
6. Verify TOTP (or recovery code)
7. If valid → issue full session JWT (same as step 2 above)
```

```ts
// POST /api/auth/mfa/challenge
const challengePayload = jwt.verify(body.challengeToken, _JWT_SECRET) as { userId: string, type: 'mfa_challenge' };
if (challengePayload.type !== 'mfa_challenge') return res.status(401).json({ error: 'Invalid challenge' });

const user = await db.query.users.findFirst({ where: eq(users.id, challengePayload.userId) });
const secret = decrypt(user.mfaSecret);

// Try TOTP first
let valid = speakeasy.totp.verify({ secret, encoding: 'base32', token: body.token, window: 1 });

// Try recovery codes if TOTP fails
if (!valid) {
  const codes = JSON.parse(user.mfaRecoveryCodes ?? '[]') as string[];
  for (let i = 0; i < codes.length; i++) {
    if (await bcrypt.compare(body.token.replace(/-/g, '').toUpperCase(), codes[i])) {
      valid = true;
      // Burn the used recovery code
      codes.splice(i, 1);
      await db.update(users).set({ mfaRecoveryCodes: JSON.stringify(codes) }).where(eq(users.id, user.id));
      break;
    }
  }
}

if (!valid) {
  await auditLog({ event: 'mfa_failure', userId: user.id, ip: req.ip });
  return res.status(401).json({ error: 'Invalid MFA code' });
}

await auditLog({ event: 'mfa_success', userId: user.id, ip: req.ip });
// Issue full JWT — same as existing authService.generateToken()
```

---

## Phase 3 — Frontend: Setup & Login UI

### 3.1 MFA Setup (in `SettingsDialog` or new `/settings/security` page)

1. **"Enable two-factor authentication"** toggle in Settings → Security tab
2. On enable: `POST /api/auth/mfa/setup` → render QR code + manual key
3. Text field for user to enter the code from their authenticator app
4. On submit: `POST /api/auth/mfa/verify-setup`
5. Show recovery codes in a modal with copy + download button — **prominently warn these are shown once**
6. MFA status badge in Settings shows "Enabled (since [date])" or "Not enabled"

### 3.2 MFA Challenge during Login

When server returns `{ mfaRequired: true, challengeToken }`:
1. Keep the login page visible; show a new step: "Enter the 6-digit code from your authenticator app"
2. Numeric input (6 digits), auto-submit on 6th digit
3. "Use a recovery code instead" link → text input that accepts `XXXXX-XXXXX` format
4. `POST /api/auth/mfa/challenge` → on success, proceed to platform (same redirect as today)
5. On failure: show error, increment attempt counter (lock after 5 failures — same as existing auth_failure audit log pattern)

### 3.3 New page component

`frontend/client/src/pages/auth/mfa-challenge.tsx` — renders the TOTP entry step, receives `challengeToken` via router state or query param.

---

## Phase 4 — Enforcement Policy

### Graduated rollout

| User tier | MFA enforcement |
|---|---|
| Anonymous / free trial | Optional |
| Standard paid | Optional (prompted but not required) |
| **Enterprise / HIPAA** | **Mandatory — login blocked until MFA enabled** |
| Admin accounts | **Always mandatory** |

Admin enforcement at login: if `user.isAdmin && !user.mfaEnabled` → redirect to `/settings/security` with banner "Admin accounts require MFA. Set it up to continue."

### Enforcement middleware

```ts
// In authenticateToken middleware (routes.ts), after JWT verify:
if (req.user.isAdmin && !req.user.mfaEnabled) {
  return res.status(403).json({
    error: 'MFA required for admin accounts',
    setupUrl: '/settings/security'
  });
}
```

---

## Phase 5 — Audit Logging

All MFA events write to `audit_logs`:

| Event | Trigger |
|---|---|
| `mfa_enabled` | User completes MFA setup |
| `mfa_disabled` | User disables MFA |
| `mfa_challenge_success` | Successful TOTP or recovery code |
| `mfa_challenge_failure` | Invalid code (count repeated failures) |
| `mfa_recovery_code_used` | Recovery code consumed |
| `mfa_lockout` | 5 consecutive failures → account temporarily locked |

---

## Dependencies to Install

```bash
npm install speakeasy qrcode
npm install --save-dev @types/speakeasy @types/qrcode
```

Both are MIT-licensed, zero external network calls (TOTP is purely local crypto).

---

## Implementation Checklist

### Database
- [ ] Add 4 MFA columns to `users` schema (`schema.ts`)
- [ ] Write Drizzle migration `0007_add_mfa.sql`
- [ ] Add `MFA_ENCRYPTION_SECRET` to `.env.production` and EC2 instance

### Backend
- [ ] Add `encrypt()`/`decrypt()` helpers for MFA secret (AES-256-GCM)
- [ ] `POST /api/auth/mfa/setup` — generate + temporarily store TOTP secret
- [ ] `POST /api/auth/mfa/verify-setup` — activate MFA + return recovery codes
- [ ] `POST /api/auth/mfa/disable` — disable MFA (requires re-auth)
- [ ] `GET /api/auth/mfa/status` — return enabled state
- [ ] Modify `authService.login()` — issue challenge token if MFA enabled
- [ ] `POST /api/auth/mfa/challenge` — verify TOTP or recovery code, issue session JWT
- [ ] Enforce MFA for admin accounts in `authenticateToken` middleware
- [ ] Audit log all MFA events

### Frontend
- [ ] MFA setup UI in Settings → Security tab (QR code + verify step + recovery codes modal)
- [ ] `mfa-challenge.tsx` login step (TOTP input + recovery code fallback)
- [ ] Login flow: handle `{ mfaRequired: true }` response → show challenge step
- [ ] Recovery codes: one-time display with copy + download, clear warning

### Testing
- [ ] Unit tests: TOTP verify, recovery code burn, challenge token expiry
- [ ] E2E test: full login-with-MFA flow (setup → login → challenge → session)
- [ ] E2E test: recovery code use + burnout
- [ ] E2E test: admin blocked until MFA enabled

---

## Estimated Effort

| Phase | Effort |
|---|---|
| DB migration | 1 hour |
| Backend endpoints + login flow modification | 1.5 days |
| Frontend UI (setup + login challenge) | 1 day |
| Tests | 0.5 day |
| **Total** | **~3 days** |

---

## Environment Variables Required

```bash
MFA_ENCRYPTION_SECRET=<64-byte random hex>   # For encrypting TOTP secrets at rest
```

Generate with: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`

---

*Document owner: Engineering / Security*
*Next review: before enterprise customer onboarding*
