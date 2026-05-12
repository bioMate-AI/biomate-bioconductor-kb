# BioMate Email Aliases — Setup Guide (2026-05-12)

Single source of truth for every customer-facing email channel BioMate uses or references. Hand this to whoever does email/DNS admin.

## Current state

- **Outbound (sending)**: AWS SES, us-west-2 region. Domain `biomate.ai` is verified. **SES is still in sandbox mode** — production access has not been requested. In sandbox, BioMate can only send TO addresses already verified in SES (currently the `biomate.ai` domain + your `xiaoni5122@gmail.com`).
- **Inbound (receiving)**: **No inbound email is currently configured.** Mail sent to `support@biomate.ai`, `contact@biomate.ai`, etc. is going nowhere.
- **Code state**: `frontend/server/email-service.ts` is configured and ready. `ADMIN_EMAIL` constant is hardcoded to `yaoyun.zhang@biomate.ai`. `/api/contact` endpoint now exists (added 2026-05-12) and sends to `process.env.CONTACT_INBOX || 'yaoyun.zhang@biomate.ai'` via SES.

## All aliases referenced in the codebase

These are addresses that appear in code, scripts, regulatory templates, audit policies, or sample data. **Every one of them should resolve to `yaoyun.zhang@biomate.ai` (or whoever you designate as the team inbox)** — at minimum until BioMate has a real support team.

| Alias | Purpose / Where used | Priority |
|---|---|---|
| `yaoyun.zhang@biomate.ai` | Founder / primary inbox | **PRIMARY — must exist** |
| `noreply@biomate.ai` | Outbound transactional FROM address (account activation, password reset) | **MUST configure as sender in SES** |
| `support@biomate.ai` | Customer support; referenced in error messages, docs | High |
| `contact@biomate.ai` | Sales / general inquiries; referenced on website | High |
| `security@biomate.ai` | Security disclosures (security.txt, vulnerability reports) | High (compliance) |
| `privacy@biomate.ai` | Privacy / GDPR / data subject requests | High (compliance) |
| `legal@biomate.ai` | Legal correspondence | Medium |
| `compliance@biomate.ai` | 21 CFR Part 11 / SOC2 / regulatory | Medium |
| `ciso@biomate.ai` | Chief security officer (placeholder; routes to founder until hired) | Medium |
| `incident@biomate.ai` | Incident response (PagerDuty / on-call) | Medium |
| `admin@biomate.ai` | Generic admin | Low (consolidate) |
| `ops@biomate.ai` | DevOps / infra | Low (consolidate) |
| `comms@biomate.ai` | Press / communications | Low (consolidate) |
| `dev@biomate.ai` | Engineering team | Low (consolidate) |
| `dba@biomate.ai` | Database admin | Low (consolidate) |
| `dr@biomate.ai` | Disaster recovery | Low (consolidate) |
| `cloud@biomate.ai` | AWS / cloud ops | Low (consolidate) |
| `researcher@biomate.ai` | Research team | Low (consolidate) |
| `security-team@biomate.ai` | Security team (duplicate of `security@`) | Low (consolidate) |

For a one-person team, **set all of these to forward to `yaoyun.zhang@biomate.ai`** until you have specialized people. When you hire (security, support, etc.), reroute the specific alias to that person without changing any code.

---

## Recommended setup: Cloudflare Email Routing + AWS SES (free, 30 min)

This is the cheapest, fastest, and most flexible setup for a startup.

### Step 1 — Cloudflare Email Routing (inbound, free)

If biomate.ai is on Cloudflare DNS (likely; check `cloudflare.com` dashboard):

1. Cloudflare dashboard → biomate.ai → **Email → Email Routing**.
2. Click **Get started**. Cloudflare will check existing MX records and warn if it would override them.
3. Add **Destination address**: your personal gmail (e.g., `xiaoni5122@gmail.com`). Verify via the email Cloudflare sends.
4. **Create routing rules**:
   - For each alias above, create a rule: `support@biomate.ai → xiaoni5122@gmail.com`
   - OR (faster): create a single **catch-all** rule: `*@biomate.ai → xiaoni5122@gmail.com`. This forwards every alias automatically.
5. Cloudflare will prompt you to add MX records — **click "Add and enable"**. It auto-configures the DNS.
6. Done. Test by sending a message from any external account to `support@biomate.ai`. It should land in your gmail within seconds.

**Cost**: $0/month. Unlimited aliases. Unlimited forwarding volume.

**Limitation**: Cloudflare Email Routing is forward-only. You can't reply *from* `support@biomate.ai` through Cloudflare. That's what AWS SES handles (Step 2).

### Step 2 — Request AWS SES production access (outbound, free)

Currently in sandbox, which limits sending to verified addresses only (200/day max). For real customer outbound (replying to leads, sending contact-form confirmations, password resets), you need production access.

1. AWS console → SES → **Account dashboard** → "Request production access".
2. Fill the form:
   - Mail type: **Transactional**
   - Website: `https://biomate.ai`
   - Use case: "Customer support replies, account verification, transactional notifications for a B2B drug-development AI platform."
   - Compliance: confirm you will honor bounces/complaints
3. AWS approves in 24–48 hours (sometimes faster).
4. Once approved: SES can send to any address, up to 50K/day initially (auto-scales up).

