# Target-Identification Tutorial Deck — Redesign Handoff for Claude Design

**Date:** 2026-11-01
**For:** Claude Design — regenerate the `target-identification` walkthrough deck (short `v4` + `edu`, EN + 中文) on the data-centroid v2 / `_v4.js` tutorial system.
**Why now:** The target-ID capability was substantially reworked (2026-10-31 → 2026-11-01). The current deck **mis-states the core ranking mechanic** and omits several new, honest, demo-worthy capabilities. This is a narrative + results-screen re-conception, not a copy edit, so it needs a design pass. **Claude Code will NOT hand-patch it**; it will re-apply narration + render once the new deck lands.

Format follows the prior handoffs (`20261023_DRUGDEV_TUTORIAL_INFOFLOW_FOR_CLAUDE_DESIGN.md`). Recording contract (below) is non-negotiable.

Authoritative sources (read these, do not guess): `backend/lib/galaxy/webapps/galaxy/api/target_id_api.py`; `backend/lib/galaxy/ai/target_id/{__init__,types,arbiter,orchestrator,channels,data_channels,client_data,analysis_outputs,validation,modality}.py`; docs `20261021_TARGETID_FUSION_VS_OPENTARGETS_BENCHMARK.md`, `20261101_TARGETID_{MODALITY_SELECTOR,FIXES_AND_VERIFICATION,TEMPORAL_GOLD}.md`. Current deck: `reference/claude_design/tutorials_v3/target-identification/targetid walkthrough v4 - proposal.zh.html` (+ `.html`), narration `.../narration/target-identification-v4.zh.md`, fixture `.../tutorials_v3/_ui/runs-instruments4.js`.

---

## 1. How target-ID works NOW (ground the deck in this)

**Endpoint:** `POST /api/target-id/identify` (+ new `GET /api/target-id/status`). MCP `identify_targets` proxies it.

**Channels** (`default_channels`, data_channels.py:261):
- **genetics_ot** — Open Targets Platform GraphQL, live, disease-association score. Also pulls Ensembl id so every row gets an evidence link.
- **ppi_string** — STRING PPI proximity, seeded from OT's top genes; live-only.
- **llm_reasoned** — frontier-LLM structured assessment; **on by default**; `evidence_kind = "model_judgment"`, no per-target citation.
- Optional/conditional: pathway_comembership (needs `TARGET_ID_GMT_PATH`), TableChannel, **client/hospital-data channels**, frozen_fm (CAPTAIN/scGPT, probationary).

**THE RANKING MECHANIC — this is the correction that drives the redesign:**
- **Default = OpenTargets-PRIMARY.** When genetics_ot is present, the list is **ranked BY the Open Targets score alone** (`score = prim[t]`, arbiter.py:167, sorted :175). The network + LLM channels **do NOT change the rank**. They only (a) set the confidence **tier** (corroboration), (b) flag **conflict**, (c) supply **provenance/evidence links**.
- **Multi-channel harmonic-sum fusion of all three scores happens ONLY in the non-default `integrated` mode** (arbiter.py:178-207), which is opt-in and which the benchmark shows **does NOT beat Open Targets alone** (`20261021` doc: 0/17 win).
- Honest value proposition: **"a well-engineered Open Targets query + corroboration tiers + conflict/veto + provenance UX"**, NOT "our fusion out-ranks Open Targets." (Stated in `__init__.py:6-13`, `orchestrator.py:46-48`.)
- Tiers (OT-primary mode): `corroborated` (≥2 strong channels agree, one must be OT) / `nominated` (1 strong) / `supporting` / `vetoed`.

