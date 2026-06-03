# IND Module — Honest Audit (2026-06-03)

**Triggered by:** user feedback that "the product is not complete, there are plenty of non-functioning elements." Previous session writeups claimed 20/20 punch-list closed and 27/27 surfaces match — that was inaccurate. This document re-classifies every visible surface as **WORKING**, **PARTIAL**, or **FAKE**, with line numbers.

**Method:** read every `.tsx` file under `frontend/client/src/components/ind-report/` and `frontend/client/src/pages/ind-report.tsx`, plus the backend routes they're supposed to call. For each visible UI element: does it have an `onClick`? does that handler hit a real backend? does the backend write durable state?

---

## TL;DR — the biggest single problem

**The entire 5-step pipeline view (Project Setup → ADMET → PBPK → Lead Selection → IND Document) is a hardcoded JavaScript constant.** Whichever IND project the user selects, the same `DEMO_ADMET`, `DEMO_PBPK`, `DEMO_LEADS`, `DEMO_DOC` constants are rendered. Source: `frontend/client/src/pages/ind-report.tsx` lines 204-272.

So when the user clicks between BM-0042 and BM-0038 and BM-0029, they're looking at identical fake data. No backend lookup, no campaign-specific results. The lead candidate displayed in Step 1 (`CC(=O)Nc1ccc(Oc2ncnc3[nH]ccc23)cc1…`) is the same regardless of project ID. **This is the demo-grade feel the user is reacting to.**

---

## Surface-by-surface inventory

### Step 1 — Project Setup (`IndSteps.tsx:65-122`)

| Element | Status | Notes |
|---|---|---|
| Molecule / Target / Indication / Sponsor display | **PARTIAL** | Shows project metadata from `DEMO_PROJECTS`; doesn't fetch from real registry per project ID. New-project modal writes to `data/ind_demo/registry/projects.json` but never reads back per-project. |
| Target regions chips (FDA/EMA/NMPA/PMDA) | **WORKING** display only — non-FDA can't actually generate content (see Region Selector in Doc Panel) |
| "12 SMILES uploaded · Edit" link | **PARTIAL** | The "12" is hardcoded label text. SMILES list modal works (`SmilesListModal.tsx`) and PATCHes `/api/ind-report/projects/:id/compounds`, but the count display doesn't reflect the actual list length. |
| Lead SMILES display | **FAKE** | Hardcoded string at `IndSteps.tsx:108`: `CC(=O)Nc1ccc(Oc2ncnc3[nH]ccc23)cc1…`. Not editable. Not pulled from campaign. Same for every project. |

### Step 2 — ADMET Screening (`IndSteps.tsx:139-317`)

| Element | Status | Notes |
|---|---|---|
| Pass/Total summary (X/Y) | **FAKE** | From `DEMO_ADMET.summary` constant |
| Per-compound table (hERG, DILI, Ames, logP, MW, Ro5) | **FAKE** | Static rows from `DEMO_ADMET.compounds` |
| "Re-run" button (line 195) | **FAKE** | No `onClick` handler. Pure visual. |
| "View qualification table" toggle | **WORKING** | Local state only |
| "View wet-lab enrichment" toggle | **WORKING** | Local state only |
| **"Upload PDF or CSV" button** (line 291) | **FAKE** | No `onClick`. No backend endpoint exists to accept the upload. |
| **"Link NDA: \[NDA # (coming soon)]" input + Fetch button** (lines 299-311) | **FAKE** (honest) | `disabled aria-disabled="true"` — at least the disabled state is wired, with tooltip "NDA fetch not yet wired" |

### Step 3 — PBPK Qualification (`IndSteps.tsx:331-461`)

