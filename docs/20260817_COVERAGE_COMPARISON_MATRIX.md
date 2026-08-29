# BioMate Coverage / Capability Comparison Matrix

**Date:** 2026-08-17
**Track:** `coverage` — evidence-only. **No new benchmark runs, no LLM API calls, no EC2, no spend.** Every cell is grounded in an artifact that already exists in this repo (or, for competitors, in their published primary source). Nothing here is a fresh measurement.
**Purpose:** an honest systems × capability-dimensions matrix comparing BioMate against bio/agent co-scientists, general coding agents, and the 8 frontier LLMs in our RealBio leaderboard — with the source for every claim and an explicit list of what we **cannot** claim without executing a run.

> **Honesty contract (this repo's team has been burned by over-claiming).** BioMate cells trace to a real file. Competitor cells are labelled **"per their paper"** or **"inferred"**; unknown ⇒ **"unknown — not published"**, never a silent ✗. Where a prior BioMate survey already flagged a "first/only/no-competitor" claim as unverified, that flag is carried forward here, not laundered. Relative dates converted to absolute.

Legend: **✓** documented/verified in-repo (BioMate) or per primary source (competitor) · **partial** = exists but limited / not wired end-to-end · **✗** = documented-absent by a primary source · **n/a** = out of that system's category · **?** = unknown, not published.

---

## 0. The comparison set and its three tiers

Comparing these three tiers on one axis would be unfair by construction, so the matrix keeps them separate and the narrative reads each on its own terms.

1. **Bio / agent co-scientists** — Biomni (Stanford, Science 2025), ChemCrow (Nat Mach Intell 2024), Coscientist (Boiko et al., Nature 2023), Google "AI co-scientist" (arXiv 2502.18864), Robin / FutureHouse (Nature 2026). These are the true *category* peers.
2. **General coding agents** — Claude Code, OpenAI Codex. These write and run *arbitrary* code; they are not bioinformatics products, so most biology-specific cells are `n/a` (they can do it only by writing it from scratch, un-curated, un-QC'd).
3. **Frontier LLMs** — the 8 in our RealBio leaderboard: **Claude Opus 5, Gemini 3.1 Pro, GPT-5.6, Qwen3.8-Max, GLM-5.2, GPT-5.6-luna, Kimi K3, DeepSeek V4.** For these we have *actual RealBio scores* (`evaluation/datasets/public_export/leaderboard.md`), so their row is quantitative, not narrative — but note the scores are for **routing / autofix / param / wf-gen / protocol tasks with the catalog handed to them**, i.e. a RAG-fair condition, NOT the same thing as *executing* a pipeline.

---

## 1. The coverage matrix (systems × capability dimensions)

Rows are capability dimensions; footnote markers (¹²³…) give the source per row and are collected in §4.

### 1a. Bio / agent co-scientists + BioMate (the category comparison)

| Capability dimension | **BioMate** | Biomni | ChemCrow | Coscientist | Google AI co-scientist | Robin / FutureHouse |
|---|---|---|---|---|---|---|
| Biological-domain breadth ¹ | ✓ multi-domain, **2,455 wf / 34 domains** (public figure; live DB snapshot 4,057 wf / 39 domains) | ✓ multi-domain, **25 biomedical subfields** (per paper) | ✗ chemistry only (per paper) | ✗ chemistry only (per paper) | ✓ broad (hypothesis-gen, any field; per paper) | ✓ biomedical, multi-agent (1 demonstrated end-to-end case: ripasudil/dry-AMD; per paper) |
| Executes real *validated* pipelines (vs advice-only / self-written code) ² | ✓ **validated-pipeline orchestration** (Nextflow/nf-core, Galaxy, Bioconductor) | partial — runs **LLM-*generated* code** (not validated community pipelines; per paper) | partial — runs 18 **pre-built validated tools** + **robotic wet-lab** (per paper) | partial — defined tool set + **robotic wet-lab** (per paper) | ✗ **no execution** — hypothesis/reasoning only (per paper) | partial — Finch **writes+runs its own** Jupyter/Python; PaperQA2/Crow = literature RAG (per paper) |
| Nextflow/nf-core · Galaxy · Bioconductor integration ³ | ✓ **all three** | ✗ not documented (verified none in repo) | ✗ (chemistry) | ✗ (chemistry) | ✗ not documented | ✗ none (verified: Finch may import a Bioconductor library, no pipeline orchestration) |
| Curated tool/workflow catalog (size) ⁴ | ✓ **2,455 wf** + ~12k tools indexed; plus 60+ verified search resources | ✓ ~150 tools + retrieval DB (per paper) | ✓ 18 tools (per paper) | ✓ small defined set (per paper) | n/a (no tool catalog — reasoning) | ✓ agent suite (Crow/Falcon/Finch); catalog size not published |
| AWS-Batch / cloud pipeline execution ⁵ | ✓ **24/24 drug-dev wf on AWS Batch**; GPU queue (GROMACS/AMBER) | ? unknown — not published as managed cloud pipeline exec | robotic lab (RoboRXN), not cloud pipelines | robotic lab (Opentrons), not cloud pipelines | n/a | ? not published |
| QC / auto-loop remediation ⁶ | ✓ **auto-loop 96/96 unit tests**; 96.4% converge ≤3 iter; ADMET single-shot 40%→100% (but SSE live-wiring incomplete — see §3) | ? not documented | ✗ not documented (human-gated single runs) | partial — closed-loop opt, **oracle-fed, not per-cycle wet-lab** | Elo/tournament loop on *hypotheses* (not pipeline QC) | ? not documented |
| Wet-lab / closed-loop DBTL ⁷ | partial — **designed, round-1 ready-to-order (~$15–25k), NOT yet synthesized** | single demo, not systematic (per paper) | ✓ **real** RoboRXN synthesis, human-gated (per paper) | ✓ **real** Opentrons synthesis, human-gated (per paper) | ✗ humans validate separately | ✗ "AI engine for biology, NOT an automated lab" (per paper) |
| Param extraction from NL ⁸ | ✓ rule+LLM hybrid; RealBio param F1 measured on LLMs, BioMate product row not yet scored (see §5) | partial — 0.708 F1 in n=40 pilot (per our leaderboard) | ? | ? | ? | ? |
| Workflow generation ⁹ | ✓ NextflowComposer (generate-if-no-match) | partial — code-gen is its core mode (per paper) | ✗ | ✗ | ✗ (hypotheses, not workflows) | partial — Finch writes analysis code |
| Protocol / threshold reasoning ¹⁰ | ✓ protocol-aware QC profiles (ffpe, membrane_protein…), evidence-graded GOLD/SILVER/BRONZE, hERG ≤10 µM ICH-S7B gate | ? not documented | ? | ? | ? | ? |
| Calibration / uncertainty ¹¹ | partial — Bayesian surrogate GPs per objective; scIB two-objective / over-correction detection (🟡 idealized-input maturity) | ? | ? | ? | tournament/Elo ranking of hypotheses (per paper) | ? |
| Cost / billing awareness ¹² | ✓ **real** billing router (LLM tokens, vCPU/GPU-hours, S3, transfer); tier + quota enforcement | ? not published | ? | ? | ? | hosted platform (pricing not a capability claim) |
| Governance / audit / 21 CFR Part 11 ¹³ | ✓ evidence-graded audit trail (our brief scores 1.0 vs 0.0 baselines — *our own* measurement, see caveat) | ✗ not documented | ✗ not documented | ✗ not documented | ✗ not documented | ✗ not documented |

### 1b. General coding agents + frontier LLMs (different category — read the caveats)

| Capability dimension | **BioMate** | Claude Code / Codex (coding agents) | Frontier LLMs (8-model RealBio row) |
|---|---|---|---|
| Curated bio catalog ⁴ | ✓ 2,455 wf | ✗ none built-in (would write from scratch) | ✗ none (parametric knowledge only) |
| Routing to correct workflow ¹⁴ | ✓ **0.965 [0.930, 0.983]** engine-free (C2, n=200) | ? not measured on RealBio | **bare (C0): 0.345–0.615; +catalog (C1): 0.80–0.96** (Opus 5 C1 0.960; GPT-5.6 0.530→0.930) |
| Executes real validated pipelines ² | ✓ | partial — runs *any* code but un-curated, un-QC'd, un-audited | ✗ (advice only) |
| Autofix / failure-classify ¹⁴ | ? product row not scored | ? | **0.77–0.88** (Gemini 3.1 0.880 top; n=100) |
| Param F1 ¹⁴ | ? product row not scored | ? | **0.621–0.757** (Opus 5 0.757 top; n=170) |
| Protocol QC ¹⁴ | ✓ encoded rules (product row not scored) | ? | **0.33–0.63** (Gemini 3.1 0.630 top; most ≈ random floor; n=100) |
| Governance / audit ¹³ | ✓ | ✗ | ✗ |

---

## 2. Honest narrative — where BioMate leads, where it doesn't, what's unknowable

### 2a. Where BioMate genuinely leads (each with the file)

1. **Breadth of an *executable, curated* catalog under validated-pipeline orchestration.** BioMate is multi-domain (2,455 wf / 34 domains publicly; 4,057 wf / 39 domains in the live DB snapshot) *and* actually orchestrates validated Nextflow/nf-core + Galaxy + Bioconductor pipelines. Two independent verification passes (`docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md`) found **no** other surveyed system integrates that workflow ecosystem — the closest peer, Robin, orchestrates *reasoning* agents and self-written code, not validated pipelines, and explicitly disclaims being an automated lab. This is a *category* difference, not a score difference. (Sources: `CLAUDE.md`; `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md`; live `backend/database/galaxy_ai_tools.db`.)

2. **Engine-free deterministic routing at 0.965.** On the RealBio routing task (n=200), BioMate's curated retrieval with **no LLM in the loop** reaches **0.965 [0.930, 0.983]** — statistically on par with the best frontier LLM *handed the same public catalog* (Claude Opus 5 C1 = 0.960), and ~+35–40 pp above every bare LLM (C0 0.345–0.615). The honest framing: this measures the *value of the curated catalog + deterministic retrieval*, not model intelligence. (Source: `evaluation/datasets/public_export/leaderboard.md` + `leaderboard.csv`.)

3. **ADMET / QC auto-loop remediation as a moat.** The auto-loop passes 96/96 unit tests, converges ≤3 iterations on 96.4% of 125 drug-discovery scenarios, and lifts ADMET single-shot 40% → 100% within 3 iterations — with an evidence-graded guard that only tunes RISK_STRATIFICATION gates (hERG ≤10 µM, ICH S7B) and never overrides REGULATORY criteria. No surveyed co-scientist documents a comparable per-pipeline QC-remediation loop. (Sources: `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`; `docs/20260417_ADMET_AUTOLOOP_ARCHITECTURE.md`; `business/case_studies/scientific_reports/04_qc_governance_autoloop_SCIENTIFIC.md`.) **Caveat (§3):** the live SSE wiring for ADMET auto-loop is documented as incomplete (`docs/20260614_AUTOLOOP_SSE_SILENT_ON_ADMET.md`) — the architecture + tests are real; the end-to-end live event stream is not fully deployed.

4. **Real cost/billing awareness.** BioMate ships a live billing router tracking LLM tokens, vCPU/GPU-hours, S3, transfer, with tier + quota enforcement — a capability none of the co-scientist papers document. (Sources: `backend/lib/galaxy/ai/billing/api/billing_router.py`; `docs/20260727_TIER_MODEL_DECISION.md`.)

### 2b. Where competitors lead, or we can't tell

- **Coscientist & ChemCrow lead on *real* wet-lab execution.** Both ran physical synthesis end-to-end (Pd cross-couplings / DEET-class chemistry) on robotic platforms (Opentrons / RoboRXN), human-gated. BioMate's wet-lab / closed-loop DBTL is **designed and round-1 ready-to-order (~$15–25k) but not yet synthesized** — on real chemistry execution they clearly lead. (Sources: their papers per `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md`; BioMate status per `docs/20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md`.)
- **Biomni leads on the autofix pilot.** In our own leaderboard, Biomni's agent scaffold scores **autofix 0.95 (n=40 pilot)** — above every bare-model row. BioMate's product row is *not scored* on autofix, so we cannot claim a win here. Biomni also matches BioMate on breadth (25 subfields) and is a peer-reviewed Science 2025 system; its retrieval + code-gen architecture is a genuine contribution. (Source: `evaluation/datasets/public_export/leaderboard.md`.)
- **Robin leads on literature-driven discovery + multi-agent orchestration.** Its Crow/Falcon/Finch + tournament-judge suite drove one demonstrated end-to-end discovery (ripasudil / dry-AMD, Nature 2026). BioMate's literature layer (60+ search resources) has *unmeasured* LitQA2 recall (`docs/20260810_SEARCH_RESOURCE_CAPABILITY_KB.md`), so we cannot claim parity on literature-driven hypothesis generation.
- **Google AI co-scientist leads on automated hypothesis generation** (Gemini multi-agent Generation/Reflection/Ranking/Evolution + tournament self-improvement) — a different category (no execution) that BioMate does not target head-on.

### 2c. Genuinely unknowable from existing evidence

- Whether BioMate's *curated + enriched* catalog beats "LLM + raw catalog names" on the **C1→C2 delta for tasks other than routing** — only routing has a BioMate product number; autofix/param/wf-gen/protocol product rows are unrun.
- Competitors' performance on the RealBio tasks beyond Biomni's n=40 pilot — nobody else has run our items.
- Any **per-token / per-second / per-dollar** cost comparison across systems — we have BioMate's billing *instrumentation*, not a measured cross-system cost table.

---

## 3. Known BioMate gaps carried forward (do not launder these)

From prior surveys, stated plainly so this doc can't be quoted as pure marketing:

- **ADMET auto-loop live SSE is a no-op in one code path** (`docs/20260614_AUTOLOOP_SSE_SILENT_ON_ADMET.md`) — architecture + unit tests real; live end-to-end event stream not fully deployed.
- **Closed-loop MPO module** passes 3/3 composition tests but is **not wired to product** (no API endpoint / executor node / UI) (`docs/20260811_DRUGDISCOVERY_SOTA_SURVEY_AND_GAP_FIXES.md`).
- **REINVENT4 not integrated** — generation slot uses RDKit BRICS enumeration, not a trained RL generator (same doc).
- **No in-vivo data generation, no patient-genotype/EHR data, no DEL analysis** — data-partnership boundaries, not software (`docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`).
- **Wet-lab DBTL not operational** — handoff files exist, round 1 designed but unsynthesized (`docs/20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md`).
- **Over-claim flags carried forward:** the moat briefing's "no competitor has this metric / only BioMate" language (`docs/20260403_COMPETITIVE_MOAT_BRIEFING.md`) and the audit-trail "1.0 vs 0.0" figure in the QC brief are **our own** framing/measurements, not independent head-to-head benchmarks — cite as positioning, not proof.

---

## 4. What we CANNOT claim without executing a real run

This section is load-bearing. **None of the following may be stated as a number in any external doc until a run produces it.**

1. **Token / latency / dollar cost per system.** We have BioMate's billing instrumentation, not a measured cross-system cost table. No "BioMate is Nx cheaper than Biomni/GPT" claim.
2. **Full-Biomni coverage / head-to-head.** Biomni appears in our leaderboard only via an **n=40 pilot** (routing C1 0.950, autofix 0.95, param 0.708). We cannot claim full-task parity or a win across the 660-item RealBio suite — Biomni has not been run on it.
3. **BioMate product rows for autofix, param_prefill, workflow_generation, protocol_thresholds.** Only **routing (0.965)** has a committed BioMate product number. Every other BioMate cell in the LLM-comparison table is *unrun* — do not fill from the LLM rows.
4. **Any competitor's RealBio score** other than Biomni's pilot — no competitor benchmark numbers may be invented.
5. **Wet-lab / DBTL outcomes** — round 1 is designed, not synthesized; no permeability/SPR results exist to report.
6. **Live ADMET auto-loop SSE end-to-end** — the 40%→100% figure is from the architecture's unit tests; a live deployed run has not been captured.
7. **Cross-domain routing on the full live DB (4,057 wf / 39 domains)** — the 0.965 number is on the 200-item public export against public targets, not the enriched live DB.

---

## 5. Sources actually used (file paths)

Primary evidence (BioMate):
- `evaluation/datasets/public_export/leaderboard.md` — RealBio leaderboard (routing C2 0.965, 8-model rows, Biomni pilot)
- `evaluation/datasets/public_export/leaderboard.csv` — machine-readable scores
- `evaluation/datasets/public_export/MANIFEST.json` — task definitions / item counts
- `CLAUDE.md` — workflow DB = 2,455 wf / 34 domains; drug_discovery counts
- `backend/database/galaxy_ai_tools.db` — live snapshot: 4,057 wf, 39 domains (queried, not rebuilt)
- `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md` — verified competitor scope matrix + primary-source citations
- `docs/20260804_REALBIO_BENCHMARK_AND_LLM_COMPARISON.md` — fair-comparison methodology (C0/C1/C2)
- `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` — coverage, auto-loop 96/96, PBPK/BOIN/ADMET numbers, explicit data gaps
- `docs/20260417_ADMET_AUTOLOOP_ARCHITECTURE.md` — hERG gate thresholds, 24 unit tests
- `docs/20260403_COMPETITIVE_MOAT_BRIEFING.md` — moat layers, competitor threat assessment (over-claim flags carried forward)
- `docs/20260501_COMPETITIVE_COMPARISON_STRATEGY.md` — IND narrative vs Certara/AutoIND/Yseop; TDC ADMET numbers
- `docs/20260811_DRUGDISCOVERY_SOTA_SURVEY_AND_GAP_FIXES.md` — closed-loop MPO not-wired, REINVENT4 absent
- `docs/20260810_SEARCH_RESOURCE_CAPABILITY_KB.md` — 60+ search resources; LitQA2 recall unmeasured
- `docs/20260727_CAPABILITY_WHITEPAPER.md` — 14-domain Bioconductor framing, 🟡 maturity honesty
- `docs/20260727_TIER_MODEL_DECISION.md` — tier / quota model
- `backend/lib/galaxy/ai/billing/api/billing_router.py` — live billing endpoints
- `docs/20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md` — closed-loop round-1 ready-to-order, ~$15–25k, unsynthesized
- `docs/20260614_AUTOLOOP_SSE_SILENT_ON_ADMET.md` — ADMET auto-loop live SSE incomplete
- `business/case_studies/scientific_reports/04_qc_governance_autoloop_SCIENTIFIC.md` — auto-loop convergence, CiPA 58%→8%, audit 1.0 vs 0.0

Competitor evidence (primary sources, via our verification run `wbeeoa07o`, as cited in `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md`):
- Biomni — Science 2025 (10.1126/science.adz4351) + github.com/snap-stanford/biomni
- Coscientist — Nature 2023 (s41586-023-06792-0)
- ChemCrow — Nat Mach Intell 2024 (s42256-024-00832-8)
- Google AI co-scientist — arXiv 2502.18864
- Robin / FutureHouse — Nature 2026 (s41586-026-10652-y) + arXiv 2505.13400 + FutureHouse.org

---

### Footnote index (row → source)
¹ `CLAUDE.md`; `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md` §3; live DB. ² same §2/§3. ³ same §3 (whitespace rows). ⁴ `CLAUDE.md` + `docs/20260810_SEARCH_RESOURCE_CAPABILITY_KB.md`; competitors per §3. ⁵ `docs/20260418_DRUG_DEV_BATCH_WORKFLOWS_24_OF_24_PASSING.md`. ⁶ `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` + `business/case_studies/scientific_reports/04_qc_governance_autoloop_SCIENTIFIC.md`; live gap `docs/20260614_AUTOLOOP_SSE_SILENT_ON_ADMET.md`. ⁷ `docs/20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md`; competitors §3/§4. ⁸ `evaluation/.../leaderboard.md`. ⁹ `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md`. ¹⁰ `docs/20260403_COMPETITIVE_MOAT_BRIEFING.md` + `docs/20260417_ADMET_AUTOLOOP_ARCHITECTURE.md`. ¹¹ `docs/20260811_DRUGDISCOVERY_SOTA_SURVEY_AND_GAP_FIXES.md` + `docs/20260727_CAPABILITY_WHITEPAPER.md`. ¹² `backend/lib/galaxy/ai/billing/api/billing_router.py` + `docs/20260727_TIER_MODEL_DECISION.md`. ¹³ `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md` §5 + QC brief (our own measurement — caveat §3). ¹⁴ `evaluation/datasets/public_export/leaderboard.md` + `leaderboard.csv`.
