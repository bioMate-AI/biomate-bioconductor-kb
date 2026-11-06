# On-prem LLM — knowledge-corpus scale-up for continued pretraining (CPT)

**Date:** 2026-10-08
**Author:** Yaoyun Zhang · xiaoni5122@gmail.com
**Base model:** Qwen3.8-27B (knowledge-rich ≤27B class)
**Scope:** CPU/data-engineering only — inventory, scale-up plan, mix discipline, and a consolidated *local* knowledge pool. **No training, no GPU** in this task.
**Method anchor:** MedGemma recipe — large domain corpus mixed as a *small fraction* of a dominant general mixture to preserve generic ability (`docs/20261008_GOOGLE_MEDLLM_RL_REFERENCE.md`).

> **Why mix discipline is the whole point.** Our last narrow/heavy CPT+SFT pass regressed param discipline (param-prefill `must_not_fill` 34 → 61) and collapsed parallel/mixed decomposition chains (`20261007_SFT_V3_CLEAN_RETRAIN.md`, memory `project_sft_from_gold_result`). "More knowledge" only helps if the knowledge slice stays a minority of a dominant general mixture. Scaling the corpus and holding the ratio are the same task.

> **Honesty contract for this doc.** Everything under "HAVE NOW" is on local disk and measured. Everything under "PLANNED FETCH" is wired/sized but **not** downloaded — I do not claim a corpus I have not assembled. All token counts are two kinds: (a) manifest figures from a real tokenizer where a manifest exists; (b) my own `chars/4` estimate (labelled `~tok(c/4)`), which runs ~1.5–1.6× higher than the tokenizer figure, so I keep them separate.

---

## STEP 1 — Inventory of what we already have (HAVE NOW)

Two local corpora exist, both git-ignored (large `*.jsonl`; only manifests are tracked):
- `docs/20260912_onprem_llm/midtrain_corpus/` — the **current CPT corpus** (built, used in the midtrain runs).
- `docs/20260912_onprem_llm/data_candidates_v2/` — **collected-but-unused** candidates (`review_status=needs_review`, `eligible_for_training=false`); never promoted into training. Knowledge gold.

### 1a. Current CPT corpus — `midtrain_corpus/`

Per-source, measured by line count + `chars/4` estimate. The tracked `manifest.json` reports a tokenizer-based figure for 11 of the sources (TOTAL 171,280 docs / **36.79M tok**) but **omits `tools_corpus` and `wkg_corpus`**, which were added after the manifest was cut.

| Source | File | docs | ~tok (c/4) | manifest ~tok | Content | License |
|---|---|---:|---:|---:|---|---|
| chebi | chebi_corpus.jsonl | 55,446 | 4.54M | 3.69M | ChEBI chemical-entity ontology verbalized | CC-BY 4.0 (open) |
| go | go_corpus.jsonl | 38,092 | 3.40M | 2.88M | Gene Ontology terms/relations | CC-BY 4.0 (open) |
| hetionet | hetionet_corpus.jsonl | 34,717 | 1.16M | 0.47M | Hetionet biomedical KG edges | CC0 (public domain) |
| db_kg | db_kg_corpus.jsonl | 23,336 | 0.87M | 0.58M | BioMate workflow-DB knowledge graph | internal (ours) |
| hpo | hpo_corpus.jsonl | 17,428 | 1.30M | 1.07M | Human Phenotype Ontology | HPO open (custom OA) |
| internal | internal_corpus.jsonl | 16,487 | 9.86M | 8.97M | BioMate docs/specs/source prose | internal (ours) |
| code | code_corpus.jsonl | 21,003 | 18.61M | 17.25M | Nextflow/Groovy/py workflow code | nf-core MIT / ours |
| **tools_corpus** | tools_corpus.jsonl | 10,532 | 17.09M | *(absent)* 11.30M¹ | Galaxy/Bioconductor tool docs + scientific_context_v2 | Bioconductor Artistic / tool-native |
| gtn | gtn_corpus.jsonl | 848 | 1.69M | 1.62M | Galaxy Training Network tutorials | CC-BY 4.0 |
| workflow_order | workflow_order_corpus.jsonl | 3,152 | 0.70M | 0.62M | Step-ordering / composition sequences | internal (ours) |
| **wkg_corpus** | wkg_corpus.jsonl | 4,049 | 0.43M | *(absent)* | Workflow knowledge-graph prose | internal (ours) |
| edam | edam_corpus.jsonl | 2,356 | 0.19M | 0.14M | EDAM ontology (formats/operations) | CC-BY (open) |
| so | so_corpus.jsonl | 2,403 | 0.15M | 0.12M | Sequence Ontology | open |
| **TOTAL (13 sources)** | | **229,849** | **~60.0M (c/4)** | ~48M (tokenizer)² | | commercial-safe |

