# BioMate — UX / HCI Expert Review

**Date:** 2026-10-02
**Method:** Nielsen heuristic evaluation + cognitive walkthrough, grounded in the actual React source (`frontend/client/src/`), the design reference (`reference/claude_design/data_centroid_design_v2/`), and prior UX docs under `docs/`.
**Target user assumed:** a bench scientist or clinician who is **not** a bioinformatician — wants to run RNA-seq / variant-calling / ADMET / imaging by asking in natural language, does not write Nextflow, does not think in genome builds, FDR thresholds, GATK, or S3 URIs.

**One-line verdict (full version at the end):** The engine and the chat loop are genuinely strong, but the product still speaks fluent bioinformatics at a user who by definition does not — and several first-run surfaces (dashboard, signup, upload) actively break trust. **Not yet easy for its stated target user.**

---

## 0. What's strong (so the critique is calibrated)

Before the problems: several things are done well and should not be regressed.

- **No hard API-key gate.** Chat works out-of-the-box on a platform-provided model; BYOK (`provider: 'default' | 'anthropic' | 'openrouter'`) is optional (`settings-dialog.tsx:145`). Good — many "AI for science" tools wall this.
- **Launch-rejection errors are reassuring and actionable.** `lib/workflow-execution-error.ts` maps execute-API failures to plain messages that explicitly say *"This workflow was not started, so no compute was used"* and name the remedy (`missing_required_params`, `inputs_required`, etc.). This is exactly right for a cost-anxious novice.
- **Honest empty states** on most data surfaces (`projects.tsx:224`, `data-hub.tsx`, `galaxy-dataset-browser.tsx:199`) — the system refuses to fabricate. The dashboard is the glaring exception (§3 below).
- **The run panel has a coherent 3-tab model** (Workflow settings · Phases · After run) that is **status-aware**: it auto-selects Settings when idle, Phases when running, After run when done (`nextflow-workflow-viewer.tsx:1099-1107`). This matches the reference spec's intent well.
- **Pre-flight blocking is clear:** the primary Run button disables with a `title` naming the exact count of unfilled required params (`nextflow-workflow-viewer.tsx:3802-3806`).

---

## 1. Cognitive Walkthrough — the first-time-user journey

For each step: *what a non-bioinformatician expects* → *what the UI actually does* → *where they stumble*.

### Step 1 — Land & sign up (`pages/auth/register.tsx`)
- **Expects:** "make an account, poke around for free."
- **Actual:** 3-step flow (account → domain → trial). An **Invite Code** field whose `(required)`/`(optional)` label is driven by an async `GET /api/auth/config` and is **blank until that resolves** (`register.tsx:408-412`); on a slow/failed fetch the user cannot tell whether a code is needed and only learns on submit: *"An invite code is required to register during our closed beta"* (`register.tsx:105`). Then step 3 pushes Stripe: primary CTA *"Add payment method & start trial"* with escape only as a muted ghost link *"Skip for now — explore the free tier"* (`register.tsx:293-298`).
- **Stumble:** possible hard block at the invite wall with no path to a code; payment pressure before the user has seen a single result; plan is called **"Premium"** here but **"Pro"** on the dashboard (`dashboard.tsx:233`) — naming whiplash at the moment trust matters most.

### Step 2 — Tell BioMate your domain (`domain-profile-selector.tsx`, register step 2)
- **Expects:** "pick my research area in plain words."
- **Actual:** a 25-tile grid whose refine-by-topic pills are **pure expert vocabulary**: *"variant calling (SNP/indel, GATK4/Mutect2)"* (`:22`), *"bulk RNA-seq (STAR / Salmon / Kallisto)"* (`:32`), *"differential expression (DESeq2 / edgeR / limma)"* (`:36`), *"protein structure prediction (AlphaFold / Boltz / Chai-1)"* (`:91`), *"population pharmacokinetics (NONMEM)"* (`:111`).
- **Stumble:** the user is asked to self-classify using the exact tool names the product claims to abstract away — *before* they have seen the product. Header says *"36 domains and 2,600+ workflows"* (`:425`) but the grid shows 25 and code/MCP cite 2,632 / 4,017 — inconsistent counts erode trust on page one.

