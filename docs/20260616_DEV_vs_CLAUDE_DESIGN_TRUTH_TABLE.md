# BioMate dev vs Claude design — truth table

Date: 2026-06-16
Branch: `bioc/v2-qc-audit-panel` (also reflects `integration/next-phase`)

## Scope

Compares **dev product capability today** (what really runs on
`dev-public.biomate.ai` after the latest sync) against the **Claude
design surfaces** in `reference/claude_design/`:

- `research_agents/` — the canonical research-agent surface
- `bioconductor-handoff/` — bioc tutorial design
- `design_handoff_tier0_design_pipelines/` — the 5 tier-0 drug-design demos
  (T01 bispecific, T02 in-vivo CAR-T, T03 PCSK9 base edit, T04 GLP-1
  bake-off, T05 BCMA modality triage)

Every row is sourced from a real file in the repo + cited.

---

## 1. System UI / chrome

| Design feature | File / line | Dev today | Gap |
|---|---|---|---|
| Sidebar with workspace + chat-history sections | `research_agents/Chrome.jsx:24+` | `app-sidebar.tsx` present | ✅ matches |
| Speaker pills (PLAN/WF/QC/LOOP/AGENT/FIND) | `research_agents/ChatStream.jsx:9+` | `chat-message.tsx:74-92` `SPEAKER_LABELS` + `deriveSpeaker` | ✅ matches |
| Logo on sidebar | `Chrome.jsx`, `images/biomate-logo.png` | `app-sidebar.tsx:266` `/biomate-logo.png` | ✅ matches |
| Tweaks panel (scenario / runState / panelWidth / qcHalt switches) | `research_agents/ResearchTweaks.jsx` | none — production has no Tweaks panel | ❌ **design-only debug surface; not needed in prod** |
| Tour picker overlay (`.tut-btn` → `.tour-picker` → spotlight) | `research_agents/Tour.jsx:1389+` | none in dev product | ❌ **prototype-only — no in-product onboarding tour** |

---

## 2. Chat information surface