| Element | Status | Notes |
|---|---|---|
| Model / Reference set display | **PARTIAL** | From `DEMO_PBPK.refSet` constant ("30 drugs"); the **underlying file `backend/lib/galaxy/ai/drug_discovery/reference_data/pk_marketed_drugs.json` is real** — 30 marketed drugs with PK params from cited references. But the page doesn't load this dynamically; it shows the hardcoded constant. |
| Cmax / AUC within-2-fold metrics | **FAKE** | `DEMO_PBPK.metrics` constant. |
| Per-drug fold-error table | **FAKE** | `DEMO_PBPK.perDrug` constant. **`model_validation.py` can compute this for real**, but the page never calls it. |
| "Review excluded compounds" button (line 393) | **FAKE** | No `onClick`. |
| **"Re-run with new params" button** (line 394, fail path) | **FAKE** | No `onClick`. |
| **"Re-run with new params" link** (line 413, pass path) | **FAKE** | No `onClick`. |
| EMA criterion verdict | **PARTIAL** | Display works; threshold is from the constant. |
| **30 drugs claim** | **REAL but inadequate** | The file exists with 30 real PK entries. **30 is too small for an FDA-grade qualification claim** — published SimCYP/PK-Sim PBPK reference sets are 100-300 compounds. The §2.6.2 narrative cites "30 reference compounds" verbatim from `ind_assembly.py:2031`. |

### Step 4 — Lead Selection (`IndSteps.tsx:465-557`)

| Element | Status | Notes |
|---|---|---|
| "Top: \<id>" status pill | **FAKE** | `DEMO_LEADS.ranking[0].id` |
| Method + Evaluated/Rounds | **FAKE** | `DEMO_LEADS.method` etc. |
| Per-rank table (Compound / Score / hERG / DILI / Ames / Potency / AD) | **FAKE** | Static `DEMO_LEADS.ranking` array. **`bayesian_optimizer.py` produces this for real**, but the page doesn't read it. |
| "View all N →" button | **WORKING** | Local state expand |
| Applicability domain line | **FAKE** | `DEMO_LEADS.inDomain / outOfDomain` |
| **Edit lead candidate** | **MISSING** | No edit UI exists. Lead is read-only display. |

### Step 5 — IND Document (`IndSteps.tsx:559-704`)

| Element | Status | Notes |
|---|---|---|
| Audit findings list | **WORKING** | Comes from `DEMO_AUDIT` constant (still demo data), but the UI rendering + dismissal flow are real. |
| Section coverage chips | **PARTIAL** | Display works; coverage values are from `DEMO_DOC.sections` constant. |
| "View" button per finding (line 680) | **WORKING** | `onClick={onAudit}` |
| "Regenerate" button per finding (line 681) | **WORKING** | `onClick={onRegenerate}` opens the regen modal in `IndDocPanel.tsx`, which POSTs to `/api/ind-report/sections/:id/regenerate` (in `feedback_router.py`). |
| "View doc" button (line 686) | **WORKING** | `onClick={onViewDoc}` |
| "Download" button (line 689) | **WORKING** | `onClick={onDownload}` calls Markdown export path |
| "Sign" button (line 693) | **WORKING** with caveat | Opens sign overlay; backend `sign` endpoint runs. **TOTP is fake in dev** — see Section "Sign + TOTP" below. |
| "Submit to FDA" disabled button (line 697) | **FAKE** (honest) | `disabled` — UI says "blocked until signed". No FDA-submission endpoint exists. |

### Doc Panel (right side, `IndDocPanel.tsx`)

| Element | Status | Notes |
|---|---|---|
| Region selector | **PARTIAL** | FDA option works. EMA/NMPA/PMDA all `disabled` with "coming soon" labels. Backend `/sections/render` returns `not_implemented` for non-FDA per `ind_actions_router.py:300`. |
| Version chip + popover | **WORKING** | Reads from `/versions` |
| "Audit" button | **WORKING** | Opens audit overlay |
| "Download .md" button | **WORKING** | Calls `/document.md` |
| "Download .docx" button | **WORKING** | Calls `/document.docx` (python-docx renderer; landed 2026-05-29) |
| "Sign & Freeze" button | **WORKING** with TOTP caveat |
| Chat handoff link | **WORKING** | Routes to `/chat?context=ind-report&project=…` |
| Citation add inline `+` icon | **WORKING** | Opens citation popover |
| Per-paragraph "Regenerate" link | **WORKING** | Streams via SSE per `feedback_router.py` |

### Sign overlay + TOTP (`IndOverlays.tsx`, `ind_actions_router.py`)

