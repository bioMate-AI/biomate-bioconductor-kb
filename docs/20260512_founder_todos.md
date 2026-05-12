# Founder TODOs — May 12, 2026

Everything pending that requires **your action, not the codebase's**. Ordered by priority. Each item has a time estimate, the exact steps, and what blocks if you skip it.

---

## P0 — Email infrastructure (blocks customer contact)

Without these, the new `/api/contact` form on the website logs messages but doesn't actually email anyone. ~45 min total.

### ☐ 1. Confirm DNS provider for `biomate.ai` (2 min)
- Open the registrar where you bought the domain (Namecheap, GoDaddy, Cloudflare Registrar, etc.)
- Check whether the nameservers point to Cloudflare (`*.ns.cloudflare.com`) or elsewhere
- If not on Cloudflare yet: do not migrate just for this — pick a different forwarding provider in Step 2

### ☐ 2. Set up email receiving — Cloudflare Email Routing (10 min, free)

**If biomate.ai is on Cloudflare:**
- Cloudflare dashboard → biomate.ai → **Email → Email Routing** → Get started
- Add destination: `xiaoni5122@gmail.com` (your gmail). Click verify, click link in gmail
- Create **Catch-all rule**: `*@biomate.ai` → forward to `xiaoni5122@gmail.com`
- Cloudflare prompts to add MX records → click **Add and enable**
- Test: from any external email, send to `support@biomate.ai`. Should land in your gmail within 60 seconds.

