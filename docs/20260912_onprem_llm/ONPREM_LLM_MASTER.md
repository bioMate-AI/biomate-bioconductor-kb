# On-Prem LLM — Master Living Document

**Scope:** On-prem BioMate intent/agent model — Qwen3-4B ("small") and Qwen3.8-27B ("large").
Pipeline: **mid-train (continued pretraining) → merge → SFT → (RL deferred)**. QLoRA 4-bit, LoRA.
**This is the single source of truth for the workstream; updated each step.** Honesty contract: every
number here is either measured (marked ✅) or an estimate/assumption (marked ~ / TODO). Change log at end.

Last updated: **2026-09-26**.

---

## 1. Status dashboard

| Track | State | Detail |
|---|---|---|
| SFT retrain #1 `sft_v2` (10k) | ✅ done | loss 1.118; adapter staged |
| SFT retrain #2 `sft_v3` (47.9k) | ✅ done | loss 1.434; adapter staged |
| Fidelity scorecard (v2, v3) | ✅ done | macro 0.522 / **0.537** (16 tasks, teacher-fidelity metric) |
| Gold routing eval (frontier) | ✅ done | Opus5.5 0.978 / Gemini3.8 0.978 / GPT-6-luna 0.964 accept-set |
| Gold routing eval (on-prem base/v2/v3) | ⏳ TODO | `eval_gold.py` ready; needs a GPU box |
| Committee SFT audit | ✅ done | `20260925_COMMITTEE_SFT_TASK_DATASET_AUDIT.md` |
| Corpus-scale quality pass | ✅ done | `sft_quality_audit.json` — narrows the committee claims |
| Literature corpus (entire PubMed) | ✅ built | 28.2M abstracts, ~10.7B tok, 40 GiB on S3 |
| **KG corpus (FULL PrimeKG + MAP-KG)** | 🔄 building | verbalize 8.1M PrimeKG + ~694k MAP-KG edges → text |
| Mid-train `_lit` (literature-only) | ⏸ stopped | superseded by `_litkg` (had no KG); checkpoints resumable on S3 |
| **Mid-train `_litkg` (lit + KG + structured)** | ⏳ pending KG corpus | launches once `kg_corpus.jsonl` verified |
| 27B (large) | ⏸ not started | gate on 4B mid-train signal + a cheap domain-knowledge probe |

**S3 root:** `s3://biomate-models-399683337364/biomate-core-local-trial/20260912/`
(`sft/`, `eval/`, `midtrain_corpus/`, `models_20260919/small/{sft_v2,sft_v3,base_domain_lit,...}_adapter/`,
`spot_ckpt/`, `spot_logs/`, `code/evaluation_local_trial.tgz`).

---

## 2. Infrastructure

- **GPU:** AWS spot L40S (g6e.xlarge 1×48GB; g6e.12xlarge 4×48GB), A10G (g5), L4 (g6). AMI
  `ami-04f7da1c787a89267`, profile `biomate-core-trial-20260912`, us-west-2 (subnets 2a/2b/2c/2d).
- **Spot-always** for training (long, resume-safe). On-demand fallback only for *short* blocking jobs
  (evals, literature build) after 2 dry spot cycles.
- **Resume machinery** (`spot_train.sh`): checkpoints→S3 every 120s; spot-interruption watcher final-sync;
  relaunch restores + `--resume` from nested checkpoint; `base_domain` persisted after midtrain so a death
  after midtrain skips to SFT. Trainer checkpoint cadence made spot-friendly (midtrain ≤300, SFT ≤200 steps).
- **DDP note:** multi-GPU torchrun DDP broke → `FORCE_NGPU=1` single-GPU is the proven path (wastes GPUs on
  a 12xlarge but reliable).
- **Observability:** every box streams `/var/log/*.log`→S3 every 30s + `trap EXIT` final upload (never-blind
  after the tarball-layout crash lesson).
- **Key scripts** (`evaluation/local_trial/`): `spot_launch.sh` (launcher+userdata), `spot_train.sh`
  (train stages), `midtrain_run.py`, `train_qlora_pilot.py`, `merge_lora.py`, `run_midtrain.sh`
  (resume-safe driver), `run_scorecard.sh`/`run_literature.sh` (AZ-cycling+on-demand fallback drivers),
  `eval_corpus.py` (fidelity scorecard, bf16+batched+parallel-judge), `eval_gold.py` (gold routing),
  `frontier_gold.py`, `committee_sft_audit.py`, `audit_sft_quality.py`,
  `build_literature_corpus.py`, `build_midtrain_mix.py`.