| Element | Status | Notes |
|---|---|---|
| Signer title / credentials / scope text inputs | **WORKING** | Real form, real POST |
| 6-digit "authenticator code" input boxes | **PARTIAL** UI / **FAKE** verification | Backend `_verify_totp` at line 78: **`return bool(re.fullmatch(r"\d{6}", code))` in dev** — accepts any 6 digits. No MFA enrollment flow exists. No QR code generation. No `pyotp.TOTP(secret).verify(code)` call. |
| 30s countdown timer | **WORKING** display | Real RFC 6238 window math (`30 - now % 30`); meaningless without a real shared secret |
| SHA-256 of doc body | **WORKING** | Real; computed on canonical JSON, stored in audit chain |
| Sign success card → "Download DOCX" | **WORKING** | Calls `downloadDocx` |
| Sign success card → "Download Audit Trail PDF" | **WORKING** | Calls `downloadAuditTrailPdf`, server-side reportlab with hash chain (landed 2026-05-29) |
| Audit chain mirror to S3 with Object Lock | **WORKING** opt-in | Set `BIOMATE_SIGN_AUDIT_S3_BUCKET` env to enable |

### Left nav (`IndLeftNav.tsx`)

| Element | Status | Notes |
|---|---|---|
| Project list | **WORKING** | Reads from local state seeded by `DEMO_PROJECTS` + any projects the user creates via NewProjectModal |
| "+ New project" | **WORKING** | NewProjectModal POSTs to `/api/ind-report/projects` |
| Sponsor / Billing / Help / Settings | **FAKE** (acknowledged in comment `IndLeftNav.tsx:69`: "Billing + Help were href=`#` stubs; Settings dialog says 'porting'") |

### Other shells / overlays

| Element | Status | Notes |
|---|---|---|
| `DocPanelMobileModal.tsx` (FAB on narrow viewport) | **WORKING** | Opens mobile-style doc panel |
| `EditableParagraph.tsx` | **WORKING** | In-place edit a paragraph; POSTs to `/api/ind-report/projects/:id/edit` per `feedback_router.py` |
| `NewProjectModal.tsx` | **WORKING** | Real form, real POST |
| `SmilesListModal.tsx` | **WORKING** | Real form, real PATCH |
| `IndOverlays.tsx::IndAuditOverlay` | **WORKING** | Audit findings + dismissal |
| `IndOverlays.tsx::IndEmptyState` | **WORKING** | Reference-compound chips that bootstrap a demo project |
| Tutorial button | **REMOVED** | Commented out per `ind-report.tsx:82` |

---

## Backend endpoints — what's actually implemented

`backend/lib/galaxy/ai/drug_discovery/ind_actions_router.py`:

| Endpoint | Status |
|---|---|
| `POST /sign` | **REAL** (with weak TOTP in dev) |
| `POST /document.md` | **REAL** |
| `POST /document.docx` | **REAL** (python-docx) |
| `GET /audit-trail.pdf` | **REAL** (reportlab + hash chain) |
| `POST /snapshot` | **REAL** (jsonl append) |
| `GET /versions` | **REAL** |
| `POST /sections/render` | **PARTIAL** — FDA path returns the canonical markdown; EMA/NMPA/PMDA return `{"not_implemented": true}` |
| `PATCH /compounds` | **REAL** (writes back to projects.json) |

`backend/lib/galaxy/ai/drug_discovery/feedback_router.py`:

| Endpoint | Status |
|---|---|
| `POST /projects/:id/edit` | **REAL** |
| `POST /audit/:id/dismiss` | **REAL** |
| `POST /citations/suggest` | **REAL** |
| `POST /sections/:id/regenerate` | **REAL** (SSE-streamed) |

**What's NOT implemented (and would need to be for the visible UI to be real):**

| Missing endpoint | Required by |
|---|---|
| `POST /projects/:id/attachments` (PDF/CSV upload) | Step 2 ADMET upload button |
| `POST /projects/:id/nda-fetch` (FDA NDA → PK params) | Step 2 NDA link input |
| `POST /projects/:id/rerun-pbpk` (with new params) | Step 3 Re-run with new params |
| `POST /projects/:id/rerun-admet` | Step 2 Re-run |
| `GET /projects/:id/admet-results` | Step 2 dynamic data |
| `GET /projects/:id/pbpk-results` | Step 3 dynamic data |
| `GET /projects/:id/lead-ranking` | Step 4 dynamic data |
| `POST /projects/:id/submit-to-fda` | Step 5 "Submit to FDA" button |
| `POST /auth/mfa/enroll` (generate TOTP secret + QR) | Real Sign |
| `POST /auth/mfa/verify` (real pyotp.verify) | Real Sign |