**NEW since the deck was authored (all honest, candidates to showcase):**
1. **Per-target evidence links** (`evidence_links`, types.py:45): every ranked target links, per channel, to its Open Targets evidence page (`platform.opentargets.org/evidence/<ENSG>/<EFO>`), STRING network, etc. LLM row = "model judgment, no citation". Server paths never exposed. **Strong provenance story — should be visible in the results screen.**
2. **2-stage orchestrator** (no-seed → STRING/pathway seeded from the primary channel's top genes); ranking stays OT-primary so expansion genes can't dilute.
3. **Hospital/client-data channel** (`client_data.py`, 6 adapters) + **`ranking_mode`**: `auto` (OT-primary, default) vs `integrated` (client data can move the rank). Reliability weight 0.8. Associational, not causal.
4. **Auto-build hospital evidence from a completed run** (DESeq2/edgeR/limma/Cox/recurrence/dependency outputs → client table; confined to `TARGET_ID_RUN_OUTPUT_ROOT`).
5. **Modality (drug-type) selector** — opt-in `suggest_modality`; rule-based, precedent-free; 4 options (small_molecule / biologic / macrocycle_peptide / other); **always `validated:false`**, carries a guidance note.
6. **Citation-existence check** on the LLM channel — PMIDs/DOIs checked against NCBI/Crossref; "existence is not support"; ungrounded claims refused.
7. **Offline snapshots** (`TARGET_ID_OFFLINE` / `TARGET_ID_SNAPSHOT_DIR`), snapshot results date-labelled.
8. **Time-split (temporal) gold** exists but is **too small to support any novel-target claim** — recall-only framing stands.

**Deployment note:** none of this is synced to dev yet (backend + route + tests only). The deck should depict the capability; live capture waits for a sync.

**Response shape a demo would see** (`OrchestratorResult.to_dict()` + route additions):
```
{ query, arbiter:"harmonic_sum",
  channels_run:["genetics_ot","ppi_string","llm_reasoned"], channel_errors, plan,
  ranking:{ mode:"primary_channel"|"weighted_harmonic_sum", primary_channel:"genetics_ot",
            evidence_value_type, seed_source, n_seed_genes },
  channel_provenance:{...},
  targets:[ {rank,target,score,tier,n_fired,fired_channels,conflict,note,
             per_channel_z:{channel:val}, evidence_links:{channel:{kind,url,label}}} ],
  n_targets_total,
  validation_plan?:{gene:{rank,tier,validation:{druggability|expression|structure_docking|perturbation:[wf]}}},
  modality_suggestions?:[{target,ranked_options:[{modality,score}],top,confidence,rationale,sources,
                          uses_drug_precedent:false, validated:false, note}] }
```

---

## 2. What the CURRENT deck shows, and what's wrong

8 scenes, journey 数据→流程→结果→报告, example = psoriasis (MONDO_0005083), data hard-coded in `_ui/runs-instruments4.js` (run id `tid`).

**Four must-fix defects:**

- **D1 (mechanic — load-bearing).** Scenes 01/02/04/05 repeatedly say the three channel scores are **harmonic-sum fused into the ranking** and that "a target must have >1 channel to rank high" (Scene 02 "· 融合" crop: `三个得分用调和求和融合…`; Scene 04 beat 2 `融合成一个排序：三个得分合成一个`; Phase B step `融合通道 / harmonic-sum arbiter`). **This is the non-default `integrated` mode and contradicts the honest default (OT-primary; fusion does not beat OT).** The fixture's method strings assert the same.
- **D2 (example data inconsistent with OT-primary).** Scene 06 shows Score 0.94 while genetics = 0.91 (a blended number above the OT score) and orders IL12B → TYK2 (genetics 0.74) → IL17A (genetics 0.82) — TYK2 out-ranks IL17A despite a **lower** genetics score. That ordering can only come from fusion. Under OT-primary the Score column must equal the OT/genetics score and the list must sort by it.
- **D3 (modality overstated).** Modality is shown as a confident automatic "按药物形式分流 / Route by modality" **pipeline step** and a settled results column. Reality: opt-in, `validated:false`, weak biologic recall, **never ranks macrocycle-peptide first** (so IL17A "可选环肽" overstates).
- **D4 (unsourced number).** Scene 06 beat 4 "IL12B 和 TYK2 也出现在 8 种自身免疫病中 4 种的前 10 名" is marked `kind:'measured'` but **no committed artifact backs it** (the multidisease benchmark ran 17 IO cancers and its headline is the fusion-vs-OT negative). Must be sourced or softened to qualitative (drop `measured`).

**Keep (already correct/honest):** disease→standard-id resolution (Scene 03); tier names 多通道印证/单通道提名 + "≥2 strong channels"; Scene 07 "recall of marketed-drug targets → trustworthy; does NOT claim novel discovery" disclaimer (**keep verbatim**); gather-then-rank 2-stage ordering.

---

## 3. The deck we want — redesign spec (8 scenes preserved, recording contract intact)

Re-tell the story as **"Open Targets, made auditable"**: rank by the strongest evidence (Open Targets genetics), corroborate with network + literature-reasoning, attach a clickable evidence trail to every target, offer an *unvalidated* modality hint, and honestly scope it to **recall, not discovery.**

- **Scene 01 · 问题** — keep the psoriasis hook. Narration: BioMate gathers evidence from Open Targets genetics, the STRING network, and frontier-LLM literature reasoning, then **ranks by the strongest channel and corroborates with the rest** (drop "fuse into one list").
- **Scene 02 · 三类证据** — keep the 3-channel concept, but the "融合" crop becomes **"排序 + 印证"**: *rank by Open Targets; network + LLM set the confidence tier and provide the evidence trail; they don't change the order.* State plainly that **fusing all three does not beat Open Targets** — that's why BioMate keeps OT as the spine.
- **Scene 03 · 带入数据** — unchanged (disease → MONDO/EFO id, param origins). Accurate.
- **Scene 04 · 工作流** — Phase A: three channels in parallel. Phase B: **rank by Open Targets → assign tier (corroborated needs ≥2 strong, one being OT) → attach evidence links**. Replace the "融合" crop with a **"排序"** crop: *"名次直接采用 Open Targets 的关联得分（OT 内部已用调和求和聚合它自己的证据类型）。"* Modality becomes an **optional, unvalidated suggestion** beat, not a routing gate.
- **Scene 05 · 运行** — steps complete; "rank waits for all three channels to report, then tiers + links." Keep "4 corroborated / 2 nominated of 6" **only if** the re-scored example (below) still yields that split.
- **Scene 06 · 结果 (the central rework)** — results table **sorted by the Open Targets score**, Score column **= the genetics score**. Columns: Score (=OT), Tier, Genetics(OT), Network(STRING), LLM-reasoned, **Evidence links** (NEW: per row, "OT 证据页 ↗ · STRING ↗"), Marketed precedent, **Modality (建议·未验证)**. Pick OT-primary-consistent example numbers (see §4). Hero line follows the new order. Showcase the **clickable per-target evidence trail** — it's the strongest honest upgrade.
- **Scene 07 · 正确解读** — keep the recall-not-novel disclaimer verbatim. Add two honest beats: (a) **LLM citation-existence guardrail** — literature claims whose PMIDs/DOIs don't resolve are refused ("existence ≠ support"); (b) modality suggestion is a **rule-based, precedent-free starting point, `validated:false`**. Optionally one line on the **hospital-data channel / `integrated` mode** ("add your own analysis as a 4th channel; it can move the ranking only in the explicit integrated mode").
- **Scene 08 · 报告** — generic report scene; unchanged.

### Honesty constraints (binding — do not violate)
1. **OT-primary is the default; fusion does NOT beat Open Targets.** Never present a blended score as the rank, or imply the multi-channel fusion out-performs OT.
2. **Recall, not discovery.** The system recovers marketed-drug targets (why it's trustworthy); it does not claim novel targets.
3. **Modality = guidance only, `validated:false`, opt-in.** Never a confident routing decision; never rank macrocycle-peptide first.
4. **LLM channel = model judgment, no per-target citation**; earns its place via the gate; ungrounded citations refused.
5. **Hospital/client data is associational, not causal**, and only moves the rank in explicit `integrated` mode.
6. **No unsourced "measured" numbers** (the 4/8 claim).

---

## 4. Correct example data (OT-primary-consistent) for the fixture

Replace the `runs-instruments4.js` `R` array so **Score = genetics(OT) and rows sort by it descending**. Suggested honest shape (psoriasis; keep marketed precedents, which are real):

| Rank | Gene | Score(=OT genetics) | Network | LLM | Tier | Precedent | Modality (未验证) |
|---|---|---|---|---|---|---|---|
| 1 | IL23A | 0.92 | 0.74 | 0.86 | corroborated | risankizumab, guselkumab | biologic |
| 2 | IL12B | 0.90 | 0.78 | 0.88 | corroborated | ustekinumab | biologic |
| 3 | IL17A | 0.86 | 0.69 | 0.80 | corroborated | secukinumab, ixekizumab | biologic |
| 4 | TNF | 0.83 | 0.71 | 0.77 | corroborated | adalimumab, infliximab | biologic |
| 5 | TYK2 | 0.74 | 0.63 | 0.85 | nominated | deucravacitinib | small_molecule |
| 6 | IL17F | 0.70 | 0.58 | 0.66 | nominated | bimekizumab | biologic |

(Design/Claude Code should verify these OT scores against a live Open Targets query for psoriasis before locking them; the point is **Score == OT, sorted by OT, tiers from corroboration** — not the exact decimals. Keeps the "4 corroborated / 2 nominated" split. Drop IL17A's "可选环肽". Modality column labelled 建议·未验证.) For the cross-disease beat (D4): either cite a committed artifact or soften to qualitative ("IL23/IL12 and TYK2 recur across several autoimmune indications") with no hard count and no `measured` tag.

---

## 5. Recording contract (MUST preserve — a change here desyncs the video)
- **8 `<section class="scene">`, same order**; do not add/remove scenes.
- **`data-seconds` per scene** present and one-per-scene (the fitter rewrites these to narration; keep the attribute).
- Keep `_v4.js` globals working: `window.__timeline`, `window.__sceneDurations`, `window.__total`, `window.__done`; `?rec=1` autoplay; `.scene.active` toggling; 1920×1080; headless-Chrome-safe; local assets + Google Fonts only.
- EN and 中文 keep identical scene structure; only caption language differs.
- Deliver as `target-identification/targetid walkthrough v4 - proposal.html` + `.zh.html` (and the `edu` long variants), matching the other decks' `_v4.js/_v4.css/_ui/assets` wiring. Narration stays `narration/target-identification-v4.zh.md` (tabular: 起点 · 画面 · 旁白 · 字数/窗口; ~4 中文字/秒).

**After design delivers:** Claude Code re-applies the Chinese language-polish pass (natural/professional, within time windows) and renders the zh short video, uploading to `biomate_drive:biomate_tutorial_recordings/1101_refined/`.
