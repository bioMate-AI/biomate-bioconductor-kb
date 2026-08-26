# Supplementary Table S4 | Capability comparison across autonomous biomedical / AI-scientist systems

This is the competitive capability matrix underlying the positioning claims of §1.2 and §1.3. It is distinct from Suppl. Table S2, which maps internal-provenance claims to committed source files; S4 is the *capability comparison* against external systems.

**Evidence rule (honesty contract).** Competitor cells were verified against **primary sources** (Science, Nature, Nature Machine Intelligence, Nature Biomedical Engineering, arXiv, official GitHub repositories) via a dedicated deep-research pass (survey date 2026-07-18 for the orchestration-agent class; scope-comparison compiled 2026-08-04). **A cell marked "not documented" means the capability was not established from a primary source — it is *not* a claim that the capability is absent** ("not documented ≠ absent"). Competitors are credited where they genuinely lead. Sources: `docs/20260718_LLM_TRAINING_DEEP_SURVEY.md` is the primary source for the orchestration-agent-class survey (2026-07-18: BioMaster, NEXUS, BioMedAgent, GalaxyMCP, AutoIND, BioWorkflow, FlowAgent, CRISPR-GPT, open-LLM lab orchestration); `docs/20260804_AI_SCIENTIST_SCOPE_COMPARISON.md` is the source for the AI-scientist-class rows only (primary-source citations per cell captured in deep-research runs `wbeeoa07o`, `wbcko0njf`).

## Core matrix

*Layout note: the first column ("Dimension") is a row-label column, not a data column; the matrix compares six systems (≤6 data columns, house-style compliant). Per-cell primary sources are keyed to the "Primary sources" block below; a reviewer can trace each "not documented" cell to its source there without needing the internal deep-research run IDs (`wbeeoa07o`, `wbcko0njf`), which are the audit provenance for the survey pass, not per-cell citations.*

| Dimension | **BioMate** | Biomni (Stanford) | Google AI Co-Scientist | Coscientist (CMU) | ChemCrow | The AI Scientist (Sakana) |
|---|---|---|---|---|---|---|
| Domain breadth | Multi-domain (4,057 workflows / 39 domains) | Multi-domain — 25 biomedical subfields | Broad (hypothesis-gen, any field) | Chemistry only | Chemistry only | Computational ML only |
| Execution mode | **Validated-pipeline orchestration** | LLM-*generated code* (full system privileges) | None (hypothesis only) | Robotic wet-lab chemistry | Robotic wet-lab chemistry | LLM-*generated* ML code |
| Runs validated community tools (vs self-written code) | Yes (validated workflows) | Uses tools **and** generates own code | n/a | Yes (defined tool set) | Yes — 18 pre-built validated tools | No (writes own code) |
| ⭐ Nextflow/nf-core · Galaxy · Bioconductor integration | **Yes — all three** | Not documented (verified: none in repo) | Not documented | No (chemistry) | No (chemistry) | No (ML) |
| Cross-specialty orchestration | Yes (target→…→IND chain) | Multi-domain via code-gen, single agent | Multi-agent (reasoning agents) | Single-domain | Single-domain | Single-domain |
| Closed-loop QC / self-healing | Yes (QC gates, auto-loop, AutoFix) | Not documented | Elo/tournament loop on *hypotheses* | Closed-loop opt (oracle-fed) | Not documented | Iterative ML-experiment loop |
| ⭐ Governance / audit / 21 CFR Part 11 | **Yes (evidence-graded, audit trail)** | Not documented | Not documented | Not documented | Not documented | Not documented |
| Wet-lab execution | Designed (dry↔wet loop; not operational) | Single demo | Human validates separately | Real (Opentrons), human-gated | Real (RoboRXN), human-gated | None (computational) |
| Maturity | Deployed production platform | Research release + web UI (Science 2025) | Research system (trusted-tester) | Research prototype (Nature 2023) | Research prototype (Nat Mach Intell 2024) | Research prototype (open repo) |

## Research/reasoning-agent suites (verification pass 2)