¹ from `tools_corpus_manifest.json` (`kept_tokens` 11,300,629; 10,532 docs out of 12,312 tools in; dedup_ratio 0.264).
² tokenizer-based union ≈ manifest 36.79M (11 srcs) + tools 11.30M + wkg ≈ 0.3M ≈ **~48M**. Use `~60M (c/4)` and `~48M (tokenizer)` as the bracket.

**Provenance caveat:** `midtrain_all.jsonl` (169,235 lines) is a **stale** pre-concatenation — it predates the `tools_corpus` and `wkg_corpus` additions (union of the 13 live files = 229,849 docs). Do **not** treat `midtrain_all.jsonl` as the current union; rebuild it from the 13 live files.

**Record schema:** `{id, source, text}` (tools_corpus: `{source, text, tool, version}`). Clean for CPT — plain `text` field, source-tagged.

### 1b. Collected-but-unused candidates — `data_candidates_v2/` (never promoted)

`application_commit=03e369101d…`; all records `eligible_for_training=false` pending review. The **knowledge** subset (not the benchmark/label subset) is what we fold in.

| Source | File | docs | ~tok (c/4) | Knowledge value | Overlap risk |
|---|---|---:|---:|---|---|
| tool_knowledge | tool_knowledge_candidates.jsonl | 12,312 | 24.01M | Full tool affordance: desc, help_text, inputs, outputs, parameters, examples, requirements | **High** — superset of `tools_corpus` (12,312 ⊃ 10,532) |
| nf_program | nf_program_candidates.jsonl | 5,049 | 10.54M | Raw `.nf` code + config + schema + README | Med — overlaps `code_corpus` |
| workflow_spec | workflow_spec_candidates.jsonl | 4,200 | 8.90M | Workflow structure + `real_exec_status` (1,092 verified) | Med — overlaps `workflow_order` |
| composition_rationale | composition_rationale_candidates.jsonl | 9,817 | 1.08M | Tool-compatibility / composition edges | Med — overlaps `db_kg`/`wkg` |
| biomate_run_output | biomate_run_output_candidates.jsonl | 1,707 | 0.96M | **Findings** — real run outputs (regulatory, multitask) | Low — unique |
| git_fix_pair | git_fix_pair_candidates.jsonl | 500 | 0.69M | issue→fix diff pairs | Low — unique |
| official_nextflow_doc | official_nextflow_doc_candidates.jsonl | 412 | 0.36M | Official Nextflow docs | Low — but check redistribution |
| docs | docs_candidates.jsonl | 1,693 | 0.18M | BioMate incident/reference markdown | Low — overlaps `internal` |
| *(benchmarks — excluded from knowledge pool)* | all_/public_benchmark | 1,545 | 0.37M | eval items, NOT CPT knowledge | — held out |

**Knowledge-eligible subset (excl. benchmark label sets):** 8 sources, **35,690 docs, ~46.7M tok (c/4)**.

### 1c. Combined HAVE-NOW ceiling (before dedup)

- midtrain_corpus (13): 229,849 docs / ~60.0M tok (c/4)
- data_candidates_v2 knowledge (8): 35,690 docs / ~46.7M tok (c/4)
- **Naïve union: ~265k docs / ~106.7M tok (c/4).** But `tool_knowledge ⊃ tools_corpus`, `nf_program ≈ code`, `workflow_spec ≈ workflow_order`, `composition ≈ db_kg/wkg` — real dedup lands materially lower (see STEP 4).

