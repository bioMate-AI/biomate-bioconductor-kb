# Next-Phase Plan — Addendum: verified references + competitive landscape

**Date:** 2026-06-19
**Extends:** `docs/20260619_NEXT_PHASE_OUTPUT_PROJECT_COLLAB_PLAN.md`
**Why:** product memo provided 4 specific external systems to learn from. This addendum captures each, verifies the citations, and maps engineering takeaways to concrete BioMate next-phase items.

## 0 — Correction to the parent plan's "Open Questions"

| Open question (prior) | Resolution |
|---|---|
| "AWS BioSkills Hub doc not found in repo" | **Not AWS. It's `github.com/BioTender-max/awesome-bio-agent-skills`** — community-maintained awesome-list of bio AI agent skills. No local survey doc exists in repo (verified via grep). Using the URL as primary reference. |
| "Robin & co-scientist paper — confirm authors" | **Robin = FutureHouse (Sakurako, Nature 2026-05; preprint earlier).** Code: `github.com/Future-House/robin`. Distinct from Google Co-Scientist (Gottweis et al., Nature 2026-05, DOI 10.1038/s41586-026-10644-y). |

## 1 — `awesome-bio-agent-skills` (BioTender-max GitHub)

**What it is:** community-maintained catalog of bio-agent skills, datasets, benchmarks, frameworks. Awesome-list format. **Action:** treat as upstream — when we author a BioMate "skill" (saved chain), publish a stub upstream so it appears in the catalog. Cross-link from BioMate's project-skills UI.

**Risk:** awesome-lists go stale fast — don't make it a runtime dependency.

## 2 — Google AI Co-Scientist (Gottweis et al., Nature 2026-05)

**Citation:** Gottweis J, Natarajan V, et al. *Towards an AI co-scientist.* Nature (2026). DOI: 10.1038/s41586-026-10644-y. Google DeepMind + Cloud AI + Research + Stanford Med + Imperial + Houston Methodist.

**Architecture: 7 agents (Gemini 2.0) + 1 supervisor, 3 stages:**

| Stage | Agent | Function |
|---|---|---|
| Generation | Generation | 4 strategies: lit search, sci debate sim, iterative testable-hypothesis ID, research extension |
| Generation | Proximity | Cluster + dedupe |
| Debate | Reflection | 6 review modes: initial / comprehensive / deep-verify / observation / simulation / iterative |
| Debate | **Ranking** | **Elo tournament** — pairwise hypothesis PK |
| Evolution | Evolution | 6 refine strategies: search-augment, feasibility-boost, inspiration, combination, simplification, out-of-box |
| Evolution | Meta-review | Synthesize across debates, feed insights back into other agents' prompts |
| Supervisor | Supervisor | Decompose goal, allocate compute, coordinate parallel agents |

