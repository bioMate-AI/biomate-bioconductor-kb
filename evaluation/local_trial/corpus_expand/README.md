# Corpus expansion suite (GPU/disk box)

Grows the mid-train corpus beyond the internal DB with external, mostly-open domain text, applying
consistent **quality → PII → MinHash near-dedup → decontamination** (shared `common.py`). Runs on the
box (needs bandwidth + disk); not on the laptop.

## Sources
| Script | Source | Notes |
|---|---|---|
| `fetch_pmc.py` | PMC Open-Access | **ALL topics** (no topic filter — decided); filter by **license** only + quality. Uniform sample to `--limit`. |
| `fetch_bioconductor.py` | Bioconductor pkg source | vignettes (prose+code) + man pages; the code-gen grounding source too |
| `fetch_workflows.py` | Dockstore TRS v2 | **all engines**: CWL/WDL/Nextflow/Snakemake/Galaxy, kept as code |
| `fetch_forums.py` | Biostars + Bioc support | Q&A (question + top answers); mirrors real routing/diagnosis tasks |
| `fetch_vendor_docs.py` | instrument-vendor PDFs | prose **+** error-table → **grounded `diag_fix` SFT**; needs curated ToS-cleared URL list |

## Order (or just `bash run_all.sh`)
1. `build_decontam.py --sft sft_enriched.jsonl --holdout holdout.jsonl --out decontam.pkl`
2. each `fetch_*.py … --decontam decontam.pkl`
3. `merge_external.py --dir corpus/ --out external_corpus.jsonl` (cross-source dedup)
4. drop `external_corpus.jsonl` into `midtrain_corpus/`, re-run `concat_dedup_corpus.py` to refresh `midtrain_all.jsonl`

## Deps
`pip install datasketch pymupdf` (+ `trafilatura` optional for HTML). `common.Deduper` needs datasketch.

## Important
- **Decontamination is mandatory** — run `build_decontam.py` first so no corpus doc leaks the
  holdout/SFT (n-gram overlap). Skipping it inflates every downstream metric.
- **Licensing:** PMC keeps per-article license in provenance; set `PMC_LICENSE` to restrict for
  commercial use, or leave empty to keep all OA (honor NC/ND downstream). **Vendor docs are
  proprietary** — only list officially-public, ToS-cleared PDFs in `vendor_docs.tsv`
  (`url<TAB>vendor<TAB>instrument<TAB>tos_note`); the manifest records the ToS note per doc. Get
  legal sign-off on the vendor set before large-scale collection.
- **Code-gen SFT** (R/Python) should be built from `fetch_bioconductor.py` vignette *code* chunks
  (execution-verified via `run_code`), NOT the noisy tools-DB code fields.
- Every fetcher writes a `*_manifest.json` (kept/dropped by reason, tokens, ToS) — **audit it before
  training**; the vendor error-table parser especially needs per-vendor tuning.