---

## 3. Data assets

| Asset | Rows | Tokens | Where |
|---|---|---|---|
| SFT train `multitask_sft_big.jsonl` | 47,959 | — | `data_pool_v2/` + `sft/multitask_sft_enriched.jsonl` (S3) |
| SFT eval `corpus_eval_big.jsonl` | 8,111 | — | `data_pool_v2/` + `eval/` (S3) |
| Structured midtrain `midtrain_all.jsonl` | 173,583 | ~50M | `midtrain_corpus/` (tools/onto/KG/code/internal) |
| **Literature `literature_corpus.jsonl`** ✅ | 28,204,269 | **~10.7B** | `midtrain_corpus/` (entire PubMed baseline, all topics) |
| General replay `general_replay.jsonl` | 550k | — | `midtrain_corpus/` (FineWeb-Edu, anti-forgetting) |
| **KG corpus `kg_corpus.jsonl`** 🔄 | ~8.8M edges | ~0.13B | `midtrain_corpus/` (FULL PrimeKG 8.1M + MAP-KG ~694k, verbalized) |
| Domain mix `midtrain_domain_lit.jsonl` (lit-only) | 7.03M | ~2.44B | superseded (lit 84.8% + structured×8 15.2%) |
| Domain mix `midtrain_domain_litkg.jsonl` ⏳ | — | — | lit + KG(×3) + structured×8 (built on box for `_litkg`) |

**KG note:** the structured corpus had only trivial hetionet (46k tok). Big relational KGs (PrimeKG,
MAP-KG) are now verbalized to NL sentences (PrimeKG: typed "{x} (type) {phrase} {y} (type)."; MAP-KG uses
its own NL relation strings) and folded into the domain mix. **Full graphs, not the immune subgraph.**
Sources: PrimeKG Harvard Dataverse `kg.csv` (datafile 6180620, 936 MB); MAP-KG HF `RainGate/MAP-KG`.

Split: tool-Jaccard **family-disjoint** (`workflow_split.json`). Routing accept-sets:
`accept_sets.json` (4,172 workflows). Gold routing eval: `gold_routing_eval.jsonl` (279 cases,
realbio+dbtest, 100% gold-in-candidates).

---

## 4. SFT phase

### 4.1 Task taxonomy (17 tasks trained)
Core live tasks (routing, parameter_extraction, task_decomposition, autofix_repair, workflow_generation,
clarification_request, log_diagnosis, knowledge_recall, scientific_qa, tool_recommendation,
dataset_prerequisite_check, findings_interpretation, multi_workflow_chaining) + new tasks
(out_of_catalog_composition=N1 flagship, lane_arbitration=N2, design_constraint=N3, model_selection=N4).
Taxonomy detail: `20260922_LLM_TASK_TAXONOMY_NEWVERSION.md`.

### 4.2 Per-task counts (train / eval)
tool_recommendation 8703/1516 · knowledge_recall 7380/1333 · scientific_qa 6985/1149 ·
dataset_prerequisite_check 6463/1082 · workflow_routing 5366/957 · log_diagnosis 2719/299 ·
parameter_extraction 2273/495 · autofix_repair 1636/171 · clarification_request 1432/276 ·
task_decomposition 1312/274 · lane_arbitration 1027/171 · findings_interpretation 784/106 ·
**out_of_catalog_composition 599/0** · design_constraint 416/79 · workflow_generation 365/110 ·
model_selection 330/70 · multi_workflow_chaining 169/23.

### 4.3 Retrains + fidelity scorecard ✅
Both QLoRA SFT on the enriched corpus. Per-task **macro (teacher-fidelity coverage, 0–1)**:
`sft_v2` (10k) = **0.522**, `sft_v3` (47.9k) = **0.537** (scaling the corpus gave a small lift).
Strongest tasks (v3): design_constraint 0.884, workflow_routing 0.728, autofix_repair 0.682.
Weakest: knowledge_recall 0.379, lane_arbitration 0.382, scientific_qa 0.422 (literature-shaped knowledge).
Full: `routing_data_v1/scorecard_small_v3.json`.

