# Demo use-cases — readiness audit + fix plan (2026-10-29)

Three demo use cases set as highest priority (2026-10-29): **(1) drug-dev DBTL loop
(dry-dry + dry-wet)**, **(2) multi-agent fast search**, **(3) public-model fine-tuning**,
plus the ongoing dataset-panel UI work. This doc = the synthesized readiness from three
parallel audits + the fix plan. Living doc — update as fixes land.

## Legend
CODE = fixable in-repo (doing autonomously). OPS = dev env/AWS, cannot do from this
machine (flag for user). INTENTIONAL = deliberately as-is, do NOT change.

---

## 1. Drug-dev DBTL loop
**Verdict:** dry-dry single-gate loop WORKS (needs toggle ON); full campaign + dry-wet PARTIAL.
Cyclic-peptide loop is a research harness, NOT a product demo → demo with **small molecules**.

Demo flow (lowest risk): Mode-1 single-gate on dev —
- Docking: erlotinib vs EGFR (PDB 1M17), exhaustiveness=4 → gate HALT at −5.2 (thr −7.0)
  → auto-remediate exhaustiveness 4→16, box 20→25Å → rerun → −8.4 PASS.
- OR ADMET terfenadine (known hERG blocker) → hERG gate HALT → remediate logp/mw → pass.
  (Gate-fire proven live: run d0ff684b, docs/20261004_AUTOLOOP_LIVE_PROOF.md.)

Gaps:
- **#1 CODE** — auto-loop self-correct toggle defaults OFF (`nextflow-workflow-viewer.tsx`
  autoloopMap `{}` ~:1400; locked unless profile.autoloop===true ~:3627). Out-of-box a halt
  gate just PAUSES for a human; the autonomous loop never fires. FIX: autoloop-capable profiles (profile.autoloop===true) now default the toggle ON
  (commit 3a7464d46). [STATUS: DONE]
- **#6 CODE** — demo harnesses (demo-01/05/06.demo.ts) use `demo_*@biomate.test` which bounce
  + degrade the account; must use fixture lifeifei163361@163.com. [STATUS: DONE demo-01/05/06]
- **#2 OPS** — `RUN_STATE_STORE=redis` on dev UNVERIFIED. Without it, autoloop SSE is
  cross-worker-blind and Batch runs can orphan (status:running forever).
  → `docker exec biomate-galaxy-dev printenv RUN_STATE_STORE` must == `redis` before demo.
- **#3 OPS** — SSE is environment-coupled; run the demo entirely on dev-public.biomate.ai
  (not a localhost browser against dev Galaxy) or events drop.
- **#4 INTENTIONAL** — CRO Library route + IND nav hidden (project_billing_hidden). Dry-wet
  demo goes via campaign REST API, not nav. Do NOT un-hide without the user's say.
- **#5 (known)** — dry-wet Make/Test is SimAssaySource (simulated); narrate as "simulated wet
  return" via a pre-staged assay CSV → `POST /ingest-assay` → GP refit → new auto-proposal.
- **#8 (known)** — QC events not durably persisted per run; show the gate LIVE, never by
  reopening history (reopen shows "all passed" fallback).

---

## 2. Multi-agent fast search
**Verdict:** engine LIVE + correct (parallel asyncio.gather fan-out over PubMed/EuropePMC/
Semantic Scholar/OpenAlex, grounded citations). PMID confabulation + Gemini tool-firing both
FIXED. Dev runs gpt-5.6-luna; research path is a direct endpoint call (backbone-independent).
The gap is pure PRESENTATION — it doesn't LOOK multi-agent.

Demo flow: a pure literature/evidence question (no "run/analyze" verbs, no pasted data).
Example: "Summarize the current published evidence on whether KRAS G12C inhibitors improve
overall survival in NSCLC, with citations to the key trials."

Gaps:
- **G1 CODE (highest)** — parallel fan-out invisible in chat (the parallel Plan-Checklist
  surface is dormant in an un-promoted sandbox). FIX (cheapest): emit a per-sub-query status/
  AGENT SSE event so the chat shows the concurrent source searches. [STATUS: PARTIAL — status line now names the 4 parallel sources (commit); full fan-out animation = design decision, deferred]
- **G2 CODE** — citations panel collapsed by default (benchmark-evidence.tsx ~:487). FIX:
  default-expand on research turns. [STATUS: DONE]
