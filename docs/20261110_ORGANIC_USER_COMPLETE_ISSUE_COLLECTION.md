# Organic-user issues — complete collection + test mapping (2026-11-10)

Supersedes the 2026-11-09 pass, which only covered the last-week signups. This is
**all** genuine organic users across the full history, mined from the users table,
`chat_sessions` (conversation content), `project_episodes`, the 702 study run logs,
and the live container logs. Privacy-safe: users are pseudonymized (U-codes by
institution type/region), frictions are paraphrased from assistant responses, no
emails or verbatim user content.

## Population (dev = production instance `i-06696b0d91f4346e0`)
- **1,483 users total**, but **~1,370 are test/internal** (`biomate-test.internal`,
  `biomate-verify.dev`, `example.com`, `test.local`, QA fixtures). **~47 genuine
  organic** signups (real institutions).
- **Engagement:** ~33 organic users started ≥1 chat; **19 hit at least one friction**
  (below). ~13 **churned** (0 sessions) — incl. Harvard, Houston Methodist, UTHealth,
  Tsinghua, Zhejiang, SENAC, megarobo; two (Harvard, Houston Methodist) opened a
  session but sent 0 messages.
- **Organic runs: 133 of 700 study-logged runs; 0 failed** — so organic *run*
  reliability is good; the issues are overwhelmingly **pre-run** (connectivity,
  ingestion, routing, input friction) and **onboarding** (verification).

## Issue classes (ranked by impact)

### I1 — Workflow engine unreachable (frontend→Galaxy `ECONNREFUSED`/DNS) · HIGH · STILL LIVE
Most common friction. Seen across a verified gmail power-user, a Hong Kong
university user (repeated), two `qq.com` users, and others. User-visible text:
"Could not generate workflow — the workflow engine is temporarily unreachable
(connection refused / DNS resolution failure `biomate-galaxy-dev` unreachable)",
and for code: "run_code sandbox backend is temporarily unavailable
(ECONNREFUSED 172.19.0.2:8080)".
- **Live check:** 0 in the last 2h, but `connect ECONNREFUSED 127.0.0.1:8081`
  (Galaxy port) appeared within 6h — intermittent, still occurring.
- **Root cause:** Node frontend → Galaxy (`:8081`) transient refusal (worker
  recycle / cold path). A retry (3×) exists on 502/503/504 + `TypeError fetch
  failed` at **execution** (`routes.ts:~12552`) but the **workflow-generation** and
  **run_code** paths surface the refusal to the user instead of retrying.
- **Fix direction:** extend the same bounded retry/backoff to the generate + run_code
  calls; keep the honest "closest available option" fallback it already shows.

### I2 — `run_code` sandbox backend unreachable · HIGH · likely same root as I1
`RDIAG[ok=false,e=connect ECONNREFUSED 172.19.0.2:8080]` — the code sandbox node was
unreachable (seen for a `qq.com`/alibaba user). Same retry gap as I1 on the sandbox path.

### I3 — "No response received from the AI service" (workflow generation) · MEDIUM
A `qq.com` user: "Workflow generation failed — no response received from the AI
service … temporary initialization issue." LLM/provider init or timeout on the
generate path. Connects to the agentic-on-Gemini / provider-timeout work.

### I4 — Cloud / local file ingestion not supported · HIGH · partially addressed
A Philippines-university user (heavy, 39 msgs) hit this repeatedly with explicit
frustration: "BioMate cannot directly access your Google Drive or local files." This
is the churn driver flagged last week (lgayukil). Drive-URL normalization was added
(`remote-source-validation.ts`), but the assistant still answers "cannot access Google
Drive directly" — the capability isn't surfaced in the conversation path.
- **Fix direction:** when a user mentions Drive/Dropbox/a share link, route to the
  From-URL ingestion (normalize + fetch) instead of replying that it's impossible.

### I5 — File-upload internal server error (incl. Word/doc retrieval) · HIGH
A University of Delhi user: "file upload encountered an internal server error, so I
wasn't able to retrieve the script content" and "internal server error retrieving your
Word document." Upload or content-retrieval 500s that blocked the whole task.
- **Test:** exercise upload + read_file of .py/.docx via the real API; capture the 500.

### I6 — Hallucinated dataset accessions · MEDIUM · correctness
A Wenzhou user got a fabricated GEO ID and the assistant later retracted:
"GSE148286 doesn't exist — that was a fictional dataset ID I generated." Matches the
`research_confabulation` finding (research_query invents accessions/PMIDs).
- **Fix direction:** gate accession claims through the accession resolver / GEO
  cascade before presenting them (the accession-benchmark work).

### I7 — Backend "no such table: workflows" · MEDIUM · FIXED (retired)
A GIBH user hit "internal database error (`no such table: workflows`)" retrieving
ChIP-seq templates (2026-06). **Live check: 0 occurrences in current logs** — the
template path changed; retired. Keep a regression note.

### I8 — Run failures + poor failure diagnosis · MEDIUM · addressed, verify
A McGill user asked "why is my run failing" 3× and got the same unhelpful "the
provided literature does not contain diagnostic information" — the run-problem was
routed to the literature agent with no run/universe context. This is exactly the
"ad hoc short-circuit" issue addressed this cycle (run-diagnostics + universe context
threaded into the research payload). Humanitas and ibch.ru also hit real run errors
("Workflow hit an error", "BIOC_TFBSTOOLS… failed — 1 task failed").
- **Test:** a run-problem query must return run-grounded diagnosis (status/step/log),
  not a literature deflection.

