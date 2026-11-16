# 2026-11-15 — Models module UX clarity plan

**Goal:** make the Models module easy to follow for a non-expert user. Triggered by a real session where the user had to ask "what is this?" / "why is this?" about **four separate elements** in one sitting — the strongest possible signal the module over-exposes internals and under-explains intent.

**Status:** Reviewed (PM + HCI, §6b) → **P0 IMPLEMENTED & verified locally** (tsc exit 0, full vitest 4016 passed / 0 failed). P1.1 verb-rename rejected; P1.2/P2 deferred & telemetry-gated. Changes are local/uncommitted — not yet synced to DEV.

### P0 implemented (2026-11-15)
Copy (en + zh, i18n parity + no-English-leak tests pass):
- `code_intro` de-jargoned (no `run_code` / `Galaxy Interactive Tools`); `no_model_chemical` reframed goal+action; `tab_purpose_*` goal-framed; `registered_artifacts` → "Your trained models"; `registry_empty`/`registry_load_error` humanized.
- Tab label `tab_molecular` "Molecular learning" → **"Molecular models"** (route value `molecular` unchanged; `models.test.tsx` assertion updated).
- New keys: `panel_subtitle` (module orientation line — the P0.5 win), `runs_manage_hint`, `code_sandbox_boundary`.
Server messages: `routes.ts` 502 registry error humanized; `model-training-registration.ts` 503/invalid-response de-jargoned; cross-references in `galaxy-assistant.ts` (×2) + `cold-start-demo-catalog.ts` updated "Molecular learning → Rounds" → "Molecular models → Rounds" (incident #2 root).
Components: `models-panel.tsx` renders `panel_subtitle` + a Run-Manager `runs_manage_hint` footer under training runs; `code-sandbox-path.tsx` shows `code_sandbox_boundary` in the result.
Not done: P0.6 telemetry (no existing hook found — flagged for follow-up); full navigate-button on the chemical empty-state (copy + correct tab-name shipped; button is a small follow-up).

### P0.7 — User feedback follow-up (2026-11-15, same session)
Direct user pushback on two P0 boundary-hints — correctly identifying that honestly *labeling* an over-complicated design still leaves it over-complicated. Fixed the design, not the label:
- **Run management brought into the Train tab.** Added inline **Rename** + **Delete** on each run in the Train-tab runs list (`RunManageControls` in `models-panel.tsx`), so users no longer need to discover a separate Run Manager. Delete is two-step (confirm) and destructive-safe; both invalidate the train-track query on success. Removed the "Rename or delete runs in the Run Manager" footer hint (now redundant). Backend: `DELETE /api/workflows/runs/:id` already existed; **rename** required extending `legacyRunUpdateSchema` (a security-reviewed owner-gated whitelist) with **`workflowName` only** — a bounded display label (1–200 chars), never a path/status/ownership/launch field — with a matching assertion in `legacy-run-access.test.ts`. The Train-tab run label *is* `run.workflowName`, so the rename shows immediately.
- **Sandbox dead-end framing removed.** Deleted the "Exploratory run — won't appear under Your trained models" hint (`code_sandbox_boundary`) that read as "why bother." Sandbox outputs are still returned and downloadable; the `code_intro` ("quick exploration") conveys purpose without discouraging. Open follow-up: a "Save outputs to project" action would make the sandbox persist results (addresses the deeper "is it worth it" concern) — not built this pass.
tsc clean; full vitest 4016 pass / 0 fail.

---

## 1. Evidence (what actually confused a real user)

In one session the user asked about, verbatim:
1. **"Central model registry is unavailable. Please retry."** — a raw 502 backend error shown as primary content in *Registered training artifacts*. No indication it's transient, no retry affordance beyond a generic "Refresh versions", no plain-language meaning.
2. **"No chemical inference model is registered for this account. Train a molecular property model on Molecular learning, or open a model you registered."** — an empty state the user read as an error. The cross-reference ("on Molecular learning") assumes the user maps our tab names to actions.
3. **"Training runs can not be deleted or updated?"** — the training-runs list offers *Register / Check versions / Follow in Run Manager* but no delete/rename; deletion actually lives in a different surface (Run Manager). The capability boundary is invisible.
4. **"…same run_code engine as chat — Galaxy Interactive Tools are not used. why do you write this"** — internal implementation jargon (`run_code`, `Galaxy Interactive Tools`) leaked into user copy.

These are not isolated string bugs; they share one root cause (below).

## 2. Current information architecture

**Surface A — Sidebar Models panel (`/models` → `ModelsPanel`)**, 3 visible tabs (`MODELS_TRACKS=["train","library","molecular"]`; `adapt` hidden via `HOUSE_STYLE_HIDDEN`):
- **Train** — path toggle **No-code** (`TrainingLauncher family="general"` + `TrainingRuns` list) / **Code** (`CodeSandboxPath` → `POST /api/code/run`).
- **Model library** — `library` catalog table + `OwnedTrainingRegistry` (*Registered training artifacts*, `GET /api/model-training-versions`) + **Run a model** inference (Structure / Genomic / Chemical families).
- **Molecular learning** — `TrainingLauncher family="molecular"` **+** `RoundsSection` (DMTA campaign: create/start/stop/propose).

**Surface B — Cold-start Models module** (dashboard card → 3 track tabs): **Train** (3 seeds) / **Adapt** (2 seeds) / **Optimise** (2 seeds), each seeding a chat draft + sample data.

## 3. Root-cause diagnosis (why it's hard to follow)

1. **Vocabulary is split-brained across the two surfaces.** Cold-start speaks **Train / Adapt / Optimise** (verbs, user intents). The panel speaks **Train / Model library / Molecular learning** (nouns, internal structure) and *hides* Adapt. A user who clicks "Optimise" in cold-start is told to go to "Molecular learning → Rounds" — a term they never saw. The two mental models don't line up.
2. **Duplicated "Train a model".** A training launcher appears in **both** the Train tab (general) and the Molecular learning tab (molecular). Nothing tells the user which to use; they look like two different features.
3. **Internals surfaced as content.** Raw backend errors (`502` registry), engine names (`run_code`), and dead infra (`Galaxy Interactive Tools`) are shown verbatim. The panel explains *how it's built*, not *what to do*.
4. **Invisible capability boundaries.** "You can register but not deploy", "runs are read-only here but deletable in Run Manager", "Code runs are not tracked training runs" — all true, none stated at the point of confusion.
5. **Empty states read as errors.** "No chemical inference model is registered" looks like a failure, not a "here's your next step".
6. **Density without progressive disclosure.** Three tabs, each with 2–3 sub-modes (No-code/Code, 3 inference families, Rounds, registry), plus ~12 model types — all flat, all at once.

## 4. Proposed changes

### P0 — Clarity fixes (low risk, high impact, no IA change)
- **P0.1 Humanize the registry error.** Replace the raw 502 passthrough with: *"Couldn't reach the model registry just now — this is usually temporary. Retry in a moment."* + keep a **Retry** button (not just "Refresh versions"). Distinguish transient (502) from "not set up yet" (503) with different copy. Files: `owned-training-registry.tsx`, `routes.ts:5942` message, `common.json`.
- **P0.2 Reframe empty states as next-steps, not errors.** `no_model_chemical` → style as guidance (info, not alert) and make "Train a molecular property model" a **button/link** that switches to the right tab, not prose the user must decode. Files: Run-a-model component, `common.json`.
- **P0.3 De-jargon the Code sandbox copy.** `models.code_intro` → *"Runs your script once in a sandbox and returns its output and files — not an interactive notebook."* Drop `run_code` and `Galaxy Interactive Tools` from user-facing text (keep them in code comments). Files: `common.json`.
- **P0.4 State capability boundaries inline.** On the training-runs list: a one-line hint *"Manage, rename or delete runs in the Run Manager →"* linking out. On Code: *"Sandbox runs are exploratory — they don't appear under Registered artifacts."* Files: `models-panel.tsx` TrainingRuns, `code-sandbox-path.tsx`.

### P1 — Vocabulary + dedup (medium risk, needs review)
- **P1.1 Unify the verbs.** Align the panel tabs and cold-start tracks to the **same three intents**. Proposal: panel tabs become **Train · Adapt · Optimise** (mirroring cold-start), with "Model library" folded into Train (as "your models") and Rounds living under Optimise. *HCI/PM to validate naming; this is the central decision.*
- **P1.2 Remove the duplicate launcher.** One "Train a model" entry point that asks "what kind?" (tabular / molecular / LLM / …) rather than two near-identical launchers in two tabs.
- **P1.3 One-line purpose header per tab** written as a user goal ("Teach a model your assay data", "Run a design-make-test loop"), replacing the current internal descriptions.

### P2 — Structural (larger, stage after P0/P1 land)
- **P2.1 Single Models entry that routes by intent** so the sidebar panel and the cold-start module are two doors to the *same* three-intent flow, not two different maps.
- **P2.2 Progressive disclosure** of the ~12 model types (group by task; collapse advanced).

## 5. Implementation order
1. Land **P0.1–P0.4** (copy + small affordances) — ships clarity immediately, reversible, no IA churn. Verify: `tsc`, `vitest` (models suites), browser spot-check on DEV.
2. Review-gated **P1.1** naming decision → then P1.2/P1.3.
3. P2 as a follow-up doc.

## 6. Out of scope / constraints
- Do **not** un-hide the Adapt *panel* tab (`HOUSE_STYLE_HIDDEN`) or restore `/drug-discovery-cro` (prior decisions).
- Do **not** change routing behavior (Optimise→DMTA deep-link, Train→ml_training) — this is presentation only.
- Keep honest framing (no invented scores; real API errors still surface, just humanized).

## 6b. Review synthesis & decisions (PM + HCI, 2026-11-15)

Both reviews agreed P0 is correctly sized and closes all four incidents; they converged on these decisions:

**Implement now (P0, reconciled):**
- **P0.1** Humanize registry error — neutral state + **Try again** button (forces refetch, not cached refresh); keep "Refresh versions" out of the error state. (First confirm 502 vs 503 both actually fire before authoring two copies.)
- **P0.2** Empty-vs-error as a **reusable pattern**: empty = names the absent thing + first-action button, neutral/`info` role (a11y: stops screen readers announcing an empty state as an error); error = failure + recovery, `alert` role. Rewrite `no_model_chemical` to goal+action; CTA **navigates** (switch-tab), drops "inference/registered/registry" and the tab-name cross-reference.
- **P0.3** De-jargon Code copy: *"Run a script once and get its output and files back. For quick exploration — not a live notebook."*
- **P0.4** Co-locate capability boundaries: muted footer *"Rename or delete runs in Run Manager →"*; sandbox result *"Exploratory run — won't appear under Your trained models."*; add *why* runs are read-only here.
- **P0.5 (promoted from P1.3, highest-leverage):** per-tab goal-framed purpose header + module-level "what you can do here" orientation (panel lacks what cold-start has).
- **Safe renames (both endorse):** tab **"Molecular learning" → "Molecular models"** (route value `molecular` unchanged → deep-links safe; MUST update `models.test.tsx` label assertion); **"Registered training artifacts"/registry → "Your trained models"**.

**Held / deferred:**
- **P1.1 verb rename → REJECTED.** Keep "Model library" first-class (management/discovery surface; nouns carry discoverability). Do not label a tab "Adapt" while `HOUSE_STYLE_HIDDEN` (over-promising dead affordance).
- **P1.2 unified launcher, P2.1 single intent entry, P2.2 disclosure → P2**, gated on telemetry (P0.6) — these are builds, not copy.
- **P0.6 telemetry** (PM): instrument the four states + CTA clicks. Recommended prerequisite for P2; flagged — deferred unless an existing analytics hook exists.
- **P2.3:** reconcile Adapt routing (`reinvent4_lead_design` vs expected `reinvent4_finetune_rl`, per verification doc) BEFORE any "Adapt" vocabulary.

**Definition of done (acceptance tests, per incident):** no raw 502 in rendered copy; no `run_code`/`Galaxy Interactive Tools` in rendered copy; chemical empty-state exposes an actionable button and uses `info` not `alert` role; read-only-runs boundary stated inline with a Run Manager link.

## 7. Open questions for reviewers (resolved above)
- PM: is **Train/Adapt/Optimise** the right top-level for the *panel* too, or does "Model library" need to stay a first-class tab (discoverability of registered/integrated models)?
- HCI: for P0.2, switch-tab-on-click vs inline-expand — which lowers load more? And is "registry" a word users understand, or do we need "your trained models"?
- Both: is the dual-surface (sidebar panel + cold-start) itself the problem (P2.1), or acceptable if vocabulary is unified (P1.1)?
