# Email Setup: contact@biomate.ai

**Date:** 2026-04-27  
**Status:** Pending — domain is wired to Google Workspace; account not yet created.

---

## Current State

`biomate.ai` MX records already point to Google Workspace:

```
1  aspmx.l.google.com.
5  alt1.aspmx.l.google.com.
5  alt2.aspmx.l.google.com.
10 alt3.aspmx.l.google.com.
10 alt4.aspmx.l.google.com.
```

`contact@biomate.ai` does not yet exist as an account or alias.

The backend email service (`frontend/server/email-service.ts`) is currently configured with Ethereal (fake SMTP — emails are captured but never delivered):

```
EMAIL_HOST=smtp.ethereal.email
EMAIL_USER=b7hlkqltjxf7bonb@ethereal.email
EMAIL_FROM=noreply@biomate.dev
```

This means verification emails and password reset links are not being delivered to real users on dev.

---

## Creating contact@biomate.ai

### Option A — Google Group (recommended, no extra seat cost)

Groups route email to one or more real inboxes without requiring a paid Workspace seat.

1. Go to **admin.google.com** → log in as Workspace admin
2. Navigate to **Directory → Groups → Create group**
3. Set:
   - Group name: `Contact`
   - Group email: `contact@biomate.ai`
   - Access type: `Restricted` (only members can post, or allow external)
4. Add `yaoyun.zhang@biomate.ai` as a member
5. Save

All mail sent to `contact@biomate.ai` will land in `yaoyun.zhang@biomate.ai`.

### Option B — Dedicated user account (uses a Workspace seat)

1. Go to **admin.google.com → Directory → Users → Add new user**
2. First name: `BioMate`, Last name: `Contact`
3. Primary email: `contact@biomate.ai`
4. Set a password and save

Log into `contact@biomate.ai` via Gmail normally.

---

## Wiring to the Backend (after account is created)

The backend sends transactional email (verification, password reset, welcome) via SMTP.  
Update `.env` on the dev EC2 instance:

```bash
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=contact@biomate.ai
EMAIL_PASS=<Google App Password — see below>
EMAIL_FROM=contact@biomate.ai
```

### Generating a Google App Password

Google blocks plain-password SMTP for accounts with 2FA. Use an App Password instead:

1. Log in as `contact@biomate.ai` (or the account that owns it)
2. Go to **myaccount.google.com → Security → 2-Step Verification** (must be enabled)
3. Scroll to **App passwords**
4. Select app: `Mail`, device: `Other` → name it `BioMate SMTP`
5. Copy the 16-character password — use it as `EMAIL_PASS`

### Reload the backend after updating .env

```bash
# On dev EC2
kill -HUP $(pgrep -f "gunicorn.*8081" | head -1)
# Then restart the Node.js frontend service as appropriate
```

---

## Email addresses referenced across the codebase

| Address | Location | Purpose |
|---|---|---|
| `contact@biomate.ai` | `shell.js`, `about.html`, `features.html`, `pricing.html`, blog sidebars | Public contact / sales inquiries |
| `noreply@biomate.dev` | `frontend/.env` (EMAIL_FROM) | Current transactional sender (placeholder) |
| `yaoyun.zhang@biomate.ai` | `email-service.ts:594` | Hardcoded admin notification recipient |

After `contact@biomate.ai` is created, update `EMAIL_FROM` and consider replacing the hardcoded `yaoyun.zhang@biomate.ai` in `email-service.ts` with an env var (`ADMIN_EMAIL`).

---

## Open Items

- [ ] Create `contact@biomate.ai` in Google Admin (Group or User)
- [ ] Generate App Password for SMTP
- [ ] Update `.env` on dev EC2 with Gmail SMTP credentials
- [ ] Replace hardcoded `yaoyun.zhang@biomate.ai` in `email-service.ts` with `process.env.ADMIN_EMAIL`
- [ ] Test password reset email end-to-end on dev