**If biomate.ai is NOT on Cloudflare:**
- Sign up for [ImprovMX](https://improvmx.com) (free tier: 25 aliases) OR migrate DNS to Cloudflare
- Add MX records they give you to your current DNS provider
- Add aliases or catch-all → forward to gmail

**Blocks if skipped:** Customer emails to `support@biomate.ai`, `contact@biomate.ai`, etc. go nowhere. Verification emails from AWS SES can't reach you.

### ☐ 3. Request AWS SES production access (10 min form, 24–48h approval)
- AWS console → SES → us-west-2 region → **Account dashboard** → "Request production access"
- Form answers:
  - **Mail type:** Transactional
  - **Website:** `https://biomate.ai`
  - **Use case:** "Customer support replies, account verification, contact form submissions, and transactional notifications for a B2B drug-development AI platform."
  - **Process for handling bounces/complaints:** "AWS SES suppression list is enabled. We monitor the SES sending reputation dashboard."
  - **Process for unsubscribes:** "All marketing email is opt-in. Transactional emails (account, billing, security) per CAN-SPAM exempt categories."
- Submit. AWS usually approves in 24–48h.

**Blocks if skipped:** SES stays in sandbox. Can only email addresses already verified in SES. Real customers (anyone outside `*@biomate.ai`) will not receive your replies.

### ☐ 4. Verify `noreply@biomate.ai` as SES sender (5 min, after Step 2)
- SES → **Verified identities** → Create identity → Email address → `noreply@biomate.ai`
- SES sends verification email → forwarded via Cloudflare to your gmail → click the link
- Confirm "verified" status in SES console

**Blocks if skipped:** Outbound emails from `noreply@biomate.ai` will fail. Account activation, password reset, contact form replies — all silently fail.

### ☐ 5. Generate SES SMTP credentials + set production env vars (10 min)
- SES → **SMTP Settings** → "Create SMTP credentials" → save the username + password (only shown once)
- On your production host (wherever the frontend runs — EC2, ECS, Render, Vercel, etc.), set:
  ```
  EMAIL_HOST=email-smtp.us-west-2.amazonaws.com
  EMAIL_PORT=587
  EMAIL_USER=<SMTP username from previous step>
  EMAIL_PASS=<SMTP password from previous step>
  EMAIL_FROM=noreply@biomate.ai
  CONTACT_INBOX=yaoyun.zhang@biomate.ai
  APP_URL=https://biomate.ai
  ```
- Restart the Node process. Look for log: `[EmailService] Email transporter initialized`

**Blocks if skipped:** Contact form falls back to logging (logged in server logs but not emailed to you).

### ☐ 6. End-to-end test the contact form (3 min, after Steps 1-5)
- From an external email (or in incognito on the website), submit the `/contact` form
- Verify a message lands in `xiaoni5122@gmail.com` within 30 seconds
- Reply to it — verify your reply goes back to the submitter

**Recovery if it fails:** Check `[CONTACT_FORM]` logs on production. Check SES dashboard → Sending statistics → look for failed sends. Most common failures: SMTP creds wrong, EMAIL_FROM not verified, SES still in sandbox.

---

## P1 — Optional but recommended (~30 min)

### ☐ 7. Gmail "Send as" for replying from biomate.ai addresses (5 min per alias)
- Gmail → Settings → Accounts → Send mail as → Add another email address
- Enter: `support@biomate.ai`, Name: "BioMate Support"
- SMTP server: `email-smtp.us-west-2.amazonaws.com`, port 587, username/password = SES SMTP creds
- Verify (code goes to support@biomate.ai → forwarded to gmail → enter code)
- Repeat for any other alias you want to reply from (`contact@`, `yaoyun.zhang@`, etc.)

**Benefit:** When you reply to customer emails, they see `support@biomate.ai` (professional) instead of your gmail address.

### ☐ 8. Update default FROM in `email-service.ts` (already in env var; verify only)
- The code at `frontend/server/email-service.ts:27` has `noreply@biomate.dev` as fallback
- This is overridden by `EMAIL_FROM=noreply@biomate.ai` in your production env (Step 5)
- No code change needed if env var is set. Code change only needed if you want to remove the legacy `.dev` fallback entirely.

### ☐ 9. Consider Google Workspace once you hire team member #2 (~$6/user/month)
- Free Cloudflare + SES is fine for 1 person
- When you have 2+ people who need to read shared inboxes (`support@`, `sales@`), Workspace's shared inbox + delegation features beat manual forwarding
- Not urgent.

---

## P2 — Marketing artifacts (5 blog posts shipped today, need promotion)

The 5 blog posts are live at `/blog`. None of this is automated; pick what fits your bandwidth.

### ☐ 10. Verify the blog renders on production (5 min)
- After next deploy, visit `https://biomate.ai/blog` and `/blog/ivonescimab-bispecific-format`
- Check that all 5 posts display correctly + the markdown renders + the "Back to all posts" link works
- If anything's broken: the issue is almost certainly that the production build didn't include the `?raw` markdown files. Check Vite config / build logs.

### ☐ 11. Share posts in relevant channels (your call)
- LinkedIn — post the Ivonescimab one first (most newsy + 2024 reference); the others on a 1-per-week cadence
- Twitter/X — same posts, condensed thread format
- Substack / personal blog — if you have one, cross-post
- Hacker News — the VERVE-102 one is most likely to land on HN (gene editing is a tech-y audience); post at 9am PT Tuesday-Thursday for best timing
- Slack/Discord biotech communities (BioBreak, BioFounders, Slack groups for cell therapy / gene therapy) — pick 1-2 you're already in

### ☐ 12. Reach out to 5–10 biotech BD / CSO contacts (your call)
- "Here's a 5-min read on [HARMONi-2 / VERVE-102 / Q4 2024 approvals] — we built a tool that would have predicted this. Open to a 20-min call?"
- The Q4 2024 validation post is the highest-credibility hook for cold outreach
- Track responses; if conversion is low, the issue is targeting not the content

---

## P3 — Operational / strategic (no fixed deadline)

### ☐ 13. E2E test the new workflows through the BioMate AI chat (your earlier ask)
- The 6 new modality workflows (atlas_expression_query, modality_triage, bispecific_format_triage, in_vivo_cart_codesign, in_vivo_base_edit_design, glp1_modality_bakeoff) are wired with routing rules
- Need to run actual chat queries against the live BioMate to verify:
  - The AI correctly routes plain-English queries to the right workflow
  - The workflow runs end-to-end without infrastructure failure
  - Outputs render in the right UI (workflow panel, findings card, etc.)
- This is the prerequisite to demo video recording — without this validation, demos that fail in customer hands burn credibility
- **I can drive this when you're ready** — just say "run E2E audit on Tier 0 workflows" and I'll execute through the local dev server

### ☐ 14. Decide demo video strategy (after E2E audit passes)
- Quick (1-2 days): screen recordings of the BioMate chat doing each Tier 0 case end-to-end. Add Claude-design-style tip overlays in post.
- Production (1-2 weeks): scripted, voiced, edited. Higher quality, slower turnaround. Better for sales.
- **My recommendation:** start with screen recordings (1-2 days, 5 videos), iterate based on what resonates. Pull the best 2 into a production version later if needed.

### ☐ 15. Request DB transfer credentials (one-time)
- The latest workflow DB snapshot is at `s3://biomate-production-backups-399683337364/db_transfers/20260512_1346/galaxy_ai_tools.db` (271 MB)
- If you're transferring work to another machine or hiring an engineer, share that path + read access on the S3 bucket
- Not urgent; can do whenever

### ☐ 16. Schedule SOC 2 / 21 CFR Part 11 conversation (medium-term)
- Pharma BD will eventually ask: are you SOC 2 Type II? Are you 21 CFR Part 11 compliant?
- SOC 2 Type II takes 3-6 months to obtain; budget ~$15-30K for the audit
- 21 CFR Part 11 is needed only when customers run regulated clinical workflows (PBPK for IND, clinical trial design output) and want to cite BioMate outputs in FDA submissions
- Worth scoping with a compliance consultant once you have 2-3 pharma pilots lined up

---

## Quick command reference

```bash
# Check the latest workflow DB on S3
aws s3 ls s3://biomate-production-backups-399683337364/db_transfers/

# Pull the latest DB snapshot to a new machine
aws s3 cp s3://biomate-production-backups-399683337364/db_transfers/20260512_1346/galaxy_ai_tools.db \
    backend/database/galaxy_ai_tools.db

# Check SES sandbox vs production status
aws sesv2 get-account --region us-west-2 | grep ProductionAccessEnabled

# List SES verified identities
aws ses list-identities --region us-west-2

# Verify contact form endpoint exists in production after deploy
curl -X POST https://biomate.ai/api/contact \
  -H "Content-Type: application/json" \
  -d '{"name":"test","email":"test@example.com","subject":"smoke test","message":"This is a smoke test of the contact form."}'
```

---

## Total time budget

- **P0 (email setup)**: ~45 min active + 24-48h waiting on AWS SES approval
- **P1**: ~30 min if you want it
- **P2**: depends on outreach cadence
- **P3**: ad hoc — E2E audit is most time-sensitive (prereq to demos)

If you can do P0 today, the contact form is fully live by Thursday. Everything else can phase in over the next 2 weeks.