### Step 3 — Log in next time (`pages/auth/login.tsx`)
- **Actual:** login is beige with a bespoke palette; the password-reset pages are a blue/purple/pink gradient; MFA is plain — **four different auth backgrounds in one funnel**. OAuth (Google/GitHub) buttons are commented out; the handlers only `toast` *"Google login not configured yet"* (`login.tsx:72`). Email placeholder `name@institution.edu` signals "academic only" despite register pitching Pfizer/Genentech.
- **Stumble:** cosmetic but reads as "unfinished"; institutional users who expect SSO find nothing and no explanation.

### Step 4 — Create a project / context (`create-project-dialog.tsx`, `project-detail.tsx`)
- **Expects:** "a folder for my study."
- **Actual:** label/placeholder mismatch — label asks *"What are you working on?"* but the placeholder answers *"Name your project"* (`create-project-dialog.tsx:223/227`). A *"Background instructions (optional)"* field explained as *"help the AI assistant understand your project… included in all project conversations"* (`:255-263`) — prompt-engineering vocabulary. Inside a project, the right rail stacks **three overlapping context concepts**: *Standing instructions* ("read by the assistant on every chat"), *Notes* ("private to you — not read by the assistant"), and *Plan / hypothesis* (`project-detail.tsx:950,988,1056`), with a *"Promote to instruction ↑"* action.
- **Stumble:** the instructions-vs-notes **trust boundary** (what the model acts on vs what it ignores) is UX-critical but conveyed only in fine print — the 2026-09-18 re-audit flagged this exact gap as HIGH safety/trust (`docs/20260918_PHASE2_REAUDIT…md §2.2`). Category taxonomy here (8 ad-hoc items: "Healthcare, Machine Learning, Data Analysis…") doesn't match the 25-domain taxonomy the user just filled in at signup.

### Step 5 — Ask for an analysis (`chat-input.tsx`, empty state in `chat-interface.tsx`)
- **Expects:** a chat box: "describe my experiment."
- **Actual (good):** empty state shows *"Input your use case here"* with 4 example chips (`chat-interface.tsx:2369-2427`). **But the examples themselves are expert-coded:** *"Screen these compounds… hERG cardiotoxicity, CYP3A4 inhibition… aspirin (CC(=O)Oc1ccccc1C(=O)O)"*, *"Run nf-core RNA-seq… s3://my-bucket/fastqs/ — human GRCh38, paired-end… FDR 0.05"* (`:139-149`). The placeholder is *"Ask BioMate to run a workflow or analyze your data…"* (`locales/en/common.json:89`) — foregrounding **"workflow,"** the one abstraction the product claims to hide.
- **Actual (worse):** above the box sit two prompt-engineering affordances. The **Instructions** placeholder is the single clearest jargon leak in the whole app: *"Standing instructions for this composer — e.g. report FDR<0.05, use GRCh38, prefer conservative thresholds."* (`chat-input.tsx:668`). A **lane preview** badge appears as you type: *"Cloud · validated workflow"* vs *"Instant · cited answer"* with *"let BioMate decide"* (`chat-input.tsx:712-721`). "Lane," "Cloud," "Instant," "composer," "expert packs" are all internal taxonomy. (The reference spec explicitly says *"say the consequence, not the lane"* — the shipped UI still prints the lane name.)
- **Stumble:** returning users get **no suggestions at all** — `ReturningUserWelcome` returns `null` because the 32 suggested queries weren't E2E-validated (`chat-interface.tsx:444-449`); only the `ColdStartDashboard` goal box remains.

### Step 6 — Get a workflow suggestion (`chat-message.tsx` → `nextflow-workflow-viewer.tsx`)
- **Expects:** "it understood me; here's what it'll do."
- **Actual:** the AI text answer is followed by a **full workflow card rendered inline in the chat stream** (not the right panel) the first time — the panel only auto-opens on *restore* or an *active/completed run* (`chat-with-artifacts.tsx:172-186, 642-648`), or when the user clicks **Open** (`chat-message.tsx:680-687`). After it's been in the panel once, the card collapses to a `wf-chip` with a helpful hint (*"You can keep chatting while this run continues in the background"*, `chat-message.tsx:657`).
- **Stumble:** the first workflow appears as a large card *inside* the conversation; the chat↔panel handoff is not obvious to a first-timer, and the panel's existence has to be discovered. The disambiguation path (*"Which workflow best fits what you need?"*, `chat-message.tsx:819`) is good when it fires.

