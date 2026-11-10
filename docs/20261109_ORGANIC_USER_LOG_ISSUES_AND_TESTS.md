# Organic registered-user log review — issues & tests (2026-11-09)

**Method.** Reviewed the chat activity of the **organic** (external-domain) registered users on dev
(`biomate-dev-postgres`, inline `chat_sessions.messages`, via SSM), excluding seeded / verify / fixture
/ e2e accounts. This is a **product-issue** review. Users are referenced by institution/role only — no
names, emails, or verbatim private content are committed here; issues are paraphrased. (The owner has
the account identifiers from this session's chat for any follow-up.)

**Users reviewed (real chat activity, last ~2 weeks):**

| Ref | Institution / role | Task | Engagement / outcome |
|---|---|---|---|
| **U-META** | SE-Asian university; environmental microbiology | Shotgun metagenomics, ~30 GB soil reads | **High (5 sessions) — churned, data never ingested** |
| **U-MOFA** | Canadian university; cancer multi-omics | Integrate processed HNSCC RNA-seq + proteomics | Medium — hit routing + run-failure |
| **U-FISH** | National academy institute; comparative genomics | Cross-species gene annotation / co-evolution | Medium (18 turns) |
| **U-TEXT** | — | Requested a multi-volume textbook | Out of scope |
| **U-BOUNCE** ×3 | Harvard / US hospital / other | Opened chat, 0 messages | Bounced at the empty chat |

**Headline:** a high-value environmental-microbiology user churned entirely on **data ingestion**, and
a cancer multi-omics user hit a **routing** bug plus an **opaque run failure**. These two things are
costing real organic signups right now.

---

## Cross-cutting issues (ranked by churn impact)

### 1. [CRITICAL] No cloud/Google-Drive ingestion; large-file upload fails
**U-META** had ~30 GB of shotgun reads (paired gzip, ~6–7 GB each) and could not get them into BioMate
across five sessions. Paraphrased: browser upload "takes forever," failed with a NetworkError on the
multi-GB files, an upload once appeared to succeed then vanished, and the user repeatedly asked to
supply a Google-Drive link instead — concluding the system "is not user friendly" and the ingestion
"starting point is a bottleneck." This user churned.

- **Root cause.** From-URL ingestion accepts **HTTP/HTTPS, SRA/ENA, FTP, S3 only** — **not Google
  Drive** (`galaxy-dataset-browser.tsx:657-678`). Multipart upload exists for >100 MiB
  (`lib/upload.ts`) but failed with NetworkError on multi-GB files and was unusably slow on the user's
  link. A Drive share link is not a direct download for large files, so pasting it does nothing today.
- **Fix.** (a) Add **Google Drive (and generic cloud) ingestion** — server-side fetch via the Drive API
  / large-file confirm-token. (b) Harden the large-file path: resumable, retry-on-NetworkError, visible
  progress, no silent loss after a transient failure. (c) Interim: the assistant should proactively
  steer users with large public data to **SRA/ENA accession or an S3/HTTPS URL** instead of browser
  upload.
- **Tests.** T1: paste a Drive share link to a >5 GB file → it ingests. T2: upload a 10 GB gzip over a
  throttled link → resumes after a dropped request, nothing lost. T3: "my data is on Google Drive, how
  do I load it?" → the assistant gives a working path, not a dead end.

### 2. [HIGH] Routing selects a RAW pipeline when the user has PROCESSED tables
**U-MOFA** had already-processed RNA-seq DE tables + proteomics abundance tables and wanted downstream
integration (overlap, concordant/discordant log2FC, EGFR/MAPK enrichment, MOFA2). BioMate kept
selecting a raw mass-spec pipeline; the user had to explicitly forbid `nf-core/diaproteomics` twice.

- **Root cause.** Intent routing keys on the modality ("proteomics") and picks the canonical raw
  pipeline, ignoring the "already-processed / integrate existing tables" signal.
- **Fix.** Detect downstream-integration intent (inputs are DE/abundance **tables**, not raw files) and
  prefer `differentialabundance` / MOFA2 integration over a raw-MS pipeline.
- **Test.** "Integrate my processed DE and protein-abundance tables; find concordant/discordant genes
  and enriched pathways" → routes to multi-omics integration, **not** a raw-MS pipeline.

### 3. [HIGH] Opaque run failure — the user cannot self-diagnose
**U-MOFA** asked "why is the run failing?" three times in one session; the failure cause was not legible.

- **Fix.** On failure, surface a plain-language cause + the specific input/param at fault + a concrete
  next action, in the chat reply (not only the panel).
- **Test.** Force a known failure (bad contrast / missing column) → the chat reply states cause + fix in
  one message, without the user having to ask "why".

### 4. [MED] Uploads vanish; attach is unreliable
An upload that reported success later "was gone"; attach failed repeatedly. **Fix/Test:** a successful
upload persists in the session + Data hub across reload; a failed attach shows a clear retry, never a
phantom "sent".

### 5. [MED] Workflow panel & param discoverability for first-timers
**U-META** was told "7 required parameters — open the panel to configure," couldn't find the panel,
couldn't find the genomics workflow "on the right side," and reported a QC workflow that "is not
opening." **Fix/Test:** the "open the panel" guidance points to a visible affordance; a first-time user
opens the workflow panel and the QC workflow on the first try.

### 6. [MED] Delete-chat is undiscoverable (backend exists)
**U-META** asked how to delete chats and wanted to clear old ones to "start anew." `DELETE
/api/sessions/:sessionId` **exists** (`routes.ts:18116`) — the UI affordance is missing/hidden, and the
assistant can't delete other chats on request (correct) but doesn't point to the control. **Fix/Test:** a
discoverable per-chat delete; the assistant names where it is when asked; delete removes the session.

### 7. [LOW] Out-of-scope expectation
**U-TEXT** asked BioMate to author a multi-volume textbook — not a bioinformatics task; bounced after 2
messages. Not a bug, but a landing/expectation-setting signal.

### 8. [CHECK] Cross-species gene-annotation accuracy (correctness)
**U-FISH** ran genome-wide annotation/co-evolution queries (neurog2, insrr, trex1, vsig4 across fishes)
and at one point asserted a gene is absent in zebrafish where it is in fact annotated. Worth a
correctness pass on the research / genome-DB search path (cf. the research_query confabulation risk):
across 18 turns, did BioMate confirm/deny annotations accurately?

---

## Per-user outcome
- **U-META — LOST to ingestion.** Highest-intent user (real soil-metagenomics project; wanted a
  downloadable reproducible pipeline for reviewers). Fixing #1 likely wins this user back — a follow-up
  is worth it.
- **U-MOFA — recoverable.** Sophisticated multi-omics ask; blocked by #2 (routing) + #3 (failure
  opacity), both tractable.
- **U-FISH — engaged; verify correctness (#8).**
- **U-TEXT — out of scope (#7).**
- **U-BOUNCE ×3 — bounced at the empty chat** (0 messages). First-screen activation is leaking
  high-value institutional signups; worth a separate onboarding look.

## Priority
1. **#1 cloud/Drive ingestion + large-file robustness** — the single biggest organic-churn cause.
2. **#2 processed-vs-raw routing** and **#3 run-failure legibility** — win back the multi-omics user.
3. **#5/#6 first-run discoverability** (panel, QC open, delete-chat).

## Reproduction pointers
- Source: `chat_sessions` on `biomate-dev-postgres` (inline `messages` jsonb), organic external-domain
  users. Query via SSM `AWS-RunShellScript` → `docker exec … psql` (account identifiers held in session).
- Capability checks done: From-URL schemes (`galaxy-dataset-browser.tsx:657-678`), multipart upload
  (`lib/upload.ts`), delete-session route (`routes.ts:18116`).