**Verified empirical results:**
- **AML drug repurposing** (Stanford Med): 2,300 FDA drugs × 34 cancers → 30 top → 5 chosen → 3 active. **Binimetinib IC50 = 2 nM (HL-60) vs TK6 control 38.71 µM — ~20,000× selectivity.**
- **KIRA6** (Co-Scientist's blind nomination, no prior literature support): 10 nM on KG-1a (AML stem-like), with IRE1α–XBP1 mechanism explanation.
- **Liver fibrosis** (Peltz, Stanford): 3 epigenetic targets → Vorinostat (FDA-approved for another oncology indication) → cross-disease drug repurposing.
- **Antimicrobial resistance** (Penadés, Imperial College London): independently rediscovered cf-PICIs phage-tail interaction mechanism in **2 days** vs lab's **~10 years**.

**Engineering takeaways → BioMate map:**

| Co-Scientist concept | BioMate next-phase item it informs |
|---|---|
| 7-agent role split | Layer A of `pilot-experiment-panel.tsx` (extend with Reflection/Ranking/Meta-review roles for chain selection) |
| **Elo tournament for ranking hypotheses** | **Direct fix path for BC-10 chain disambig** — current implementation uses MiniLM cosine + LLM scope-check; Elo over pairwise LLM comparisons is more robust (matches Robin's takeaway below) |
| Meta-review feeding back into prompts | Pattern for BioMate's auto-loop QC remediation messages |
| Most compute → verification, not generation | Pattern for chain dispatch: prefer to retry LLM verification (current half-day fix shipped earlier) before falling back to embedding rank |
| Test-time compute scaling shows non-saturating Elo gains | Suggests BioMate's chain-router could spend more LLM budget on rerank without diminishing returns |
| Cost: $3,985 vs $910 for stronger results | If LLM cost is bottleneck, this isn't free. Position as "premium" path option. |

**Constraint disclosure:** Gemini 2.0 is closed-source; full source not public. Supplementary Notes 8-9 have pseudocode + prompts. BioMate cannot copy the implementation but can rebuild the patterns on Claude / Qwen / open Gemini.

## 3 — Robin (FutureHouse, Nature 2026-05)

**Citation:** FutureHouse team. *Robin: a multi-agent system for autonomous biomedical hypothesis generation and experimental design.* Nature (2026). Code: `github.com/Future-House/robin`.

**Architecture: 4-stage pipeline, 3 specialized agents:**

| Stage | Agent | Function | Wall-clock |
|---|---|---|---|
| 1 — Hypothesis generation | Falcon | Deep-search PaperQA2 RAG, multi-round gap-driven retrieval | hours |
| 1 — Hypothesis generation | Crow | Focused-search PaperQA2 RAG, 2-3 RAG rounds | minutes |
| 2 — Ranking | (no dedicated agent; uses pairwise-Elo) | Hypothesis pool (~100-200) ranked via pairwise GPT-4o comparisons + Swiss-system tournament + 3-run majority voting | hours |
| 3 — Experimental design | Falcon + Finch | Pick in vitro model + endpoints from literature | hours |
| 4 — Data analysis | Finch | Jupyter kernel as tool-calling interface (43 cells / trace) | hours |

**Key engineering decisions (critical for BioMate to learn from):**

### Decision 1 — pairwise + Elo over LLM-as-judge absolute scoring

The Robin paper EXPLICITLY documents that early versions tried LLM-as-judge absolute scoring (1-10 score per hypothesis) and **rejected it for two reasons:**

1. **Calibration failure:** same hypothesis scores 3-9 across 10 runs.
2. **Position pollution:** score depends on what other hypotheses are in the prompt (position bias).

**Direct relevance to BioMate BC-10:** my BC-10 handoff doc (`docs/20260618_BC10_CHAIN_RANKING_REQUIREMENT.md`) discussed reranker options A/B/C/D. **Option C (off-the-shelf cross-encoder)** is the structural fix; **Option D (custom train)** is premature. But **Robin's evidence specifically validates option C+ pairwise tournament over absolute LLM scoring** — exactly what BioMate's `_llm_select_chain` does today (returns `chain:<name>` / `clarify` / `none`, an absolute call).

**Concrete fix path for BC-10 informed by Robin:**
- Phase 1 (today's PR — shipped): retry on garbage LLM response, treat as no-match
- Phase 2 (next, ~2 days): replace `_llm_select_chain`'s single-shot absolute call with pairwise comparisons across top-3 embedding candidates. Use 3-run majority voting per pair (matches Robin's recipe). No custom training needed.
- Phase 3 (deferred): full Swiss-tournament if N candidates > 5.

### Decision 2 — Jupyter kernel as tool-calling interface (Finch)

Robin's Finch agent uses Jupyter cells as the tool-calling primitive, not `bash + python` sandbox. Cells share kernel state, output is losslessly fed back to LLM, error recovery is local.

**Direct relevance to BioMate:** the `run_code` tool today uses `docker run` per call (verified earlier — and the `biomate-biotools:1` image was pull-denied during BC-04 reproduction). Refactoring `run_code` to a persistent Jupyter kernel per chat session would:
- Preserve state across `run_code` calls (no need to re-load CSVs / re-import libraries every cell)
- Cleaner error recovery (cell-level not session-level)
- Same observability model the design promises in Findings tab
- Pattern adopted by Robin and validated on ProteinGym (217 DMS assays)

**Effort:** ~1 week — needs a per-session JupyterKernelGateway-style service, websocket for cell exec, cleanup on session end.

### Decision 3 — split RAG into focused (Crow) vs deep (Falcon)

Robin uses **PaperQA2** as the RAG backbone but exposes two agents with very different schedule loops. The split correctly recognizes that "give me the 5 most-cited papers on X" needs different retrieval logic than "give me an opinionated review of methods for X."

**Direct relevance to BioMate:** the research-intelligence-agent feature (mentioned in the parent plan §3 — Project document index) should adopt this dual-mode pattern. **Focused mode** for "what does this paper say about X" (Crow shape — 2-3 RAG loops); **deep mode** for "review the literature on X" (Falcon shape — gap-driven multi-round).

### Decision 4 — bottleneck is wet-lab time, not LLM time

Robin paper explicit: end-to-end discovery ≈ 2.5 months, of which Stage 1+2 (LLM-heavy) ≈ 2 hours. Wet-lab dominates.

**Implication for BioMate:** investing in agent intelligence past a point yields diminishing returns vs investing in faster experiment cycle time. Liu pilot's RQ2 (efficiency for analysts) maps directly.

### Verified result — dAMD → Ripasudil

Robin's headline output: **Ripasudil** (FDA-approved 2014 in Japan as Glanatec for glaucoma; ROCK inhibitor). Robin proposed re-using for dry AMD (no prior literature link). Mechanism: ROCK inhibition → RPE cytoskeleton reorganization → restored phagocytosis of photoreceptor outer segments → slowed drusen accumulation. Validated in iPSC-RPE cell model with RNA-seq mechanism explanation matched to predicted pathway (ARHGEF18, ABCA1 upregulated).

## 4 — AutoScientists (Shanghua Gao et al., arXiv:2605.28655)

**Citation:** Gao S et al. *AutoScientists: Self-Organizing Agent Teams for Long-Running Scientific Experimentation.* arXiv:2605.28655 (2026). Code: `github.com/mims-harvard/AutoScientists`. Marinka Zitnik (Mims) group.

**Architecture: 2 agent roles, shared state, hypothesis-driven team formation**

| Role | Job |
|---|---|
| **Analyst** | Reads experiment log; identifies which directions untried, which dead; proposes next experiments |
| **Experiment** | Claims experiments from queue; modifies code; trains models; writes results back to log + forum |

**Shared state (the load-bearing innovation):**
- Current champion model
- All experiment logs (success + **failure**)
- Forum-style discussion area
- Per-team queue + dead-end registry + hypothesis docs

**Discovered patterns enforced by source-code-level protocols:**
1. **Orchestrator is pure coordinator** — cannot run experiments, modify code, or substitute for an agent. Bright line: "if everything fails, orchestrator releases stale claims and restarts agents — doesn't take over the work."
2. **HEARTBEAT + Mode Selector at each agent start** — agent must finish prior work's API trail before claiming new tasks.
3. **No-API-trail = no work** — bright rule. Analyst MUST POST proposals + PATCH team queue, not just suggest locally.
4. **Teams formed around falsifiable hypotheses, not technical axes** — e.g., "model is training-step limited" team vs "model is gradient-quality limited" team. Each writes prediction + falsification criterion.
5. **Axis-mining trigger** — if recent failures concentrate in few axes and queue lacks cross-axis experiments, trigger new discussion round.

**Verified empirical results:**
- **BioML-Bench 24 tasks**: AutoScientists 74.40% vs Autoresearch 66.07% (8.3 pp improvement). Drug discovery: 64.52% vs 46.16%.
- **GPT nanochat optimization**: at same target loss, AutoScientists used 34 experiments vs Autoresearch 65 (1.9× efficiency). When starting from AutoScientists' own champion: 7 improvements in 93 runs vs Autoresearch's 0 in 100 runs.
- **ProteinGym** (zero-shot transfer): AutoScientists-Kermut improved Spearman from 0.747 → 0.840 on dev (+12.5%); zero-shot transfer to 217 DMS assays: 0.657 → 0.700 (+6.5%).

**Engineering takeaways → BioMate map:**

| AutoScientists concept | BioMate next-phase item |
|---|---|
| Shared experiment state | **Critical pattern for the parent plan's Pilot Experiment Panel (§9 / Layer A)** — current panel does A/B compare but doesn't accumulate "things we tried, didn't work, here's why" registry. Add a `experiments.dead_ends` table scoped per project. |
| **Failures as first-class assets** | Project's experiment registry should store failed run config + reason; chat-stream should consult before re-proposing |
| Teams formed around falsifiable hypotheses, not technical axes | Pattern for grouping related runs in project dashboard ("this batch of runs tests whether parameter X matters") |
| Orchestrator is pure coordinator | BioMate's chain composer (`workflow_chain.py`) already follows this — good design; document it explicitly |
| Cost: more LLM tokens for better experiment selection | Same trade-off as Co-Scientist. Project owner should configure budget posture (lean / standard / aggressive search). |

## 5 — Gene Detective (基因侦探, cnsaccept.top) — commercial competitor

**Citation:** "生信研究室" WeChat blog post, 2026-05-05. Commercial platform by a "medical and bioinformatics PhD team."

**Their offering:**
- Differential expression, WGCNA, GO/KEGG/GSEA, immune infiltration, ML (LASSO / RF), eQTL Mendelian randomization, colocalization, TCGA + single-cell cloud-direct analysis
- **Per-module output: auto-generated Methods + Result + Figure-legend text + publication-quality figures**

**Direct competitive analysis vs BioMate:**

| Capability | Gene Detective | BioMate today |
|---|---|---|
| One-stop bioinformatics catalog | ✅ (~10 listed modules) | ✅ 2,455 indexed workflows, broader |
| Per-module auto Methods/Results/Figure-legend text | ✅ — their headline differentiator | ⚠️ partial — Methods tab exists; figure-legend not auto-generated |
| Cloud-hosted execution (no Slurm) | ✅ | ✅ AWS Batch |
| TCGA / single-cell direct connect | ✅ | ⚠️ available via workflow; not "one-click" pre-staged |
| Publication-quality figures inline | ✅ | ⚠️ figures generated but not styled to publication standard automatically |
| Mendelian randomization | ✅ | ❌ not in catalog (parent plan §1 listed this as a Liu/Zhi GWAS-evidence gap) |
| Colocalization | ✅ | ❌ same |
| Pricing | "first 10 free, 2 weeks, paid after" | Lago metered (token + GPU + storage) |
| Audience | Mostly Chinese-market clinical researchers wanting publishable figures | Researcher labs wanting orchestration + reproducibility |
| Differentiation BioMate has | Multi-tenant + project + skills + BYO code (planned); regulatory pipelines (IND); BioMate's research-intelligence agent | They have a tighter, more polished single-purpose UX |

**Strategic takeaway:** Gene Detective is the Chinese-market version of "RNA-seq paper analysis as a SaaS." For Zhi/Zhao/Liu (US academic), they are not the competitor. For Chinese clinical genomics labs, they are. BioMate's edge is breadth, reproducibility, project-scoped collaboration, and BYO. Don't try to match Gene Detective's auto-figure-legend feature in week-1; do plan for it in P2.

## 6 — Updated priority ordering after these references

The parent plan had P0/P1/P2/P3. Refined ordering based on what these papers + the Gene Detective competitor say:

| New priority | Item | Justification (which reference informs) |
|---|---|---|
| **P0** | Channel 5 lockdown + counted endpoint | unchanged — compliance |
| **P0** | User-assigned output location | unchanged — compliance |
| **P0** | Download Report rewrite (research-doc style) | unchanged — design promise |
| **P0+** (new) | **Per-module auto Methods + Figure-legend** | Gene Detective competitor parity — adds 2-3 days to Download Report work |
| **P1** | Project dashboard + file browser | unchanged |
| **P1** | Per-project output organization | unchanged |
| **P1+** (new) | **BC-10 chain reranker — pairwise + Elo + 3-run voting** | Robin's evidence specifically validates this over absolute LLM scoring (matches my prior BC-10 handoff Option C; now has citation backing). ~2 days. |
| **P1+** (new) | **Project experiments registry with dead-end log** | AutoScientists' load-bearing pattern. Without it, parallel runs in same project waste effort retrying failed configurations. Adds to Pilot Experiment Panel. ~3 days. |
| **P2** | Project document index (RAG over uploaded docs) | adopt Robin's Crow/Falcon dual-mode split |
| **P2** | Project skills | adopt `awesome-bio-agent-skills` schema as the skill manifest format |
| **P2+** (new) | **Refactor `run_code` to per-session Jupyter kernel** | Robin's Finch validates this. Closes the broken `biomate-biotools:1` Docker pull issue surfaced during BC-04 reproduction. ~1 week. |
| **P2+** (new) | **Coloc + MR workflows** | Per parent plan §1 Liu GWAS-evidence gap + Gene Detective parity. ~3-5 days. |
| **P3** | BYO code git import | unchanged |
| **P3** | Project members RBAC | unchanged |
| **P3+** (new) | **7-agent Co-Scientist architecture for research-intelligence-agent extension** | Pattern for the future when BioMate moves from "execution + reporting" to "hypothesis generation + experimental design." Big effort; defer until P0-P2 lands. |

## 7 — Specific code/repo references to clone + read

| Repo | What to learn |
|---|---|
| `github.com/Future-House/robin` | pairwise + Elo + Swiss tournament implementation; Jupyter-as-tool-call pattern; PaperQA2 dual-mode (Crow + Falcon) |
| `github.com/mims-harvard/AutoScientists` | shared-state protocol; orchestrator-as-pure-coordinator; dead-end registry schema; team-formation-around-hypotheses |
| `github.com/Future-House/paper-qa` (PaperQA2) | citation-anchored RAG with mandatory source attribution; would replace generic embedding RAG for BioMate's research-intelligence-agent |
| `github.com/BioTender-max/awesome-bio-agent-skills` | community skill format — adopt for BioMate's per-project skills registry manifest |

## 8 — Specific design pattern recommendations (concrete UI / API)

### Pattern A — BioMate's "Skills" should mirror `awesome-bio-agent-skills` manifest

If the awesome-list uses a structured YAML/JSON per skill (typical for these lists), BioMate's `projects.<id>.skills.<id>.manifest.json` should be a strict superset. Then a user-authored skill can be one-click published upstream. Effort: ~half day to inspect their schema + align ours.

### Pattern B — Pilot Experiment Panel extends to AutoScientists-shape

| Today (Pilot Experiment Panel) | After AutoScientists patterns |
|---|---|
| User: hypothesis + control + experimental params | + dead-end log (auto-populated from failed runs) |
| BioMate fires 2 runs | + per-team queues; LLM-agent proposes next run from log + dead-ends |
| Side-by-side comparison | + meta-review LLM summarizes "what we've learned across N runs" |
| History in left sidebar | + "research-overview" auto-doc that compounds across runs |

This positions BioMate as not just "compare run A vs run B" but "manage a long-running multi-direction experiment program for me."

### Pattern C — Download Report adopts per-module Method/Result text generation

| Section | Today | Gene Detective parity |
|---|---|---|
| Methods | verbatim Methods tab | LLM-generated publication paragraph from manifest + container digests (BioMate already has the per-step Methods text — just needs the synthesis prompt) |
| Results | finding bullets | LLM-generated narrative ("…we identified 2,841 DE genes at FDR < 0.05; top GO terms include regulation of apoptotic process [GO:0006915] …") |
| Figure legends | nothing | LLM-generated per figure from the run manifest + figure description |

Effort: ~3 days frontend + ~1 day prompt engineering.

## 9 — Updated open questions (replaces parent doc's set)

1. ~~AWS BioSkills Hub~~ → **resolved**: `github.com/BioTender-max/awesome-bio-agent-skills`. No local survey doc — should we author one (~half day)?
2. ~~Robin authors~~ → **resolved**: FutureHouse team, Nature 2026-05. Code at `github.com/Future-House/robin`.
3. **Liu Phase 2 compliance scope** (HIPAA / 21 CFR Part 11 / GDPR / all?) — unchanged from parent doc
4. **Project members for Phase 1** — single-tenant or invite-by-email? — unchanged
5. **BYO code policy** — Python/R/shell/containers? Network? GPU? — unchanged
6. **Output retention** — default duration? user-configurable per project? — unchanged
7. **NEW: How much engineering bandwidth for AutoScientists-shape experimental harness?** — extends the existing Pilot Experiment Panel substantially (~2-3 weeks). High value but big commitment.
8. **NEW: BC-10 fix priority** — Robin's evidence makes pairwise+Elo+3-run-voting the right next step (P1+). Confirm we should ship this before Coloc/MR workflows.
9. **NEW: Per-module auto Methods/Results/Figure-legend** — Gene Detective parity. Add to P0+ list?

Please confirm answers (or "use defaults") so I can convert the priority list into actionable tickets.

## 10 — Anything missing that's still in your memo

Re-reading the product memo, items I haven't addressed in this addendum:

- **"User should be able to provide own code locally or from git to run in our system"** — covered in parent doc P3 (BYO code). Robin's Jupyter-as-tool-call pattern (§3 Decision 2 above) is the right primitive to adopt.
- **"five use cases to clearly organize their input and outputs in different channels and documents, to clarify things together"** — covered in parent doc Part 6 (UC1 Liu / UC2 DESeq2 / UC3 scGWAS / UC4 TorchGWAS / UC5 T01).

Both still in scope; this addendum just sharpens the engineering patterns to use when implementing them.