### Step 7 — Configure parameters (`nextflow-workflow-viewer.tsx`, Settings tab + per-phase params)
- **Expects:** fill in a couple of blanks in plain terms.
- **Actual:** params are prettified (`prettifyParamLabel`, `:190`) and split into Required / Optional groups with AI-prefilled values badged; missing required fields are highlighted amber and summarised (*"X required"*). A **"Choose file"** button opens a dataset browser for file params (`:2970`). Output-location radios appear (*"Default (BioMate-managed, kept 90 days)"*, user S3 as Advanced, `:3105`).
- **Stumble:** for workflows with real file-path params, a novice must still supply a dataset or an S3 URI; the input-mapping copy *"Nothing will run until N inputs are resolved"* (`:2981`) is clear but assumes the user knows what the input *is*. No plain-language "what is this parameter" help beyond the raw `description`.

### Step 8 — Run on AWS Batch (`handleExecute`, footer)
- **Actual:** footer primary button reads **"Confirm & Run"** (`locales/en/common.json:70`). If confidence is low, an "Execution blocked" alert offers **Fix now** / **Confirm anyway** with an auto-confirm countdown (`:3756-3785`). **No pre-run cost estimate** — `CostEstimateBadge` is deliberately commented out (`:450-478`); a vCPU-hr usage meter shows only if `used > 0` (`:3845`).
- **Stumble:** the user commits to a potentially multi-hour, real-money AWS Batch run with **no idea of cost or expected duration**. (Per `docs/20260918…§1.3` the money estimate is an intentional deferral, but the net experience for the novice is "I clicked Run and have no idea what it'll cost or how long.")

### Step 9 — Watch progress (Phases tab, SSE)
- **Expects:** a progress bar and "it's working."
- **Actual:** the **progress bar is commented out** (`:2583-2598`); status is carried only by a header badge + per-phase chips (RUNNING / DONE / FAILED) + per-phase `completedCount/total`. Live phase transitions arrive via SSE and update `data-status`. A background narrator posts short italic chat lines (QC / LOOP / FIND speaker pills).
- **Stumble:** for a 35-minute Batch run there is **no overall % and no ETA** — just chips. Prior docs confirm deeper observability gaps: raw logs, per-task resource data, autofix status, and a complete `/realtime/status` endpoint all exist backend-side but **no frontend surfaces them** (`docs/20260310_EXECUTION_TRACING_UX_GAPS.md`, Gaps 1-7). The user staring at a static "RUNNING" chip for 30 minutes cannot tell live from stuck.

### Step 10 — View & download results (After-run tab, `AfterRunReport`)
- **Actual:** on completion the panel auto-switches to After run; a post-run links row offers *View results · Download all · AI analysis* (`:3376-3410`); findings and outputs render from `s3_output_files`. On failure, runtime error text is sanitised (`sanitizeErrorText`, `:984` strips stack traces, `nextflow`→"the pipeline", `s3://…`→"the storage bucket").
- **Stumble:** on a hard failure the **only offered recovery is Restart / Start over** — re-running a deterministic failure from scratch (another multi-hour Batch spend); `-resume` plumbing exists but isn't wired to infra/timeout failures (`docs/20260817_FAILURE_UX_FINDINGS_AND_PLAN.md`, Finding 2). The 2026-08-17 doc also flags that raw Nextflow log tails still leak into the failure panel in some paths.

### Side-trip — the Runs dashboard (`pages/dashboard.tsx`) — **broken for first-timers**
A brand-new user who navigates to the dashboard sees **100% hardcoded mock data**: *"Welcome back, Dr. Smith"* (`:77`), fake runs ("DIA-LCMS Proteomics… 4,521 proteins"), *"Workflows Run 127 / +12%"*, *"Pro Plan / Next Billing Date November 17, 2025"* (a **past** date), a progress bar pinned at `value={100}`. Every row routes to `/`. There is **no empty state** — the opposite failure of every other page. (Note: the dashboard route is currently commented out in `App.tsx`, but the page exists and is reachable via project/nav paths; if it ships as-is it is actively misleading.)

---

## 2. Nielsen 10-Heuristic Evaluation