### I9 — Email verification not completing · HIGH · SYSTEMIC · ROOT CAUSE FOUND (config)
**46 of 47 organic users are unverified** (only one gmail verified) — a ~2% rate,
abnormally low for "sent + delivered," which pointed at deliverability/link, not
engagement. **Tested live and found a concrete configuration root cause:**
- Registration DOES send the email (`auth-service.sendVerificationEmail`,
  fire-and-forget → SES). SES is in **production** (not sandbox) and verifiably
  delivers to external domains (observed: a `…@163.com` recipient got platform mail).
- **But the production stack's email config points at the DEV subdomain:**
  - `EMAIL_FROM = noreply@dev-public.biomate.ai` (sender looks like a dev/test
    address → lower inbox trust / spam placement).
  - `APP_URL = https://dev-public.biomate.ai` → every verify link is
    `https://dev-public.biomate.ai/verify-email?token=…`, i.e. a **different domain**
    than the `biomate.ai` a user signed up on (confusing; some users won't click a
    dev-looking link; mismatched-domain cookies/redirects).
  - **Both `biomate.ai` and `dev-public.biomate.ai` are already verified SES domains**
    (sending enabled), so the fix needs **no new infra** — only config.
- Secondary: the send is fire-and-forget with `.catch(() => {})`, so per-recipient
  send failures are **silently swallowed** — no telemetry to distinguish "not
  delivered" from "not clicked."
- **Fix (config only — the user's call, since biomate.ai is the canonical product
  URL): on the production frontend set `EMAIL_FROM=noreply@biomate.ai` and
  `APP_URL=https://biomate.ai`** so verification mail comes from, and links to, the
  real domain. Also log the verification-send outcome instead of swallowing it. NOT
  changed autonomously — it's production, outward-facing (every user's email), and
  "which domain is canonical" is a product decision.
- **Test to confirm after the fix:** register a deliverable address → the email
  arrives from `@biomate.ai` with a `biomate.ai/verify-email?token=…` link → clicking
  flips `email_verified` true.

### I10 — Post-signup churn · MEDIUM · onboarding
~13 organic users (incl. Harvard, Houston Methodist, UTHealth, Tsinghua) registered
and never engaged; two opened a chat and sent nothing. Likely compounded by I9
(unverified → degraded first session) and an empty cold-start.
- Related: the cold-start cleanup + example rows shipped this cycle.

### I11 — Required-param / "Missing input" friction · MEDIUM · UX, high-frequency
Very frequent across USC, alibaba, kk, alphac, GIBH, Wenzhou, Chongqing, Delhi, HKU:
"⚠️ 1 required parameter need to be filled" and "Missing: input data / accession /
FASTQ." Often legitimate, but the volume suggests users expect the run to proceed or
don't find the panel. Some are fine (guarding a real missing input); worth a UX pass
on making the required-param affordance obvious and offering a sample dataset.

### I12 — Citation-integrity friction · LOW · working as intended
ncsu and St. Jude users were told the assistant can only cite from papers they
supply. Correct behavior (citation-integrity guard), logged as friction only so it's
not mistaken for a bug.

(Not an issue — positive signal: a `gmail.com` user probed with hack/role-play/
paradox prompts; BioMate refused each correctly.)

## Test mapping
| Issue | Status | Test |
|---|---|---|
| I1 engine-unreachable | still live | NEW: retry/backoff on ECONNREFUSED for generate + run_code paths (unit on the fetch wrapper) |
| I2 run_code unreachable | still live | same wrapper test as I1 |
| I3 no-AI-response | open | provider-timeout handling test (generate path) |
| I4 Drive ingestion | partial | e2e: "my reads are on Google Drive <link>" → From-URL ingestion, not a refusal |
| I5 upload 500 | open | API test: upload .py/.docx + read_file → no 500 |
| I6 hallucinated accession | open | accession-benchmark: invented GEO ID must be caught by the resolver |
| I7 no-such-table | fixed | regression note only (0 in logs) |
| I8 run-diagnosis | addressed | e2e: "why is my run failing" → run-grounded diagnosis (not literature) |
| I9 verification | systemic | e2e: register deliverable email → verify link flips email_verified |
| I10 churn | onboarding | funnel metric; cold-start already revised |
| I11 required-param UX | open | UX pass + sample-dataset affordance |
| I12 citation friction | WAI | none (keep) |

## Live-test results this pass (2026-11-10)
- **I9** — root-caused to config: prod `EMAIL_FROM`/`APP_URL` point at the dev
  subdomain (`dev-public.biomate.ai`); both domains are SES-verified; send is wired
  but fire-and-forget. Concrete, infra-free fix below.
- **I1/I2** — confirmed STILL LIVE: `ECONNREFUSED 127.0.0.1:8081` within 6h (none in
  last 2h); the generate/run_code paths surface it instead of retrying.
- **I7** — confirmed FIXED: `no such table: workflows` has 0 occurrences in current logs.

## Top actions (highest leverage first)
1. **I9 verification config** — set `EMAIL_FROM=noreply@biomate.ai` +
   `APP_URL=https://biomate.ai` on the production frontend (both domains already
   SES-verified; no new infra), and log send outcomes. This is the single
   highest-leverage organic fix; it's production email config, so confirm before
   applying.
2. **I1/I2 connectivity resilience** — extend the execution retry to the
   workflow-generation and run_code paths so a transient Galaxy refusal doesn't become
   a user-visible "could not generate workflow."
3. **I4 Drive ingestion in-conversation** — route share-link mentions to the From-URL
   path instead of replying it's impossible.
4. **I8 run-diagnosis** — confirm the universe-context fix returns run-grounded
   answers (McGill-style repeat failure).

See [[project_personal_workflow_batch_exec]] (exec reliability), the SES/admin-alert
work (I9), and `research_confabulation` (I6).
