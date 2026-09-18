# BioMate domain mid-training data mix (GAP-Replay style, commercial-safe)

Recipe (mirrors Periodic Neon + Meditron GAP-Replay): **open base (Qwen3.8-27B) → MID-training
(distributional bridge) → SFT (tasks) → RL/self-evolving loop**. Mid-training = a bridge, NOT 100%
domain: keep a large **general replay** fraction to avoid forgetting; inject domain knowledge at
~15–30%. All sources below are **commercial-on-prem safe** (license column); verify the two flagged.

## The mix (target ≈ one mid-training run)
Two knobs: **domain fraction** (recommend ~25%) and **total domain-token budget** (recommend
**~3–6B tokens**; a 27B needs modest domain tokens — GAP-Replay used ~48B at 70B, far less suffices
for task lift). Weights below are **shares of the DOMAIN portion**.

| Source | License | Commercial? | Est. tokens (raw) | Weight (of domain) | Best use |
|---|---|---|---|---|---|
| **Internal corpus** (ours; S3 `midtrain_corpus/`): **text ~9M + CODE ~17M = ~26M tok** | internal + nf-core MIT + Bioconductor Artistic-2.0 | ✅ (verify per-pkg) | ~26M (repeat ×2–3) | **35%** | tool/workflow knowledge **+ Nextflow/Bioconductor/workflow_json CODE** — *highest value, on-domain; code drives param/workflow-gen/decomposition* |
| **peS2o** (bio-relevant slice) | ODC-BY | ✅ | 2–3B | **40%** | literature domain knowledge |
| **PMC OA — `oa_comm` only** (bio) | CC-BY family | ✅ | 1–2B | **20%** | full-text papers/methods |
| **Biostars Q&A** | CC-BY-4.0 | ✅ | ~0.3B | **8%** | tool use + error diagnosis prose |
| **Galaxy Training Network** | CC-BY-4.0 | ✅ | small (repeat ×3) | **6%** | workflows + **decomposition** (multi-step) |
| **nf-core** code + docs | MIT | ✅ | ~0.2B | **4%** | code/param/workflow syntax |
| **Bio-protocol** (CC-BY subset only) | CC-BY-4.0 | ✅ (skip CC-BY-NC) | small | **2%** | protocol logic + decomposition |
| _BioProCorpus, UltraMedical_ | **verify** | ? | (SFT stage) | — | protocols / medical instructions — license-check first |

**General replay (~75% of the run):** a high-quality general/code corpus as the anti-forgetting
bridge (e.g., FineWeb-Edu slice + peS2o non-bio + a code slice). We lack Qwen's exact pretrain data,
so this is a proxy for its distribution — its job is retention, not new knowledge.

## Train-in vs RAG (our finding + GAP-Replay principle)
- **TRAIN-IN (weights):** reasoning/style, protocol logic, routing conventions, error-diagnosis
  patterns, decomposition patterns, domain vocabulary. → the corpora above.
- **KEEP IN RAG (never train stale facts):** the 4,200-workflow catalog, per-workflow schemas,
  DB records (UniProt/Ensembl/etc.). BioMate's hybrid retriever already handles these well.

## Sequence
1. **Mid-training** on the mix above (~25% domain / ~75% replay), 1 pass, LR warmup+decay, pack to
   seq-len; checkpoint→S3. Goal: inject domain knowledge without forgetting.
2. **SFT** on grounded task data (routing/param/autofix/**decomposition**) + Biostars/GTN/protocol
   Q&A + UltraMedical (if license clears) — the multi-task plan, harness-exact formats.
3. **RL / self-evolving loop** on proprietary signal (exec-verified outcomes + corrections) — our
   flywheel = Periodic's autonomous-lab loop.

## Data hygiene (mandatory before training)
- **Dedup** (MinHash/LSH) within + across sources.
- **Decontaminate** against RealBio, LAB-Bench, BixBench, MedQA (n-gram overlap filter) — no test leak.
- **License filter** per-article/per-directory (PMC → `oa_comm` only; Bio-protocol → CC-BY only;
  drop bioRxiv redistribution, KEGG, non-OA PubMed full text).
- **Quality filter**: length, language, boilerplate/dedupe headers, PII scrub.

## Realistic budget note
For narrow **task** lift, SFT + the inner-loop harness evolution likely move the needle more per GPU-
hour than mid-training (our earlier finding: base is already competitive; retrieval carries knowledge).
Mid-training's payoff is **domain fluency + fewer hallucinations on unseen domain prose** — worth one
run once the SFT/inner-loop cluster is in. Order of ROI: **inner-loop skills → SFT tasks → mid-training → RL**.