---

## What's actually real and load-bearing

To not undersell — these things work today end-to-end on dev:

1. **Markdown export** — full doc renders correctly with project metadata and section bodies
2. **DOCX export** — Word doc, FDA-format, opens in Office
3. **Audit Trail PDF** — hash-chained, tamper-evident, 21 CFR Part 11 §11.10(e) presentation (the e-signature side of §11.10(c) is weak — see TOTP)
4. **Sign + audit chain append** — local jsonl + optional S3 Object Lock mirror
5. **Version history** — snapshot endpoint + versions list
6. **Per-paragraph regenerate via SSE** — streams Claude/GPT response into the doc
7. **In-place paragraph edit** — captures user corrections, persists
8. **Audit finding dismissal** — captures reason + persists
9. **Citation add** — popover + persist
10. **New project + SMILES editor + project switcher** — real CRUD
11. **Chat handoff** — routes correctly to `/chat`
12. **GPT-5 frontier path** for generation — 90% on the n=100 9-checker eval (currently primary)

---

## Severity-ranked punch list (no implementation yet — for prioritization)

### Tier S (would call this "fraudulent in a customer demo"):

| # | Item | Cost to fix |
|---|---|---|
| S1 | DEMO_ADMET / DEMO_PBPK / DEMO_LEADS / DEMO_DOC hardcoded — same data shown for every project | **Large.** Needs `GET /projects/:id/{admet,pbpk,leads,doc}` endpoints + real per-project computation. 2-3 days. |
| S2 | TOTP "authenticator code" is fake — any 6 digits sign | **Medium.** `pyotp` + enrollment screen + QR + secret storage. ~1 day. |
| S3 | Lead candidate display is hardcoded SMILES string | **Small** once S1 is in place — render the lead from per-project leads data |

### Tier A (visible buttons that pretend to work):

| # | Item | Cost to fix |
|---|---|---|
| A1 | Upload PDF or CSV button | **Medium.** POST endpoint + S3 write + lib parse for PDF text / CSV columns. ~1 day. |
| A2 | "Re-run with new params" ×2 (PBPK fail + pass path) | **Medium.** Need a params edit UI + `POST /rerun-pbpk` + UI refresh on completion. ~1 day. |
| A3 | "Re-run" button in Step 2 ADMET | **Same shape as A2.** ~0.5 day on top of A2. |
| A4 | "Submit to FDA" disabled but no plan for it | **Out of scope short-term.** Either remove the button or be clear this is a v2 feature. |
| A5 | "Review excluded compounds" button | **Small.** Open a modal showing the excluded subset. ~0.5 day. |

### Tier B (cosmetic + honest stubs):

| # | Item | Cost to fix |
|---|---|---|
| B1 | "12 SMILES uploaded" — hardcoded count | **Trivial.** Derive from compounds array. ~30 min. |
| B2 | EMA / NMPA / PMDA region selectors disabled — "coming soon" labels | Known multi-region work; ~2 days per region for prose + tabulated handlers + audit ruleset |
| B3 | Sponsor / Billing / Help / Settings nav items | **Small.** Wire to real pages or hide. |
| B4 | NDA fetch — disabled with honest label | Either implement (medium-large; requires FDA NDA scraper + extractor) or remove entirely |

### Tier C (data quality):

| # | Item | Cost to fix |
|---|---|---|
| C1 | PBPK reference set is 30 drugs; "FDA-grade" typically wants 100+ | **Medium.** Source 70 more from SimCYP / OSP / published lit, re-run validation. ~1 day data wrangling + 1 day write-up. |
| C2 | §2.6.2 narrative cites "30 reference compounds" — when C1 lands, update the narrative | Trivial; just a string change |

---

## What I'd recommend tackling first

If we're picking the smallest set that lifts the demo from "obviously fake" to "credible early-stage product":

1. **S1** (per-project real data) — without this, everything else feels fake
2. **A1** (upload PDF/CSV) — high-frequency visible action
3. **A2 + A3** (re-run with new params) — high-frequency visible action
4. **S2** (real TOTP) — required before any Part 11 claim is honest

That's ~6 person-days of work. C1 (PBPK 30 → 100 drugs) is the next priority for any regulatory-credibility claim.

But this is your call. I won't start coding any of this until you pick.