| Dimension | Robin / FutureHouse suite | STELLA | BioMedAgent | TxAgent / ToolUniverse (Harvard) |
|---|---|---|---|---|
| Domain breadth | Biomedical (multi-agent; one demonstrated end-to-end case: ripasudil / dry-AMD) | Biomedical/scientific (self-evolving) | Biomedical data analysis | Therapeutic reasoning / precision medicine over a **211-tool** biomedical tool ecosystem (ToolUniverse) |
| Execution mode | Cross-specialty orchestration of *reasoning* agents; humans do all wet-lab | Self-generated code (Dev Agent) | Chains tools into executable workflows (77% reported) | LLM multi-step **tool-calling** over a curated tool/API set; no pipeline generation or execution |
| Runs validated community tools vs self-written code | Finch **writes+runs its own** Jupyter/Python; PaperQA2/Crow/Falcon = literature RAG | Self-generated code | Tool-chaining into executable workflows | **Yes** — invokes a defined set of 211 curated tools/APIs (does not write pipelines) |
| ⭐ Nextflow/nf-core · Galaxy · Bioconductor | None (generated code may import a Bioconductor *library*, but no pipeline orchestration) | None | None | None (tool/API wrappers, not pipeline orchestration) |
| Cross-specialty orchestration | Yes — multi-agent (Crow/Falcon + Finch + Tournament Judge) | Multi-agent (self-evolving) | Multi-agent | Multi-step reasoning within therapeutics (interactions, contraindications, dosing); single agent |
| Closed-loop QC / self-healing | Not documented | Not documented | Not documented | Not documented |
| ⭐ Governance / audit / 21 CFR Part 11 | Not documented | Not documented | Not documented | Not documented |
| Wet-lab execution | No — humans execute ("AI engine for biology, NOT an automated lab") | No | No | No (computational reasoning) |
| Maturity | Hosted agent platform; Nature 2026 | Research prototype (2025) | Nat Biomed Eng 2026 (s41551-026-01634-6) | Research release; arXiv 2503.10970 (2025) + open repos (mims-harvard/ToolUniverse, /TxAgent) |

## Coverage & breadth — scope and unit (not a raw-count race)

*Coverage is compared on two axes — domain **scope** and the **unit** of coverage — because the systems are not counted in the same units. BioMate's unit is a **validated multi-step workflow** (a containerised pipeline); the tool-ecosystem systems count **single tools/functions/APIs**. A workflow is not a tool, so raw counts are not directly comparable; the meaningful comparison is domain scope plus the unit-appropriate count. Numbers below are from each system's primary source.*

| System | Domain scope | Unit of coverage | Count | Source |
|---|---|---|---|---|
| **BioMate** | **39 biological domains** (omics → drug-discovery → cryo-EM → clinical pharmacology) | validated multi-step **workflows** | **4,057** | `galaxy_ai_tools.db` snapshot 2026-08-17 (verified) |
| Biomni | 25 biomedical domains | tools + software + databases (+ LLM code-gen) | **150+ tools · 100+ software · 59 databases** | Science 2025; HAI Stanford |
| TxAgent / ToolUniverse | therapeutic reasoning / precision medicine | tools / APIs | **211 tools** | arXiv 2503.10970 |
| ChemCrow | chemistry | expert-designed tools | **18 tools** | Nat Mach Intell 2024 |
| Coscientist | chemistry | defined robotic + tool set | small defined set | Nature 2023 |
| Google AI Co-Scientist | any field (hypothesis only) | — (no execution) | n/a | arXiv 2502.18864 |
| The AI Scientist | ML only | self-written code | n/a | arXiv 2408.06292 |