- **G3 CODE** — chat re-synthesizes the research answer (prose can drift from the grounded
  set); structured citations panel stays faithful. FIX: preserve the evidence-boundary note /
  pass grounded answer through more directly. [STATUS: consider]
- **G4 (demo scripting)** — route the demo query as a pure literature question to avoid
  workflow_generation misrouting.
- **G5/G6 (out of scope)** — no single turn fans out to catalog too; hierarchical Pattern
  Router dormant (governs workflow-gen, not search) — do NOT enable for this demo.

---

## 3. Public-model fine-tuning
**Verdict:** backend engine real (ml_training/: LoRA/QLoRA, TRL DPO/GRPO, chemprop) but NOT
demo-ready E2E. EPERM `/data` bug RESOLVED+verified live (adapt/retrain returns succeeded).

Demo flow (asked): pick public base model → attach data → launch FT → fine-tuned model as a
first-class object with "Built from" lineage. Only launch path today = a chat message
("fine-tune SmolLM2 on my instruction data") → route_ml_training_result → training workflow
card → Confirm&Run → /api/nextflow/execute → AWS Batch.

Gaps:
- **#1 OPS (top blocker)** — `ML_TRAINING_ROUTING` flag OFF on dev (routing.py ~:205); not in
  any committed env. The chat launch route is DEAD until set. → set `ML_TRAINING_ROUTING=1` on
  biomate-galaxy-dev + restart. Until then, fine-tune cannot be triggered at all.
- **#2 CODE** — no UI affordance to launch a fine-tune (Train track + Supersede/Use-in-run are
  read-only; model-case `tune_on_our_data` page not mounted). Only chat free-text works.
- **#3 CODE** — fine-tuned result does not round-trip into a /api/models object with populated
  Built-from lineage (trainingRunId/datasetVersion).
- **#4/#5 OPS** — GPU path not wired (chemprop_train.nf is process_low/CPU); ECR
  ml-training/trl-training :latest images push status unverified (`aws ecr describe-images`).