---

## 5. Evaluation methodology

- **Fidelity scorecard (current default):** LLM-judge coverage of the teacher's answer — measures
  *distillation fidelity*, NOT correctness. Valid for relative comparison; **not** an absolute capability
  measure. (Harness: `eval_corpus.py`, bf16+merged-LoRA, batched gen + parallel judge.)
- **Gold routing (`eval_gold.py`):** accept-set membership vs the real workflow DB, candidate-grounded
  (279 cases). TRUE gold.
- **Frontier ceiling ✅** (same 279 gold cases, `frontier_gold.py`):

  | Model | Accept-set | Exact-gold |
  |---|---|---|
  | Claude `claude-opus-5-5` | (opus-4-8 run: 0.978) | 0.910 |
  | Gemini `gemini-3.8-flash` | **0.978** | 0.925 |
  | GPT `gpt-6-luna` | 0.964 | 0.914 |

  → frontier ceiling ~97% accept. **On-prem base/v2/v3 on this same metric is the missing comparison (TODO).**
- **Latest model IDs (probed 2026-09-24/26):** Claude `claude-opus-5-5` (also opus-5, sonnet-5, fable-5-1);
  OpenAI `gpt-6-luna`/`gpt-6-sol` (no `gpt-6`); Google `gemini-3.8-flash` (no 3.8-pro).

---

## 6. Committee audit + corpus-scale verification

Committee (Opus 5.5 / GPT-6-luna / Gemini-3.8-flash), grounded in real counts+samples. Full:
`20260925_COMMITTEE_SFT_TASK_DATASET_AUDIT.md`. **Unanimous structural findings (stand):**
1. Value–volume inversion: ~62% train on 4 lookup/QA tasks; N1–N4 = 4.9%; flagship N1 = 1.2%.
2. N1 flagship has **0 eval rows** — deployment blocker.
3. Eval metric = teacher-fidelity for 15/17 tasks → can reward hallucinations (proof: `rtracklayer`→
   `marraylm` teacher answer baked in).
4. 3 QA tasks (knowledge_recall+scientific_qa+tool_recommendation, ~48%) are really one.
5. Galaxy contamination vs de-Galaxy target (ToolShed wrappers throughout).
6. Label≠content mis-scoping (param_extraction, dataset_prereq, findings, wfgen, decompose).
7. CI/CD harness leakage in log_diagnosis + autofix_repair.

**Corpus-scale pass (`audit_sft_quality.py`, all 48k+8k rows) — CONFIRM/DISCONFIRM:**
- ✅ CONFIRMED: CI-leakage localized — log_diagnosis **8.8%**, autofix **7.4%** (~360 train rows).
- ❌ DISCONFIRMED as sample/display artifacts: truncation **0.0%** (the "chainSort" cutoff was my 500-char
  sample cap), answer-leakage **~0.1%**, templated/short answers **0.0%**, duplication **0.18%**.

**Prioritized fixes (from audit):** rebalance (downsample QA ~75% → N1–N4); N1 gold eval as deploy gate;
replace teacher-fidelity scoring with programmatic gold (DAG/JSON-schema/type-check/exact-match); relabel +
rewrite task contracts + structured-JSON outputs; purge CI artifacts + stale Galaxy entities.

---

## 7. Mid-training (literature) — the "data ready" fix

**Why:** the weak tasks (knowledge_recall 0.379, scientific_qa 0.422) are literature-shaped, and the prior
mid-train was a WASH (MID=400 = ¼ epoch of a literature-less corpus). User: mid-train data was "not ready —
no literature, no open-text mix." **Fixed by acquiring the entire PubMed corpus.**

- **Corpus ✅:** entire PubMed baseline (all 1,334 files, all topics, no filter) → 28,204,269 abstracts,
  ~10.7B tokens, 40 GiB (`build_literature_corpus.py`, parallel stdlib parser on a CPU box).
- **Mix ✅ (verified gate):** domain = literature stride-sampled (keep-every 5 → 5.64M abstracts, ~2.07B
  tok, **84.8%**) + structured×8 (173k unique → 1.39M rows, ~370M tok, **15.2%**) = ~2.44B domain tokens.
  With 25% general replay → overall ~**63% literature / 12% structured / 25% open-domain** (user-approved).
