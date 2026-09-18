# SFT training-data review + what to prepare (given the mid-training corpus)

## A. Review of current SFT data (`multitask_sft.jsonl`, 1,253 ex)
Format: all well-formed (user→assistant, 0 malformed). Per-task counts + findings:

| Task | n | Quality finding |
|---|---|---|
| routing | 529 | OK. Real GEO queries + full-catalog gen; labels from assay→pipeline map (coarse but sound). |
| wfgen | 320 | Good 17-category balance; synthetic intents, decent. Minor: `rna_seq`=6 under-represented. |
| autofix | 217 | ⚠️ **Noisy labels**: some items have EMPTY/uninformative error logs ("(empty) | Command error:") yet get a category → low-signal. Category skew to dependency/format/missing (fixture population); rare cats (genome_mismatch=2). |
| protocol | 119 | ⚠️ **Incoherent pairs**: protocol × QC randomly crossed → nonsense like "whole-genome bisulfite" + "3% mito in single-cell". Label may be right for the QC value but the pairing is invalid. |
| param | 68 | ⚠️ **Too small**; restraint (must-not-fill) present and correct, but volume can't move the metric. Obscure Bioconductor params only. |
| **decomposition** | **0** | ❌ **Missing entirely** (T01/T09) — the first-stage multi-intent→sub-task-DAG task. |

**Verdict:** routing/wfgen are SFT-ready; **autofix needs de-noising** (drop empty-log items, balance categories from real logs), **protocol needs coherent (protocol,QC) pairing**, **param needs 5–10× more volume**, and **decomposition must be added**.

## B. What to prepare for SFT — and how the MID-TRAINING corpus feeds it
Principle: **mid-training injects KNOWLEDGE (raw docs/code/GTN/papers into weights); SFT teaches
BEHAVIORS (instruction→output) over that knowledge, in exact production format.** So SFT data should
be *derived from the same sources mid-training used*, shaped as verifier-gated tasks:

1. **Decomposition (new, high priority)** ← **GTN tutorials** (our staged `gtn_corpus`, 848 multi-step
   tutorials) + `chain_composer` chains + multi-step `.nf`. A tutorial/protocol IS a gold decomposition
   → `query → [{sub_task,intent,order,depends_on}]`. Verify via routing-validity + `chain_planner` DAG.
2. **Tool selection / routing rationale** ← tool docs (`scientific_context`/`usage_guide` in the
   internal corpus) → "which tool/workflow for this data+goal, and why" (+ hard negatives).
3. **Parameter extraction (scale up)** ← workflow `params_schema` + **Nextflow/R code** (code corpus):
   generate 5–10× more, span param types (enum/bool/num/file), keep restraint negatives.
4. **Autofix (de-noise + balance)** ← real `real_exec_err` but **drop empty/uninformative logs**;
   oversample rare categories (genome_mismatch, param_type_error) from broader error sources.
5. **Protocol QC (fix pairing)** ← coherent (protocol, QC-situation, action) triples grounded in
   assay-appropriate QC thresholds; balance PASS/FAIL/WARN (already ~balanced).
6. **Results interpretation / troubleshooting QA** ← **Biostars** (CC-BY) + protocols + parsed outputs
   → grounded Q&A (teaches applying the injected knowledge).

**Cross-cutting SFT requirements (locked lessons):**
- **Exact production/harness prompt format** (single-task LoRA-mismatch caused negative transfer).
- **Joint mixture, task-balanced**; include free-form/no-candidate examples (avoid select-only narrowing).
- **Verifier-gated** per task (schema/execution > auditor) + `overlap_check.py` leakage gate vs RealBio.
- **Volume target** ~1–3k balanced per task; over-generate, filter hard.

## C. Sequence
mid-train (knowledge) → **SFT (these tasks, grounded in the same corpus, production-format)** →
inner-loop skill evolution + RL. SFT is where the mid-trained knowledge becomes correct task behavior.