- **#7 CODE (hygiene)** — two latent `parents[5]/data` fallbacks (training_job.py ~:49,
  models_inference.py ~:638) — same bug class as the resolved EPERM; shadowed by overrides
  today. Migrate to `_data_root.data_root()`. [STATUS: DEFERRED — hygiene only, shadowed by env overrides, not demo-blocking; FT demo is ops-gated on #1 regardless]

NOTE: FT demo is OPS-gated (#1) regardless of UI work — building the launch UI is only useful
once the flag is confirmed on dev. So do the safe hygiene fix (#7) now; defer the UI build
(#2/#3) until #1 is confirmed, to avoid building against a dead route.

---

## Autonomous execution order (code fixes)
1. [done] MAS G2 — default-expand citations.
2. Loop #1 — autoloop default-on for autoloop-capable profiles.
3. MAS G1 — per-sub-query parallel fan-out narration (investigate feasibility first).
4. Loop #6 — demo harness fixture emails.
5. FT #7 — data_root hygiene (test module import per pre-sync step 3).
6. tsc + vitest gate → batch sync → live verify each demo flow on dev.

## OPS checklist for the user (cannot do from this machine)
- [ ] `ML_TRAINING_ROUTING=1` on biomate-galaxy-dev (+ restart) — unblocks fine-tune route.
- [ ] `RUN_STATE_STORE=redis` confirmed on biomate-galaxy-dev — unblocks autoloop SSE.
- [ ] ECR `ml-training:latest` + `trl-training:latest` pushed (`aws ecr describe-images`).
- [ ] Run the demos on dev-public.biomate.ai (not localhost) so SSE delivers.


## Verification results (live dev, 2026-10-29)
- **Multi-agent search: ✅ VERIFIED PASS** on dev — parallel-source status line, cited
  answer with [N], citations panel expanded by default (G2), real DOI + evidence boundary,
  no workflow card. First answer ~54s.
- **DBTL loop: blocked by a separate bug, now FIXED.** The ADMET terfenadine run died at
  Nextflow launch (~17s) — `smiles_list` reached the pipeline as a bare SMILES, not a
  JSON-array string, aborting the session at JSON parse. NOT redis/SSE. Fixed:
  `_normalize_smiles_list_param` at the pre-launch chokepoint (commit). The autoloop
  default-on fix (gap #1) remains UNVERIFIED e2e until the ADMET run can launch — re-run
  PART B (terfenadine) after this backend deploy. run_id of the failed attempt:
  60a3e843-0d44-4bb8-8445-e8fe44ec7aef.

## Loop autoloop-trigger root cause (2026-10-29, after launch fix)
Re-run under the launch fix: terfenadine ADMET now COMPLETES (run 486bb38d, 159s, 2
processes) — but produced `qc_gates: []` / `qc_report: null`, so no HALT gate → the
autoloop had no trigger (autoloop-default-on fix still unexercised, not disproven).

Root cause chain (code-confirmed, read-only):
- `qc_evidence.yaml:123` — **admet_standard HALTS at hERG IC50 ≤ 10 µM**. Terfenadine
  IC50 ≈ 0.01 µM → should HALT.
- `qc_trace_monitor.py:1090 infer_qc_profile()` auto-binds **admet_standard** for any
  path containing "admet" (line 1107-1108), and the comment there explicitly notes
  admet_standard is "the ONLY profile carrying the cardiotox (hERG) gate".
- BUT the verify run explicitly requested a **"cipa/hERG" profile**, which overrode the
  inference and produced no halt (loop-audit gap #7: "a request for admet_standard ran
  under a different profile"). → the halt the config promises never fired.

Decisive experiment (in flight): re-run terfenadine under **admet_standard** (no "cipa"
override). Expected: hERG HALT fires → autoloop (admet_standard is autoloop:true) auto-
remediates without a manual toggle → the autoloop-default-on fix is finally exercised.
If admet_standard STILL yields `qc_gates: []`, the gate evaluation isn't wired for this
ADMET execution path (deeper) — trace qc_trace_monitor wiring in the Node→Galaxy execute.

### Demo-path recommendation
- **ADMET loop**: works once the demo binds **admet_standard** (do NOT request "cipa").
- **Docking loop (erlotinib/EGFR, demo-05)**: the loop audit called this "the tightest
  gate→remediate→rerun story" with a clear HALT (−5.2 vs −7.0) — likely the cleaner demo
  path; verify it binds its halt gate too. Pick one as the canonical loop demo.

## DEFINITIVE loop finding (2026-10-29, admet_standard run 82c1245a)
Re-run under **admet_standard** (no "cipa"): produced **qc_gates=2 blocking** — hERG
IC50 0.01<1.0 µM FAIL + DILI high FAIL (GOLD rationale). So:
- The QC gate EVALUATION is correctly wired; the earlier `qc_gates:[]` was caused by the
  demo goal forcing the **"cipa" profile**, which overrode inference. FIX FOR DEMO: don't
  name cipa — let inference bind admet_standard (or pick it in the panel).
- **Autoloop still does NOT engage**, two independent downstream causes:
  (a) **Delivery**: the blocking gate lands in the completed run record, NOT as a live
      mid-run `qc_gate_triggered` halt SSE event — ADMET is single-phase and finishes in
      the same step, so the client-side autoloop (which only triggers on a live event)
      never fires. Levers: confirm RUN_STATE_STORE=redis on dev AND/OR make the ADMET
      executor emit a mid-run halt event (not only at completion).
  (b) **Actionability**: terfenadine hERG/DILI are REGULATORY, non-tunable failures →
      they route to the regulatory-action card ("structural optimisation required"), NOT
      the was→now tunable-param auto-remediate+rerun path. A tunable gate is required to
      demo auto-rerun.

### FINAL demo-path recommendation for the loop
Use the **DOCKING loop (erlotinib/EGFR, demo-05)**: its halt is a TUNABLE param
(exhaustiveness 4→16, box 20→25 Å) → the was→now remediation + auto-rerun path the
autoloop-default-on fix targets. ADMET is the wrong vehicle for the *auto-remediation*
loop (its safety gates are non-tunable regulatory halts) — though it's an excellent
"gate fires, blocks progression" safety story on its own.
Open item before the docking loop demo: verify docking ALSO surfaces its halt as a LIVE
mid-run event (the delivery gap (a) may be general to single-phase workflows) — i.e.
confirm RUN_STATE_STORE=redis and that the executor emits a live qc_gate_triggered.

### Autoloop-default-on fix (commit 3a7464d4) status
Shipped + deployed; UNVERIFIED end-to-end because no live TUNABLE halt gate has yet
fired on dev to trigger it. Verify via the docking loop once (a) is confirmed.