**Reading (breadth-first, not "biggest pile").** BioMate's distinguishing coverage properties are (a) the **widest biological-domain scope** — 39 domains spanning multi-omics, drug discovery, structural biology, and clinical pharmacology — versus chemistry-only (ChemCrow, Coscientist), ML-only (The AI Scientist), or Biomni's 25 domains; and (b) the **unit is a validated, containerised pipeline**, not a raw tool the model must compose (the same distinction the core-matrix execution-mode row draws). BioMate's per-domain spread from the snapshot: transcriptomics ≈1,693, genomics ≈750, epigenomics ≈262, proteomics ≈182, variant-calling ≈181, drug-discovery ≈122, single-cell ≈95, and others. **We explicitly do not claim "more tools than Biomni/ToolUniverse"** — a workflow and a tool are different units; the claim is *domain scope + validated-pipeline granularity*, not raw count.

## Where competitors genuinely lead (credited)

- **Biomni** has the broadest biomedical scope (25 subfields), comparable to BioMate on breadth; its retrieval + code-gen architecture is a published Science 2025 contribution.
- **ChemCrow & Coscientist** ran physical wet-lab synthesis end-to-end (DEET; organocatalysts / Pd cross-couplings); on real-world *chemistry execution* they lead — BioMate's wet-lab loop is only designed.
- **Google AI Co-Scientist** is a sophisticated multi-agent hypothesis engine (Gemini; Generation/Reflection/Ranking/Evolution + tournament self-improvement) — a genuine advance in automated hypothesis generation.
- **Robin / FutureHouse** is the closest analogue to BioMate's cross-specialty-orchestration thesis, but it orchestrates *reasoning* agents (literature synthesis + self-written data-analysis code), not validated production pipelines, and does not run wet-lab or integrate the workflow ecosystem.

## The two rows only BioMate fills (verified in two independent passes)

1. **Workflow-ecosystem integration** — no verified system integrates Nextflow/nf-core, Galaxy, or Bioconductor pipeline orchestration.
2. **Governance / audit / regulatory (21 CFR Part 11)** — no verified system documents it.

Plus the distinct **execution mode**: BioMate orchestrates *validated production pipelines*; every other verified system generates its own code, runs robotic chemistry, or only reasons. Stated as a category difference, not a superiority-across-all-axes claim (see the credited-leads list above).

## Shared-benchmark comparisons (no re-runs required)

Where a system already *publishes* results on a benchmark BioMate also ran, a fair comparison needs no re-execution of either system — we simply place the two committed numbers side by side. Cross-referencing each system's published benchmarks against BioMate's coverage:

| Competitor (published) | Shared benchmark | Competitor's published score | BioMate (committed) |
|---|---|---|---|
| Biomni-R0-32B (Stanford) | BiomniEval1 | 66.9% (per-task avg) | **71.1%** (macro-avg) |
| Biomni Lab | BixBench / Phylo Verified-50 | 88.7% | **92.0%** (46/50) |
| Biomni agent scaffold | RealBio cross-domain routing | 0.950 (38/40) | **0.965** [0.930, 0.983] |
| Biomni / FutureHouse (PaperQA2) | LAB-Bench | per-subtask model baselines (paper) | **72.7%** overall |

- **Biomni** — the general-biomedical-agent class member nearest BioMate — overlaps BioMate on four published benchmarks, giving direct no-re-run comparisons (all above; BioMate leads on each measured head-to-head, at parity on the routing scaffold).
- **Google's AI co-scientist** publishes on **GPQA** and **bespoke clinical-discovery tasks** (drug repurposing, novel target ID, antimicrobial-resistance mechanisms). BioMate has run **none** of these (verified: no GPQA/HLE run in the benchmark record), and GPQA is a multiple-choice knowledge test rather than BioMate's routing/execution modality — so **there is no shared benchmark** on which to compare without introducing a new run. The comparison against it is therefore the capability matrix above, by design, not an omission.
- **Robin / FutureHouse (PaperQA2)** shares **LAB-Bench** with BioMate (BioMate 72.7% overall; the FutureHouse suite reports per-subtask model baselines). PaperQA2's home literature-QA benchmark (LitQA2) is a literature-retrieval task outside BioMate's routing/execution scope and is not featured here.
- **STELLA** (self-evolving agent) and **BioMedAgent** (BioMed-AQA, 77% reported) publish on benchmarks BioMate has not run (no BioMed-AQA / HLE run in the benchmark record) — no shared benchmark.
- **Coscientist / ChemCrow** (chemistry-synthesis benchmarks) and **The AI Scientist** (ML-paper generation) likewise share no benchmark with BioMate's routing/execution/pharmacology suite.