**Cost**: $0.10 per 1,000 emails. For a B2B platform doing maybe 1,000 emails/month, this is ~$0.10/month. Free tier for first 62K/month when sending from EC2.

### Step 3 — Configure SMTP credentials in production env

The BioMate frontend reads SMTP from env vars (`EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USER`, `EMAIL_PASS`, `EMAIL_FROM`). To use SES via SMTP:

1. AWS console → SES → **SMTP Settings** → "Create SMTP credentials". This creates an IAM user and gives you the SMTP username + password.
2. Set these env vars on your production host (EC2, ECS, Vercel, etc.):
   ```
   EMAIL_HOST=email-smtp.us-west-2.amazonaws.com
   EMAIL_PORT=587
   EMAIL_USER=<the SMTP username AWS generated>
   EMAIL_PASS=<the SMTP password AWS generated>
   EMAIL_FROM=noreply@biomate.ai
   CONTACT_INBOX=yaoyun.zhang@biomate.ai
   APP_URL=https://biomate.ai
   ```
3. Restart the frontend Node process. The `[EmailService] Email transporter initialized` log message should appear.

### Step 4 — Verify `noreply@biomate.ai` as a sender in SES

In sandbox or production, every FROM address must be verified.

1. SES → **Verified identities** → "Create identity".
2. Identity type: **Email address**. Email: `noreply@biomate.ai`.
3. SES sends a verification email to `noreply@biomate.ai`. Since Cloudflare forwards `*@biomate.ai` to your gmail, the verification email lands in your gmail. Click the link.
4. Done. `noreply@biomate.ai` is now an allowed sender.

(Optional but recommended) verify the entire `biomate.ai` domain via DKIM. This is already done — the domain is verified. You just need to verify the specific local-part you want to send from.

### Step 5 — (Optional) Gmail "Send as" — reply from biomate.ai through gmail

If you want to reply to customer emails and have them see `support@biomate.ai` (not your gmail), set up Gmail's "Send mail as" feature:

1. Gmail → Settings → Accounts and Import → **Send mail as** → Add another email address.
2. Email: `support@biomate.ai`. Name: BioMate Support.
3. SMTP Server: `email-smtp.us-west-2.amazonaws.com`, Port `587`, Username/Password: the SMTP credentials from Step 3 above.
4. Verify. Gmail sends a code to `support@biomate.ai` → forwarded to your gmail → enter the code.
5. Done. When composing a new email in gmail, you can pick `support@biomate.ai` as the From address.

Repeat for each alias you want to reply from.

---

## Alternative: Zoho Mail free tier (one-tool setup)

If you don't want to split inbound/outbound across two services:

1. Sign up at [zoho.com/mail](https://www.zoho.com/mail/) — pick "Free Plan" (5 users, custom domain).
2. Add `biomate.ai` as your domain. Zoho gives you DNS records (MX, SPF, DKIM) to add.
3. Add them in Cloudflare DNS (or wherever biomate.ai DNS lives).
4. Create the primary mailbox: `yaoyun.zhang@biomate.ai`.
5. Add aliases for the rest (Zoho allows multiple aliases per mailbox on free tier).
6. Use Zoho's web/mobile clients to read and reply.

**Cost**: $0/month for up to 5 mailboxes. 5GB per user. No IMAP/POP on free tier (web/mobile only).

**Tradeoff**: Less integration with gmail. Two inboxes to check (personal gmail + zoho).

---

## What's NOT free / why this won't last forever

- **Google Workspace** for biomate.ai: ~$6/user/month minimum. Worth it once you hire #1.
- **Microsoft 365 Business Basic**: ~$6/user/month. Similar to Workspace.
- **AWS SES Production at scale**: free tier is generous (62K/month from EC2) but production access has compliance requirements (bounce/complaint handling). Out of scope for now.

For a 1-person founder team, Cloudflare + SES (free) is correct. Migrate to Workspace when you have 2+ people.

---

## Action items (for you, not me)

| # | Action | Who | When |
|---|---|---|---|
| 1 | Confirm DNS provider for `biomate.ai` (Cloudflare or other) | Founder | Today |
| 2 | Set up Cloudflare Email Routing with catch-all → gmail | Founder | Today (30 min) |
| 3 | Request AWS SES production access | Founder | This week |
| 4 | Verify `noreply@biomate.ai` as sender in SES | Founder | After Step 2 (need inbox to receive verification) |
| 5 | Set SMTP env vars on production host | DevOps | When deploying contact form |
| 6 | Test `/api/contact` endpoint with curl + verify gmail receipt | QA | After Steps 2-5 |

---

## Code changes shipped (2026-05-12)

- `/api/contact` POST endpoint added at `frontend/server/routes.ts:1230`. Reads `CONTACT_INBOX` env var (defaults to `yaoyun.zhang@biomate.ai`), uses existing `emailService` to send via SES SMTP. Falls back to logging if SMTP not configured.
- `email-service.ts` default FROM unchanged at `noreply@biomate.dev` (legacy) — **needs to change to `noreply@biomate.ai` once you verify that sender in SES.** Set `EMAIL_FROM=noreply@biomate.ai` in your production `.env`.

That's all the codebase work needed. Everything else is one-time email/DNS setup.