---

## STEP 2 — Scale-up plan (PLANNED FETCH), prioritized by value/effort

Ranked by (knowledge value) ÷ (effort + license risk). "Effort" counts engineering + bandwidth, not GPU. All sizes are *target* scopes, not downloaded bytes.

### Tier 1 — the big lever: PMC Open-Access full-text (RELEVANT subset)

- **Source:** NCBI PMC Open Access subset, mirrored on **AWS Open Data** `s3://pmc-oa-opendata` (UNSIGNED/anonymous; no egress cost from us-east-1). Also reachable via PMC OA bulk FTP and E-utilities (`efetch`).
- **License — critical:** fetch **ONLY** the OA subset. Within it, split by license: `*/txt/` CC-BY/CC-BY-SA/CC-BY-NC are redistributable; the **non-commercial (NC)** and "author-manuscript" tranches are usable for *internal model training* but **not for redistributing the text**. **Flag:** keep a `license` field per article and exclude NC from any shareable artifact; the full PMC *comm/* vs *noncomm/* split in the bucket must be preserved.
- **Scope (NOT all of PMC ~5–6M articles):** filter to BioMate's covered domains — genomics, transcriptomics, variant calling, proteomics, single-cell, epigenomics, drug discovery/ADMET, immunology, cryo-EM, clinical/pharmacology. Filter by MeSH terms + journal allow-list + title/abstract keyword gate against the 42 domain tags.
- **Size estimate:** domain-scoped subset ≈ **300k–600k articles**. At ~4k tokens/article (we truncate to 20k chars ≈ 5k tok) → **~1.5B–3.0B tokens** raw; after dedup/quality filtering **~1.0B–2.0B tokens**. This is the dominant *domain* mass.
- **Dedup/quality:** drop <500 chars (already in fetcher), near-dup by MinHash/SHA on normalized text, strip reference lists + boilerplate, language=en gate, dedup against eval sets (litqa2/biomni PMIDs — **mandatory**, MedGemma-style eval-contamination guard).
- **Wiring — ALREADY EXISTS:** `evaluation/local_trial/build_pmc_bulk.py` + `build_pmc_bulk.sh` (boto3 UNSIGNED, parallel, 120s incremental S3 upload) and `build_pmc_eutils.py` + `build_pmc.sh`. **Gap to close:** the current bulk fetcher samples the first N prefixes **blindly** (no domain filter, no license split). The scale-up = add the MeSH/journal/keyword domain gate + per-article license tag. Exact commands stubbed in STEP 4.
- **Effort:** Medium (filter + license split + dedup); fetch is already wired. **Value: highest.**

### Tier 2 — deep tool / method documentation (deeper than tools_corpus)

- **Bioconductor vignettes + man pages:** every Bioconductor package ships `.Rmd`/`.Rnw` vignettes + Rd man pages — method-level prose far richer than the catalog `tools_corpus`. Source: Bioconductor package tarballs (`https://bioconductor.org/packages/release/bioc/`), **Artistic-2.0 / open** (per-package; check DESCRIPTION `License`). ~2,300 packages × ~1 vignette ≈ **~30–60M tokens**. Effort: Medium (R/`tools::Rd2txt`, pandoc for Rmd). Value: high (directly lifts tool-knowledge grounding).
- **Protocols:** **protocols.io** public protocols (CC-BY by default on public ones — verify per protocol; API available) + **Nature Protocols** abstracts/open subset (most are paywalled — **flag non-redistributable**; use only OA ones + PMC-mirrored). Bio-protocol (many OA). Size: **~10–30M tokens** OA-only. Effort: Medium; Value: high for procedural knowledge.
- **Open textbooks/reviews:** PMC OA review articles (already captured by Tier-1 filter on `publication_type=Review`), plus open bioinformatics textbooks (e.g. "Computational Genomics with R", "Modern Statistics for Modern Biology/Holmes-Huber" — CC-BY-NC-SA, **flag NC**), Galaxy Training Network (already have; CC-BY — can expand). Size: **~5–15M tokens**. Effort: Low–Medium; Value: medium-high (pedagogical, well-structured).
- **Method papers:** subset of Tier-1 restricted to tool/method-introduction papers (DESeq2, Salmon, STAR, GATK, Seurat, CellRanger, AlphaFold, etc.) — highest value per token; curate a seed DOI list from our 12,312-tool catalog's citations. Size: **~5–20M tokens**. Effort: Low (DOI list → efetch). Value: very high.

### Tier 3 — fold in the unused local knowledge (HAVE NOW, zero fetch)

- `data_candidates_v2` knowledge subset (STEP 1b): **tool_knowledge (12,312), composition_rationale (9,817), biomate_run_output findings (1,707), git_fix (500), official_nextflow_doc (412), docs (1,693), nf_program (5,049), workflow_spec (4,200)**. Already local; just needs dedup + provenance labelling + promotion gate. **This is the cheapest, highest-certainty win** — done in STEP 4.

### Tier 4 — keep the DB-derived knowledge (HAVE NOW, keep)

- Tool docs + `scientific_context_v2` (via `tools_corpus`/`tool_knowledge`), workflow structure (`workflow_order`/`workflow_spec`), composition edges (`db_kg`/`wkg`/`composition_rationale`) from `backend/database/galaxy_ai_tools.db` (4,210 workflows / 12,312 tools). Keep as the BioMate-specific grounding slice; refresh from DB when the catalog updates.

### Scale-up summary table

| Tier | Source | Status | Est. size (tok) | License | Effort | Value |
|---|---|---|---|---|---|---|
| 1 | PMC OA full-text (domain-scoped) | PLANNED (fetcher wired) | 1.0–2.0B | CC-BY/BY-SA (+NC internal-only, flagged) | Med | ★★★★★ |
| 2a | Bioconductor vignettes + man pages | PLANNED (new fetcher) | 30–60M | Artistic-2.0/open | Med | ★★★★ |
| 2b | Protocols (protocols.io/bio-protocol OA) | PLANNED (new fetcher) | 10–30M | CC-BY (NatProt mostly paywalled — flagged) | Med | ★★★★ |
| 2c | Open textbooks/reviews | PLANNED | 5–15M | mixed (NC flagged) | Low-Med | ★★★ |
| 2d | Method papers (DOI-seeded PMC) | PLANNED | 5–20M | OA subset only | Low | ★★★★★ |
| 3 | data_candidates_v2 knowledge | **HAVE NOW** | ~47M (c/4) pre-dedup | internal/MIT/open | Low | ★★★★ |
| 4 | DB-derived (tools/workflow/KG) | **HAVE NOW** | in midtrain ~48M | internal/Artistic | Low | ★★★ |

**Planned domain mass after Tier-1+2 ≈ 1.1–2.1B tokens**, dominated by PMC. HAVE-NOW domain mass ≈ 100M tokens (c/4) pre-dedup.

---

## STEP 3 — Mix discipline (MedGemma-style), the load-bearing design

**The failure mode we are designing against:** heavy/narrow CPT→SFT regressed param-prefill `must_not_fill` 34→61 and collapsed decomposition chains. MedGemma's control is the *ratio*: domain data entered at **2% weight** (vision-encoder stage) and **10% weight** (decoder continued-pretraining) over the *original dominant Gemma-3 general mixture*; the result was large domain gains with only **minor** general-benchmark drops (MMLU-Pro −4.5 at 4B; larger −~7.3 at 27B) (`20261008_GOOGLE_MEDLLM_RL_REFERENCE.md` §1, §3).

### 3a. Recommended domain:general ratio for Qwen3.8-27B CPT

- **Target domain weight: 10% (ceiling 15%), general/instruction: ≥85%.** This mirrors MedGemma's decoder-stage 10% and respects that retention cost grows with model size (27B ⇒ be conservative, stay at the low end).
- **Rationale for a *token-weight* ratio, not a dataset-size ratio:** even though our *available* domain tokens (1–2B after Tier-1) could dwarf a small general set, we **down-weight** the domain slice at the sampler so it is 10% of tokens-seen. The whole point is that scaling the corpus does **not** mean scaling its mixture weight — more domain knowledge available, same minority weight.
- **Do NOT** repeat the last mistake of training predominantly on the narrow slice. The corpus got bigger; the weight stays small.

### 3b. Which general/instruction data to co-train (the dominant ≥85%)

- **General pretraining text:** an open general-web/code/math mixture to stand in for "the original Gemma-3 mixture" that we don't have for Qwen. Candidates (all OA/open): **FineWeb-Edu** (ODC-BY), **The Stack v2** permissive subset (code), **open math** (OpenWebMath / FineMath), **Wikipedia** (CC-BY-SA). This is the generic-ability anchor.
- **Instruction/param-discipline anchor:** co-train the **854 `must_not_fill` param-discipline anchors** we already built (memory `project_sft_from_gold_result`) + general instruction data (e.g. Tülu-3 SFT mix / OpenHermes — open) so the model keeps "don't hallucinate params / don't over-fill" behavior. This directly targets the thing that regressed.
- **Keep Qwen base behavior:** because Qwen3.8-27B is already knowledge-rich, the general slice primarily *protects* existing ability rather than teaching new general skill — argues for a **KL/replay-style** anchor (replay of a generic slice every step) over a one-shot general warmup.

### 3c. Forgetting-check eval (run BEFORE/AFTER every CPT variant)

Two panels, reported together — MedGemma Table-12 discipline (retention) + Table-3/11 (gain), plus an **OOD** split (their headline evidence was OOD):

- **Forgetting / retention panel (must stay flat, tolerance ≤ −3 pts):**
  - General: MMLU / MMLU-Pro, GSM8K or a math set, a code eval (HumanEval-ish), IFEval (instruction-following).
  - **BioMate-specific retention guards (the real regressors):** `param_prefill` `must_not_fill` count (must stay ≤ base ~34, hard gate — this is the exact metric that blew up), `routing` accuracy (≥80% target), `stability` cross-run (≥90%).
- **Knowledge-gain panel (must go up):** `litqa2` (biomedical literature QA), `biomni_eval1` (biomedical recall ≥70%), `findings` quality (run-output grounding), `biomni`/`admet` where relevant.
- **OOD/held-out split:** evaluate on topologies/sources *outside* the CPT generators — our analogue of MedGemma's CXR14-OOD is `decomposition_real` (out-of-synthetic) vs in-family `decomposition_v2`. Contamination guard: dedup CPT corpus against all eval PMIDs/items (mandatory).
- **Decision rule:** accept a CPT checkpoint only if **knowledge-gain panel ↑ AND retention panel within −3 pts AND `must_not_fill` ≤ base**. If `must_not_fill` rises, the domain weight is too high — cut it, do not patch the eval (per CLAUDE.md benchmark discipline).

### 3d. Size sweep (MedGemma reports 4B+27B; retention cost is size-dependent)

Run the mix at ≥2 sizes (e.g. the 9B we already have + Qwen3.8-27B) and report capability lift **and** retention cost per size, since the 27B is expected to forget *more* at a given domain weight (MedGemma: −7.3 at 27B vs −4.5 at 4B). Pick the domain weight per size, not one global number.


---

## STEP 4 — Consolidated local knowledge pool (BUILT NOW)

Builder: `evaluation/local_trial/build_knowledge_pool.py` (reproducible; CPU-only, no fetch).
Output: `docs/20260912_onprem_llm/knowledge_pool_v1/` — `knowledge_pool.jsonl` (310 MB, git-ignored) + tracked `manifest.json` + `.gitignore` (same convention as `data_candidates_v2`: track manifest, ignore large jsonl).

**Record schema (every line carries provenance):**
```json
{"id":"chebi:0","text":"ChEBI compound: …",
 "provenance":{"pool_source":"chebi","orig_source":"chebi","orig_id":"CHEBI:100",
               "license":"CC-BY-4.0","tier":"ontology","intended_task":"cpt_knowledge"}}
```

**Consolidation rules applied (documented in manifest):**
- **Dedup:** exact-text `sha256(whitespace-collapsed, lowercased)`, first-seen wins.
- **Supersession:** `tools_corpus` **excluded** — `tool_knowledge` (12,312) is the richer superset of the 10,532-doc `tools_corpus`. Keeping both would double-count the tool slice.
- **Pointer-only:** `docs_candidates` (1,693) has no body (overlaps `internal_corpus`) → recorded as pointers, body excluded.
- **Held out:** `all_benchmark`/`public_benchmark` (eval items) excluded from the knowledge pool — they are the forgetting-check/gain evals, not CPT fuel.

**Built result — 248,035 records, ~60.9M tokens (c/4), 5,279 exact dups dropped:**

| pool_source | tier | in | kept | dup-dropped | kept ~tok (c/4) | license |
|---|---|---:|---:|---:|---:|---|
| chebi | ontology | 55,446 | 55,446 | 0 | 3.67M | CC-BY-4.0 |
| go | ontology | 38,092 | 38,092 | 0 | 2.87M | CC-BY-4.0 |
| hpo | ontology | 17,428 | 17,428 | 0 | 1.06M | HPO-open |
| so | ontology | 2,403 | 2,403 | 0 | 0.12M | open |
| edam | ontology | 2,356 | 2,356 | 0 | 0.14M | CC-BY |
| hetionet | ontology | 34,717 | 34,715 | 2 | 0.45M | CC0 |
| gtn | T2c-tutorial | 848 | 848 | 0 | 1.62M | CC-BY-4.0 |
| internal | internal-prose | 16,487 | 16,487 | 0 | 8.96M | internal |
| db_kg | T4-DB | 23,336 | 23,307 | 29 | 0.57M | internal |
| wkg | T4-DB | 4,049 | 4,049 | 0 | 0.38M | internal |
| workflow_order | T4-DB | 3,152 | 3,152 | 0 | 0.62M | internal |
| code | T4-DB | 21,003 | 21,001 | 2 | 17.24M | nf-core-MIT/internal |
| tool_knowledge | T4-DB | 12,312 | 12,300 | 12 | 5.87M | Bioconductor-Artistic/tool-native |
| composition_rationale | T4-DB | 9,817 | 4,899 | 4,918 | 0.28M | internal |
| biomate_run_output | T3-findings | 1,707 | 1,571 | 136 | 0.58M | internal |
| git_fix_pair | T3-repair | 500 | 496 | 4 | 0.59M | internal |
| nf_program | T4-DB | 5,049 | 4,873 | 176 | 9.21M | nf-core-MIT/internal |
| workflow_spec | T4-DB | 4,200 | 4,200 | 0 | 6.42M | internal |
| official_nextflow_doc | T2-method-doc | 412 | 412 | 0 | 0.28M | nextflow-io (verify redistribution) |
| **TOTAL** | | **253,314** | **248,035** | **5,279** | **~60.9M** | commercial-safe (1 flagged) |

**Honest limits of this dedup:** exact-text only. Near-duplicates (same tool verbalized two ways; `nf_program` vs `code_corpus` paraphrases) are **not** collapsed beyond the `tools_corpus` supersession and the 176 exact `.nf` matches. `composition_rationale` lost ~50% to exact dups (compatibility edges repeat) — expected. A MinHash/LSH near-dedup pass is a cheap planned refinement before CPT.
**License flag:** `official_nextflow_doc` carries `license_note: verify before external redistribution` — safe for internal training, **do not redistribute** that slice.

### 4b. PLANNED fetchers — exact commands (NOT run; sizing only)

PMC fetchers already exist and are wired to AWS Open Data; the scale-up adds a domain+license gate.

```bash
# Tier-1 PMC OA full-text — EXISTING wired fetcher (blind sample today):
#   evaluation/local_trial/build_pmc_bulk.py  (boto3 UNSIGNED s3://pmc-oa-opendata)
# Smoke (size only — 2k articles, no domain filter yet):
PMC_ARTICLES=2000 python3 evaluation/local_trial/build_pmc_bulk.py \
    --out /tmp/pmc_smoke.jsonl --n 2000 --workers 32   # ~8–10M tok, verifies ~5k tok/article

# Scale-up GAP to implement before a real pull (do NOT run a TB download here):
#   (1) domain gate: keep article iff MeSH/journal/title matches the 42 BioMate domain tags
#   (2) license split: tag each from the bucket's comm/ vs noncomm/ prefix; exclude NC from shareable
#   (3) eval-contamination dedup: drop any PMID in litqa2/biomni eval sets

# Tier-2a Bioconductor vignettes/man pages — NEW fetcher to add (R tooling):
#   list release packages, download tarball, extract vignettes/*.Rmd + man/*.Rd, pandoc->text
# Tier-2b protocols.io OA — NEW fetcher (public API, CC-BY only):
#   GET https://www.protocols.io/api/v4/protocols?filter=public   (store license per record)
# Tier-2d method papers — seed DOIs from catalog tool citations, then:
#   python3 evaluation/local_trial/build_pmc_eutils.py --out method_papers.jsonl --dois dois.txt
```

To rebuild the HAVE-NOW pool at any time: `python3 evaluation/local_trial/build_knowledge_pool.py`.
Union-for-training = `knowledge_pool_v1/knowledge_pool.jsonl` directly (already a single provenance-labelled file).

---

## DELIVER — summary

1. **Current corpus (HAVE NOW).** `midtrain_corpus/` = 13 live sources, **229,849 docs, ~48M tok (tokenizer) / ~60M (c/4)**; tracked manifest under-reports (omits `tools_corpus`+`wkg`). `data_candidates_v2/` knowledge subset = **35,690 docs, ~46.7M tok (c/4)**, never promoted. `midtrain_all.jsonl` is a stale pre-concat — rebuild from the 13 live files.
2. **Scale-up plan.** Tier-1 **PMC OA domain-scoped full-text (~1–2B tok, CC-BY; fetcher wired, needs domain+license gate)** is the big lever; Tier-2 Bioconductor vignettes (30–60M), protocols (10–30M, NatProt paywalled-flagged), open reviews/method papers (10–35M); Tier-3 fold in the local candidates (done); Tier-4 keep DB-derived. Planned domain mass ≈ **1.1–2.1B tok**.
3. **Mix discipline.** Domain **10% weight (ceiling 15%)** over **≥85% dominant general/instruction mixture** (FineWeb-Edu + permissive code/math + Wikipedia + Tülu/OpenHermes-style instruction + our 854 `must_not_fill` anchors). Forgetting-check = retention panel (MMLU/-Pro, math, code, IFEval + BioMate guards `must_not_fill`≤34, routing≥80%, stability≥90%) run beside the gain panel (litqa2/biomni/findings) and an OOD split (`decomposition_real`); accept only if gain↑ AND retention within −3 AND `must_not_fill`≤base. Run at ≥2 sizes (9B + 27B). **This ratio discipline is the fix for the prior narrow-CPT param/routing regression.**
4. **Consolidated local pool (BUILT).** `knowledge_pool_v1/knowledge_pool.jsonl` — **248,035 provenance-labelled records, ~60.9M tok (c/4)**, 5,279 exact dups dropped, `tools_corpus` superseded by `tool_knowledge`, benchmarks held out; reproducible via `build_knowledge_pool.py`; manifest tracked, body git-ignored.

**Honesty:** HAVE-NOW = everything in §1 and §4 (on disk, measured). PLANNED FETCH = §2/§4b (wired + sized, **nothing downloaded**). Licenses are real and OA/open except the one `official_nextflow_doc` redistribution flag and the PMC-NC/NatProt tranches, which are internal-training-only and flagged. No corpus is claimed that was not assembled.