**Method note:** this cross-reference is the "collect their published benchmarks, compare where BioMate already covers them" principle — it yields real comparisons for Biomni without re-running any system, and honestly shows that the co-scientist / chemistry / ML-paper systems evaluate on non-overlapping benchmarks because they target different tasks.

**Companion / authorship disclosure.** RealBio (the row above and the §4.1 routing result) is an open benchmark **released by the same authors as a companion paper** [ref 26], not a third party's evaluation; the BioMate RealBio number is a released-benchmark result, not independent external validation. The mitigation is that RealBio's items, ground truth, and scorer are public and independently re-runnable by any team, so the comparison is refutable even though authorship is shared.

**Also surveyed (workflow-oriented AIs, no scope-matched head-to-head).** *Edison Analysis / Kosmos* (ref 14): workflow-oriented AI reported at BixBench 42.4% and Verified-50 78.0% in a public positioning survey — a different split/protocol from BioMate's BixBench runs (§4.3), so no direct comparison is drawn. *BioMaster*, *NEXUS*, *BioMedAgent*, *GalaxyMCP* are the nearest orchestration-agent analogues named in-line in §1.2. Stage-level prior art surveyed and credited (capability exists; BioMate integrates rather than originates): *AutoIND* (arXiv:2509.09738, 2025 — drafts IND nonclinical eCTD 2.6.2/2.6.4/2.6.6 summaries, ~97% time reduction) for IND-summary generation; *BioWorkflow* (*Brief Bioinform* bbaf571, 2025) for prose→parameter extraction. *FlowAgent* (bioRxiv 2025.03.06.641728), *CRISPR-GPT* (arXiv:2404.18021, 2024), and an open-LLM lab-orchestration study (bioRxiv 2026.05.13.724985, reporting free open models reaching frontier accuracy executing pipelines) are further orchestration-class prior art; the last is cited in §4.1/§6 when framing the catalog+retrieval-is-sufficient result.

**Primary sources.** Biomni — Science 2025 (10.1126/science.adz4351) + github.com/snap-stanford/biomni; Coscientist — Nature 2023 (s41586-023-06792-0); ChemCrow — Nat Mach Intell 2024 (s42256-024-00832-8); Google AI Co-Scientist — arXiv 2502.18864; The AI Scientist — github.com/sakanaai/ai-scientist + arXiv 2504.08066; Robin — Nature 2026 (s41586-026-10652-y) + arXiv 2505.13400 + FutureHouse.org; PaperQA2 — arXiv 2409.13740; STELLA — 2025 preprint; BioMedAgent — *Nat Biomed Eng* 2026 (s41551-026-01634-6), ref 20; BioMaster — bioRxiv 2025.01.23.634608 (ref 18); NEXUS — arXiv:2605.09366, 2026 (ref 19); GalaxyMCP — github.com/galaxyproject/galaxy-mcp (ref 15); AutoIND — arXiv:2509.09738, 2025 (ref 21); BioWorkflow — *Brief Bioinform* bbaf571, 2025 (ref 22); FlowAgent — bioRxiv 2025.03.06.641728 (ref 23); CRISPR-GPT — arXiv:2404.18021, 2024 (ref 24); open-LLM lab orchestration — bioRxiv 2026.05.13.724985 (ref 25); TxAgent/ToolUniverse — arXiv 2503.10970 (Gao S, Zhu R, Kong Z, Noori A, Su X, Ginder C, Tsiligkaridis T, Zitnik M, 2025) + github.com/mims-harvard/ToolUniverse & /TxAgent (211-tool biomedical ecosystem; verified against primary sources 2026-08-24). Orchestration-agent-class survey source: `docs/20260718_LLM_TRAINING_DEEP_SURVEY.md`.