| Design feature | File / line | Dev today | Gap |
|---|---|---|---|
| Speaker-pill colour contract | `research_agents/ChatStream.jsx` + `research-tokens.css` | `chat-message.tsx:238` + `frontend/v2/research-layout.css` | ✅ matches |
| Speaker-fold (3+ consecutive same speaker → caret) | `research_agents/ChatStream.jsx:69` `CollapsedSpeakerBlock` | `chat-progress-fold.tsx` shipped this session (K) | ✅ shipped on remote; **dev not yet synced** |
| `(why?)` anchor with hover popover | `research_agents/ChatStream.jsx:44-50` + `RESEARCH_PHASE_TRACE` | `why-anchor.tsx` + `chat-message.tsx:254` shipped this session (L) | ⚠️ shipped + tested at RTL layer; **needs chain narrator to emit `rationale_id`** before it lights up on real runs |
| 4-section popover (rationale / events / params / cost) | `research-data.js:571+` `RESEARCH_PHASE_TRACE` shape | Dev popover shows **only rationale + citation** (1 of 4 blocks) | ❌ **events + params + cost blocks NOT shipped** (Phase 3 of L plan) |
| FindingsChatCard with headline + rows + report-link | `research_agents/ChatCards.jsx:316` | `findings-card.tsx:142` | ✅ matches |
| Disambig card with candidate scores + recommended badge | `research_agents/ChatCards.jsx` | `workflow-disambiguation-card.tsx` + wired in `chat-message.tsx:480+` (Wave 1-1) | ✅ shipped on dev (verified curl earlier) |
| Pilot prompt / promotion card | `research_agents/ChatCards.jsx:15,103` `PilotPromptCard / PilotPromotionCard` | none — dev jumps straight to full run | ❌ **no pilot-vs-full UX** |
| Comparison card (Run-A vs Run-B with Δ column) | `research_agents/ChatCards.jsx:201` `ComparisonCard` | none in dev | ❌ **no run-comparison surface** |
| Section signposts (4-act arc: Understanding/Choosing/Running/Found) | implicit in design via `kind` taxonomy | `chat-message.tsx:86` `deriveSpeaker` provides equivalent acts via speaker grouping | ✅ functionally equivalent (no dedicated divider event needed) |
| Tip-card overlay (tier-0 demos' 480×120 translucent card) | `design_handoff_tier0/Tier-0 Demo Requirement.md §2` | none — tip-cards are tutorial-recording overlay only, NOT a product feature | ✅ correctly excluded from product |

---

## 3. Workflow execution ability

| Design feature | Dev today | Gap |
|---|---|---|
| Chain runner that walks `workflow_chains.steps` in data-flow order | `nextflow_executor.py` chain composer + Nextflow execution | ✅ matches |
| Per-step `workflow_id` pinning (deterministic across re-index) | shipped this session (`pin_bioc_chain_workflow_ids.py`) | ✅ 4 bioc chains pinned; 56 other chains NOT pinned (auto-resolves via cascade) |
| Live SSE chat stream (`chat_progress`, `qc_gate_triggered`, `autoloop_*`, `step_state`, `workflow_state` — 9 channels) | `nextflow_executor.py` + `frontend/server/workflow-sse.ts` | ✅ matches the design's 9-channel model |
| Auto-loop QC remediation | `experiments/admet_autoloop/`, `cyp_ddi_autoloop/`, `docking_autoloop/`, `nca_pk_autoloop/` shipped | ✅ matches |
| Disambig gate (router opens disambig when ≥2 candidates tied) | `ai_assistant.py:3515` gate + `_detect_alt_method_enumeration` (D shipped this session) | ✅ shipped on remote; **dev not yet synced** |
| Interactive Launcher (Open in RStudio / Jupyter / CellxGene) | `frontend/client/src/components/viewers/interactive-tool-launcher.tsx` (prod) + `design_handoff_tier0/InteractiveLauncher.jsx` (design has equivalent prototype) | ✅ matches |
| Pilot-then-full execution | none in dev | ❌ **design assumes pilot-promote UX; dev does single-shot runs** |
| Comparison run (A/B) | none in dev | ❌ **no A/B comparison mode** |
| Watcher (auto-attach to in-progress run + email alerts) | `watcher_attached` flag in design Tweaks; no dev implementation found | ❌ **watcher pattern not in dev** |

---

## 4. Workflow panel content

| Design feature | File / line | Dev today | Gap |
|---|---|---|---|
| Three sections: Workflow settings · Phases · After run | `bioconductor-handoff/WorkflowPanel.jsx` | `nextflow-workflow-viewer.tsx` (3-tab layout, commit `924138d00a` earlier) | ✅ matches |
| Phase cards with status badge + auto-expand active phase | design `PhaseCard.jsx` | `nextflow-workflow-viewer.tsx` phase rendering | ✅ matches |
| Run footer with single primary action (Run / Running / Run again) | design | dev viewer footer | ✅ matches |
| QC gate inline alert with "Edit" jump-to-settings | design | `nextflow-workflow-viewer.tsx` QC alert | ✅ matches |
| Parameter strip: required params surfaced before run | design | dev panel pre-run checklist | ✅ matches |
| Hard gate on Run button when required params missing | shipped this session (commit `712492acd`) | ✅ matches |
| Param origin tags (default / edited / user / autoloop) | `research-layout.css:441-443` `.tag.edited/.autoloop/.user` | css class exists in `frontend/v2/research-layout.css` but **no producer writes the tag onto params today** | ❌ **CSS ready but no data-binding** — backend params endpoint doesn't emit a `tag` field per row |
| PARAMETERS line visible-by-default in panel | tier-0 spec §1 Beat-4 | dev panel shows params under a click | ⚠️ **partial — params surface exists but not pre-expanded** |
| Step-output preview inline (image / table / sequence / vcf / annotation / structure / text / density / download) | design `Modals.jsx` `PreviewModal` + 11 viz handlers | `step-output-preview.tsx` dispatch by extension (`case 'image'`, `'html'`, `'table'`, `'sequence'`, `'vcf'`, `'annotation'`, `'structure'`, `'text'`, `'density'`, `'download'`) | ✅ all 10 types covered |
| Per-output Interactive Launcher button (.rds → RStudio, .h5ad → CellxGene) | `design_handoff_tier0/InteractiveLauncher.jsx` + `bioconductor-handoff/REQUEST_ADD_INTERACTIVE_PANEL.md` | `viewers/interactive-tool-launcher.tsx` exists | ✅ matches |

---

## 5. After-run report

| Design feature | File / line | Dev today | Gap |
|---|---|---|---|
| 7-tab structure (Findings · Outputs · Methods · Parameters · Software · Citations · QC audit) | `bioconductor-handoff/WorkflowPanel.jsx:474+` | `frontend/v2/AfterRunReport.tsx` 7-tab structure (task #40 shipped) | ✅ matches |
| Findings tab — headline + structured figures (FigBars/FigComp/FigQc) | design `FindingsChatCard` | `v2/AfterRunReport.tsx` + `FigBars/FigComposition/FigQc` (task #40); F adapter shipped this session emits `figures[]` shape | ✅ component + data-shape both shipped on remote; **dev not yet synced** |
| Outputs tab — per-file row with view + download + (optional) Open-in-RStudio | design | `v2/AfterRunReport.tsx` + Download-all (JobButton kind `download_all_zip`) | ✅ matches |
| Methods tab — IMRaD prose with versions + parameters, italics on inferred values | design | `/api/invocations/:id/methods-report` returns prose; **no italic-on-inferred distinction** in dev | ⚠️ **prose works; manifest-vs-inferred styling NOT implemented** |
| Parameters tab — phase/step/parameter/value rows | design | `v2/AfterRunReport.tsx` Params tab | ✅ matches (still needs origin-tag column per §4) |
| Software tab — exact pinned versions | design | `/api/invocations/:id/software` reads `software_versions.yml` (shipped earlier) | ✅ matches |
| Citations tab — per-domain refs | design | `/api/workflows/:name/citations` reads `qc_evidence.yaml`; bioc 3 domains populated Wave 1-2 | ✅ shipped on remote (4 domains cited); **24 qc_evidence domains have no chain consumer** — see `docs/20260616_RATIONALE_NARRATOR_HANDOFF.md` + `RATIONALE_GAP_TRACKER.md` |
| QC audit tab — 4-stat + audit log + chain-of-custody | design | `v2/AfterRunReport.tsx` `QcAuditTab` (task #50 shipped earlier; commit `8050e6c3d`) | ✅ matches |
| QC e-signature record on `qc-events` | design has compliance-lens framing | none in dev | ❌ **e-sig NOT shipped** (dropped per your instruction earlier) |
| Auto-loop remediation card (was→now param diff) | design `AutoLoop.jsx` | dev auto-loop panels in 4 domains (ADMET/CYP-DDI/Docking/NCA-PK) | ✅ matches |
| `Download report` exports DOCX / MD / LaTeX | design | dev exports DOCX + MD; LaTeX not confirmed | ⚠️ **DOCX + MD yes, LaTeX status unconfirmed** |

---

## 6. The 5 tier-0 drug-design demos — what actually runs

The tier-0 design spec (`design_handoff_tier0_design_pipelines/Tier-0 Demo Requirement.md`) defines 5 advanced drug-discovery demos. For each, the design has a complete prototype scenario (per-step tape + tip-card script). What dev can actually execute:

| Demo | Underlying workflow in dev | Executable today? |
|---|---|---|
| T01 — Bispecific antibody (PD-1 × VEGF) | `nf-core-workflows/modules/biomate-ai-tools/bispecific_format_triage/main.nf` (4-phase pipeline, ~140 lines) | ✅ workflow exists |
| T02 — In-vivo CAR-T (CD19 for DLBCL with LNP) | `biomate-ai-tools/in_vivo_cart_codesign/` | ✅ workflow exists |
| T03 — In-vivo base-edit (PCSK9) | `biomate-ai-tools/in_vivo_base_edit_design/` | ✅ workflow exists |
| T04 — GLP-1 modality bake-off (MASH) | `biomate-ai-tools/glp1_modality_bakeoff/` | ✅ workflow exists |
| T05 — Modality triage (BCMA) | `biomate-ai-tools/modality_triage/` | ✅ workflow exists |

**However**: none of these are in `workflow_chains` — they're top-level
nf-core sub-workflows. The router will hit them directly (single
workflow_type='nextflow'), not via a curated multi-step chain.
**Citations**: none of the 5 tier-0 workflow domains
(`bispecific_format_triage` etc.) have entries in `qc_evidence.yaml`,
so the Citations tab is **empty** for tier-0 runs.

---

## 7. What dev CAN do that the design doesn't show

| Dev capability | Design has? |
|---|---|
| Real AWS Batch execution of nf-core workflows | design is simulated (scenario tape) |
| Real Lago billing per invocation + plan-limit gating | design has commented-out cost block only |
| Multi-tenant auth + email verification + admin notifications | design is single-user prototype |
| Real chat session persistence across machines (PostgreSQL `chat_sessions`) | design uses localStorage |
| LLM-generated IND §2.6.1 narrative (`_llm_narrative()` shipped Apr 2026) | design doesn't model regulatory authoring |
| Real R/Bioconductor execution in BioMate `run_code` | design fakes outputs |
| Auto-loop with real param remediation (4 domains shipped) | design has remediation card but no real param mutation |
| Per-user adapter retraining queue (regulatory_llm Lane B3) | design doesn't model this |
| 2,455 indexed workflows + BGE dense retrieval routing | design uses 4 hardcoded scenario tapes |
| 60 curated chains in DB | design has ~4 hardcoded chains (rnaseq, drugscreen, variant, cryosparc) |

---

## 8. Critical gaps still to fill (prioritized)

| # | Gap | Impact | Effort |
|---|---|---|---|
| 1 | **Chain narrator emit `rationale_id`** so (why?) anchor lights up on real runs | High — L feature is invisible until this lands | 1 BE-day (handoff doc shipped) |
| 2 | **Param origin tags producer** — backend writes `tag: default/edited/user/autoloop` per param | Medium — CSS exists, frontend will render once data flows | 2 BE-days |
| 3 | **Citations for 5 tier-0 workflow domains** + 13 true-gap chain domains | Medium — Citations tab empty for ~37 chains | per-domain scientific-lead curation; `RATIONALE_GAP_TRACKER.md` ready |
| 4 | **Pilot-then-full UX** with promotion card + countdown | Medium — design's key cost-saving pattern, absent in dev | ~3 FE-days |
| 5 | **Comparison run mode** (A vs B with Δ column) | Medium — competitive differentiator | ~5 FE-days |
| 6 | **(why?) popover blocks 2/3/4** — events + params + cost | Medium — current popover is 1/4 of the design | ~3 BE-days + 2 FE-days |
| 7 | **Methods tab italic-on-inferred** styling | Low — visual nicety | ~1 day |
| 8 | **Watcher / email alerts** for long-running runs | Medium — present in design Tweaks, absent in product | ~3 BE+FE-days |
| 9 | **Tour onboarding** in product (`.tut-btn` + `tour-picker`) | Low — currently only in prototype; ship if users ask | ~1 week |
| 10 | **`workflow_id` pinning** extended to remaining 56 non-bioc chains | Low — auto-cascade works today, pinning is reproducibility insurance | 1 day (script extension) |

---

## Sign-off

**Dev has** everything in §1, most of §2 (folds + DisambigCard wired but
not on dev until sync), §3 (one-shot runs), §4 (panel structure +
hard gate + viz dispatch), §5 (7-tab report skeleton + 4 cited domains).

**Dev does NOT have** pilot-then-full, A/B comparison run, watcher,
in-product tour, all-4-block (why?) popover, param origin tags wired
end-to-end, full Citations coverage on non-bioc chains.

**The 5 tier-0 drug-design demos** have executable nf-core workflows
in dev, but they are top-level workflows (not chains) with no
qc_evidence citations and no curated rationale_registry rows — so the
tutorial-grade demo experience (chain → 7-tab report with citations +
(why?) anchors) is bioc-only today.