### H1 — Visibility of system status — **WEAK**
- Live run status is **under-communicated**: progress bar removed (`nextflow-workflow-viewer.tsx:2583`), no ETA, no overall %. For long Batch jobs the user has only phase chips.
- Backend has rich status (`/realtime/status`, logs, per-task resource, autofix) that **no component renders** (`docs/20260310_EXECUTION_TRACING_UX_GAPS.md`).
- **Good:** idle→running→terminal is reflected on `data-status` and the footer button text swaps (Confirm & Run → Pause/Stop → Run again/Restart, `:3813-3821`); sidebar chat dots pulse for running runs (`app-sidebar.tsx:396-403`).

### H2 — Match between system and the real world — **WEAK (core failing)**
- The product's vocabulary is bioinformatician vocabulary at nearly every turn: **"workflow/pipeline"** in the chat placeholder, dashboard, project "Workflow Runs" tab, and upload subtitle; **GRCh38, FDR<0.05** in the composer Instructions placeholder (`chat-input.tsx:668`); **GATK4, DESeq2, STAR, MACS2, AlphaFold, NONMEM** in the signup domain picker; **AWS Batch, QC gates, phases, "detach the watcher"** in the tour; **S3 bucket prefixes, SRA/ENA/EMPIAR accessions** in upload; **"Galaxy history," Galaxy UUIDs** in the dataset browser (`galaxy-dataset-browser.tsx:584`); **"Nextflow"** in the run-viewer component and sanitised errors.
- This is the single biggest gap between positioning ("for non-bioinformaticians") and reality.

### H3 — User control & freedom — **MIXED**
- **Good:** Pause / Stop / Resume / Cancel in the action bar (`:3708-3752`); "Reset to defaults" and "Start over"; a stop-reply dialog that asks what to do with queued messages (`chat-interface.tsx:2340-2360`); run can continue in background.
- **Weak:** no true "undo" of a launched run beyond cancel; on hard failure only Restart (no fix-and-resume for infra deaths); **Skip phase/step controls are commented out** (no backend), so a documented affordance silently doesn't exist (`:792-800, 950-958`).

### H4 — Consistency & standards — **WEAK**
- Plan naming **"Premium" (register) vs "Pro" (dashboard)**; workflow counts **2,600+ / 2,632 / 4,017**; email placeholders `@institution.edu` vs `@example.com`; **four auth-page backgrounds**; three different category taxonomies (25 signup domains / 8 create-project categories / raw `primaryDomain` keys shown on cards). The run-viewer footer/action-bar even uses a dark palette (`oklch(0.12 …)`, `:3687`) inconsistent with the light panel above it.

### H5 — Error prevention — **GOOD (pre-flight), WEAK (runtime)**
- **Good:** required-param gating disables Run with an explanatory title; low-confidence "Confirm anyway"; launch errors say "no compute was used."
- **Weak:** no cost/time guardrail before an expensive run; `file-upload.tsx` storage math can display **negative** "available GB" (`:84,121`); "Analyze with BioMate" on an empty project sends an under-specified canned message (`project-detail.tsx:508`).

### H6 — Recognition rather than recall — **MIXED**
- **Good:** example chips, AI-prefilled params with badges, dataset browser instead of typing paths, project-suggestion row.
- **Weak:** returning-user suggestions removed (`chat-interface.tsx:444`), so the recall burden returns; the user must *recall* what "lane," "instructions," "notes vs standing instructions," and tool names mean with no inline glossary.

### H7 — Flexibility & efficiency of use — **GOOD**
- Lane override, composer instructions, expert packs, S3-prefix bulk references, BYOK, panel resize, "Run again" param carryover, keyboard tour. These serve power users well — arguably **too** well, at the expense of the novice (expert affordances are shown by default, not progressively disclosed).

### H8 — Aesthetic & minimalist design — **MIXED**
- The chat and panel are clean and reference-faithful. But first-run surfaces are cluttered with concepts a novice doesn't need yet (lane preview, instructions, experts, output-location radios, QC editor), and the dashboard is cluttered with **fake** content.