- **Run `_lit`:** STAGE=full (midtrain→merge→SFT), MID=5000 (~325M tok seen), BS8×GA4 (eff 32), SEQ2048,
  LoRA r16, spot L40S, resume-safe. **Status: midtrain step ~1,200/5,000**, surviving spot reclaims via
  resume. Output → `models_20260919/small/full_lit_adapter/`.
- **Then:** eval `full_lit` on gold routing (vs frontier ~97%) + fidelity (vs sft_v3 0.537) to answer:
  *does literature mid-training lift the knowledge/scientific-QA tasks?*

---

## 8. Key decisions & rationale
- Mid-train "wash" was undertraining + no literature → fixed by real corpus + more steps (not abandoning mid-train).
- Eval must move from teacher-fidelity to programmatic gold; gold routing built first (flagship, cheapest).
- 27B gets SFT (not mid-train) gated on a cheap domain-knowledge probe — deferred until 4B mid-train signal.
- Open-domain replay fraction = 25% (user choice; LoRA makes forgetting mild, lets literature dominate).

## 9. Open issues / next steps
1. **On-prem gold routing** (base/v2/v3 + `full_lit`) via `eval_gold.py` — the real 4B-vs-frontier gap. [TODO]
2. **N1 gold eval** (deploy gate): ~250 graph-composition problems + abstention negatives. [TODO]
3. **Corpus rebalance + relabel** per committee (downsample QA, boost N1–N4, merge 3 QA tasks, fix labels). [TODO]
4. **Filter CI-leakage** (~360 log_diagnosis/autofix rows). [TODO — cheap]
5. **Programmatic scorers** (DAG/JSON-schema/type/EM) to replace teacher-fidelity. [TODO]
6. `full_lit` eval + decision on 27B. [after mid-train]

## 9b. DECISION (2026-09-28): 27B mid-train = NO-GO; eval judge was broken

- **Broken metric found:** the teacher-coverage LLM judge (fidelity scorecard) is unreliable — diagnostic
  showed it scored a hallucinated wrong workflow (`clustermix` vs gold `clustall`) as 1.0, and near-identical
  answers 0.0 vs 0.8. The `sft_v4` macro 0.458 is **judge noise on an ungrounded eval**, NOT a real fail.
- **Valid signal (objective gold routing, accept-set, no judge, matched 150-step SFT):**
  plain-base+SFT **0.849** accept / 0.781 exact vs midtrain-1200-base+SFT **0.796** / 0.706 → **lift −0.053**.
- **Conclusions:** (1) the plain-SFT 4B is strong on routing (0.849 vs frontier 0.978) — not a fail;
  (2) **mid-training HURTS** (−5.3 pts), consistent with the prior wash + ~1% NLL. **27B → SFT-only, skip
  mid-train.** Literature+KG corpus → use via RAG + KG→SFT-reasoning, not mid-train.
- **Caveat:** ckpt-1200 + routing-only; full objective per-task grader suite (RealBio score.py contracts) is
  the next build to confirm across all tasks and retire the judge everywhere.

## 10. Change log
- 2026-09-26 (later): KG gap identified (only trivial hetionet in the mix) → building FULL PrimeKG
  (8.1M edges) + MAP-KG (verbalized) corpus from immune-llm-sourced references; wired `--kg`/`MIX_KG`/
  TAG-namespaced mix into the pipeline; stopped `_lit` (lit-only, superseded) to relaunch as `_litkg`
  (lit + KG + structured + replay) once the KG corpus is verified. KG assets found in
  `/Users/kky/biomate-immune-llm/research/knowledge/` (MAP-KG primary, PrimeKG fallback per their registry).
- 2026-09-26: Literature corpus built (10.7B tok); `_lit` mid-train launched + composition verified
  (63/12/25); corpus-scale quality pass (confirmed CI-leak, disconfirmed truncation/leak/templating);
  committee SFT audit; frontier gold ceiling (~97%); latest model IDs probed (opus-5-5). Master doc created.
- (earlier) sft_v2/sft_v3 retrains + fidelity scorecards; grounded metric; eval harness bf16+batched fixes;
  gemini-3.5→3.8 config swap; data-pool v2 (53k interactions, 47.9k SFT).
