# I-B: retrieval, encoder index, prompt builder, blind rule, structure adaptors, group-A soft-rule re-mining

All runs are on EC2 spot (launcher: `retrieval/ec2_job.py`, single-writer S3 prefix per run, cost log `retrieval/ib_cost_log.jsonl`).

| piece | file | status (EC2 evidence) |
|---|---|---|
| store + builders (`from_long_all`, `from_pair_labels`) | `retrieval/store.py`, `build_store.py` | real data run: arm-G store 4,634 exact rows / 2,826 isomers / 230 documents / years 1991-2025 / 8 integrin targets; wide store 21,575 rows / 724 targets / NO document ids |
| stereo-aware Tanimoto index (Morgan r2, 2048 bit, chirality) + embedding index (cosine, content-hash cache) | `retrieval/index.py` | 15 tests passed (siblings distinguished, determinism with ascending-index tie break, save/load, cache hit, alignment guard) |
| `Retriever` (build / add / query; filters applied before ranking) | `retrieval/retriever.py` | tests above |
| prompt builder with token-budget guard, pharmacophore text, honest `pharmacophore_encoded` flag | `retrieval/prompt.py` | tests above (farthest hits dropped first, `PromptTooLong` instead of silent truncation) |
| blind rule for arm G (`exclude_docs`, answer-set flat keys, `max_year`, strict provenance) | `retrieval/blind.py` | test + controls that can FAIL (4 violation types raise); real store: held-out newest avb3 document (CHEMBL6153109, 2025, 5 rows): 0 excluded-document hits in 5 queries |
| structure tier wrappers (Boltz-2 cofold via `physics_batch`, BoltzGen, UniMoMo), metered | `structure/wrappers.py` | 4 tests passed; Boltz dry-run for target avb6 returned `cold_start` (receptor 9xmm not prepped): no cofold job possible until the receptor is prepared; Batch queue `biomate-gpu-spot-queue` ENABLED and job-def `boltz-snat2-direct` ACTIVE (read-only check); BoltzGen / UniMoMo are plan-only (whole-instance bake scripts) |
| soft-rule re-mining on group A only (existing `kb_audit/peptide_sar_kb.py::fit`, unmodified) | `rules_mining/mine_groupA.py`, `test_mine_groupA.py` | see the results section of the report; groups are read from the committed `track_e/source_groups*.json`, never recomputed |

Known limits: retrieval documents/years exist only for the 8-target integrin set; embedding index construction needs the frozen PeptideCLM-2 encoder on EC2/Spark (not run here, only the cache/alignment logic is tested); Boltz cofold input is sequence-based (no non-canonical residues on that path).