### H9 — Help users recognise, diagnose & recover from errors — **MIXED**
- **Good:** sanitised runtime errors; typed launch errors with remedies; "AI analysis" and error-explain ("Analyzing error log…", `:3561`); `WorkflowExecutionErrorNotice` with title/detail/missing-params/action.
- **Weak:** some paths still leak raw Nextflow log tails (`docs/20260817…`); recovery = Restart-from-scratch for deterministic/infra failures; several silent failures (download no-ops in `data-hub.tsx:183` and project-detail; forgot-password renders the **raw reset link on screen** when email isn't configured — `forgot-password.tsx:62-71` — a token-exposure smell).

### H10 — Help & documentation — **WEAK**
- **No Help / Docs / "?" entry point in the sidebar** (`app-sidebar.tsx` nav has New Chat, Workflows, Connectors, Data, Models, Design, Recent Tools, Settings — no help). A `/tutorials` marketing page exists but isn't linked from the app shell. The only in-product guidance is the **Workflow-Panel spotlight tour** (`workflow-tour.tsx`), which itself is expert-framed ("phase hierarchy," "QC gates," "detach the watcher," "AWS Batch submission," `:31-135`) and teaches the panel rather than the core "ask → results" loop.

---

## 3. Severity-ranked friction list (Nielsen 0–4; top problems for a first-time bench scientist)

> Severity: 0 = not a problem · 1 = cosmetic · 2 = minor · 3 = major · 4 = catastrophe.

| # | Severity | Problem | Location | Why it hurts / Fix |
|---|---|---|---|---|
| 1 | **4** | **Dashboard is 100% fake data, no empty state** — "Welcome back, Dr. Smith," 127 fake runs, past billing date, progress pinned at 100%. | `pages/dashboard.tsx:20-247` | New user sees someone else's results as if their own → "whose data is this? is this broken?" Trust collapse. **Fix:** wire to real `/api/workflows/runs` + quota, add a true empty state ("No runs yet — start in chat"). Don't ship the mock. |
| 2 | **4** | **Pervasive expert jargon at a non-expert** — GRCh38/FDR in composer, GATK4/DESeq2/NONMEM at signup, AWS Batch/QC gates/"watcher" in tour, S3/SRA in upload, "Galaxy history"/Nextflow in data+runs. | `chat-input.tsx:668`; `domain-profile-selector.tsx:22-111`; `workflow-tour.tsx:31-135`; `file-upload.tsx:380-582`; `galaxy-dataset-browser.tsx:584` | The product's defining promise ("no bioinformatics knowledge needed") is contradicted on nearly every surface. **Fix:** plain-language labels with expert terms as secondary ("Reference genome (human)" not "GRCh38"); hide tool-name topic pills behind "Advanced." |
| 3 | **3** | **No cost or duration shown before committing a real AWS Batch run.** | `nextflow-workflow-viewer.tsx:450-478` (CostEstimateBadge disabled), `:3845` (meter only if used>0) | Cost-anxious novices won't click Run, or will be shocked at billing. **Fix:** show at least an order-of-magnitude time + "est. cost" (even a range) at Confirm & Run. |
| 4 | **3** | **Invisible run progress on long jobs** — progress bar removed, no ETA/%, backend status endpoints unused. | `:2583-2598`; `docs/20260310_EXECUTION_TRACING_UX_GAPS.md` | A static "RUNNING" chip for 30 min is indistinguishable from "hung." **Fix:** restore an overall progress bar + phase ETA; surface `/realtime/status`. |
| 5 | **3** | **Hard failure offers only Restart-from-scratch**; raw logs still leak in some paths. | `:3813`; `docs/20260817_FAILURE_UX_FINDINGS_AND_PLAN.md` Findings 1-2 | Re-running a deterministic failure wastes hours + money and reproduces the same error. **Fix:** classify transient vs deterministic; wire `-resume`/fix-and-resume; never show raw stack/log tails. |
| 6 | **3** | **Signup funnels straight into payment**; invite-code wall ambiguous; "Premium" vs "Pro" naming. | `register.tsx:105,293-298,247`; `dashboard.tsx:233` | Payment pressure + possible hard block before any value is seen = abandonment. **Fix:** default to free tier, make "continue free" the primary path; resolve invite-required state before rendering the field; unify plan names. |
| 7 | **3** | **Instructions vs Notes vs Standing-instructions trust boundary is opaque** (what the model reads vs ignores). | `project-detail.tsx:950,988,1056`; `docs/20260918…§2.2` | Users can't tell what's shaping their runs — a safety/trust gap, not just confusion. **Fix:** one clear "What the assistant reads" section with explicit on/off, plain copy. |
| 8 | **2** | **Composer leaks internal routing concepts** ("lane," Instant/Cloud, experts) by default. | `chat-input.tsx:668-725` | Decisions the system should make silently are pushed onto the novice mid-typing. **Fix:** per the reference spec, "say the consequence, not the lane"; move lane override + instructions + experts behind an Advanced disclosure. |
| 9 | **2** | **Dead / soft-dead controls** — projects ⋮ menu no-op; "Analyze" on empty project opens blank chat; silent download failures; commented-out OAuth with error-only handlers. | `projects.tsx:259`; `project-detail.tsx:503-511`; `data-hub.tsx:183`; `login.tsx:72-192` | Clicking a control that does nothing is a classic trust/competence hit. **Fix:** wire or remove each. |
| 10 | **2** | **Upload overwhelms with formats/modes/IDs** — 40+ extensions, Deferred-vs-Immediate radio, raw "Dataset ID: uuid," S3-prefix guidance, negative storage math. | `file-upload.tsx:84,106,380-629` | A novice with files on their laptop faces infrastructure decisions and raw UUIDs. **Fix:** lead with drag-drop + plain help, hide S3/deferred behind "Advanced," never show raw UUIDs, fix storage math. |
| 11 | **1** | **Four distinct auth-page visual identities**; inconsistent email placeholders; `/tutorials` not linked; no in-app Help. | `login.tsx` vs `verify-email.tsx:41` vs `mfa-challenge.tsx`; `app-sidebar.tsx` | Reads as unfinished; no self-serve help. **Fix:** one auth shell; add a Help entry linking tutorials. |

---

## 4. Quick wins vs. structural fixes

### Quick wins (hours–days, high impact)
- **Kill the mock dashboard** or gate it behind real data + an empty state (#1). Single highest ROI.
- **Relabel the worst jargon strings**: composer Instructions placeholder (`chat-input.tsx:668`), chat placeholder "workflow" (`common.json:89`), and the example chips (`chat-interface.tsx:139-149`) to plain language with expert terms secondary.
- **Unify plan names** (Premium/Pro) and **workflow counts** (pick one number, source it) across register/dashboard/domain-selector.
- **Fix storage math** and hide raw "Dataset ID" uuids in `file-upload.tsx`.
- **Wire or remove dead controls** (projects ⋮, empty-project "Analyze," silent downloads).
- **Make "continue free" the primary signup path**; resolve invite-required state before rendering the field.
- **Add a Help/"?"** entry in the sidebar linking the existing tutorials.
- **Stop rendering the raw reset link** on the forgot-password success screen.

### Structural fixes (weeks; need backend/design)
- **Plain-language layer over the whole product** — a consistent translation of tools/params/formats into user-goal language, with expert terms as progressive disclosure. This is the core work, not a string pass.
- **Run observability** — restore overall progress + ETA and surface the already-built `/realtime/status`, logs, and autofix state (`docs/20260310…`).
- **Pre-run cost/time estimate** at Confirm & Run.
- **Intelligent failure recovery** — transient-vs-deterministic classifier + wired `-resume`/fix-and-resume; guaranteed no raw-log leakage (`docs/20260817…`).
- **Project context model** — a single, honest "what the assistant reads" surface replacing the instructions/notes/plan ambiguity (`docs/20260918…§2.x`).
- **Onboarding that teaches the core loop** (ask → suggestion → run → results) rather than the panel internals; make the domain step optional/plain and user-scoped (the "done" flag is browser-local, `docs/20260416…`).

---

## 5. Verdict — "Is the current system easy to use for its target user?"

**No — not yet, for a bench scientist or clinician who is not a bioinformatician.** The hard engineering is real and often excellent (the chat loop works out of the box, launch errors are reassuring, the run panel is coherent and status-aware, empty states are honest), but the product consistently **speaks bioinformatics to a user who by definition cannot** — GRCh38 and FDR in the composer, GATK/DESeq2/NONMEM at signup, AWS Batch and "detach the watcher" in the tour, S3 prefixes and Galaxy UUIDs in data handling — while also **breaking trust on the first-run surfaces that matter most**: a dashboard of fabricated "Dr. Smith" data with no empty state, a signup that pushes a credit card before any value is shown, a long run with no progress bar/ETA/cost, and a failure path whose only move is to burn more hours restarting from scratch. The platform has, as the team's own 2026-09-18 audit put it, "already built the hard parts — most of them are switched off"; the decisive remaining work is **a plain-language layer and the wiring of trust/observability components that already exist**, not new capability. Until that lands, the target user will feel the tool was built for the expert they hired BioMate to replace.
