# BioMate local-LLM training curriculum — knowledge dimensions × stage

What the model must learn, from which source, in which representation, at which stage
(mid-training = declarative knowledge; SFT = task behavior; RL = grounded outcome; RAG = volatile).
Companion to [MIDTRAIN_MIX.md](MIDTRAIN_MIX.md), [SFT_DATA_REVIEW.md](SFT_DATA_REVIEW.md),
[LOCAL_LLM_PROPOSAL.md](LOCAL_LLM_PROPOSAL.md).

## 1. Knowledge dimensions → representation → stage
| Dimension | Source | Representation | Stage |
|---|---|---|---|
| Domain literature | peS2o bio, PMC oa_comm, bioRxiv (mining) | raw text | mid-train |
| **Bioconductor books/vignettes/workflows** (OSCA, CompGenomicsR, bioc workflows) | bioc.org + our R corpus | text + code | mid-train (+SFT QA) |
| Tool docs/tutorials | `help_text`/`examples`/`rawText` + upstream | text | mid-train |
| **Tool FUNCTIONS & usages** (per-function semantics) | `best_practice_functions`, `examples`, vignettes | function-granular text + code | mid-train → SFT (function/param selection) |
| **Workflow biological ORDER** | `.nf` code, `workflow_json`/`step_metadata` DAG, GTN, methods | **verbalized ordered step-DAG** + code | mid-train (canonical order) → SFT (decomposition) → RL (chain runs, I/O-compatible) |
| **Data TYPES** (FASTQ/BAM/VCF/h5ad/mzML/MRC/SMILES/PDB…) | EDAM data ontology + `tool_compatibility` (9,656 edges) + format specs | verbalized ("X consumes FASTQ→BAM") | mid-train → SFT (format/compat tasks) |
| **Data SOURCES** (GEO/SRA/UniProt/Ensembl/ClinVar/PDB/ChEMBL…) | per-DB docs/schema | schema/purpose/fields verbalized | mid-train (schema); SFT (source selection+query); **RAG (records)** |
| **Instruments** (specs, error-fixing) | instrument manuals + fix materials | text | mid-train (specs); SFT (troubleshoot); RL (fix resolves) |
| **KGs / ontologies** (Hetionet/PrimeKG/Monarch; GO/EDAM/SO/HPO/ChEBI/MeSH) | external KGs + internal `tool_compatibility`/step-graph | **verbalize triples→sentences** | mid-train |

## 2. Stage division of labor
- **MID-TRAINING = declarative "knowing":** what tools/functions/data-types/DB-schemas/instruments ARE,
  their relations, canonical step ORDER, and domain literature. Raw + verbalized text/code.
- **SFT = procedural "doing" (production format, verifier-gated):** intent **decomposition** (ordering),
  routing, **function + parameter** selection, data-format handling, **data-source** selection, output
  interpretation, **tool + instrument error diagnosis**.
- **RL = grounded "working" (reward = execution/verifier/correction):** chain actually runs & steps are
  I/O-compatible, params execute, fix resolves the error, interpretation faithful to outputs, user
  correction satisfied. (Periodic-style "reward from reality".) This is where order/autofix quality is truly enforced.
- **RAG (inference, not trained):** volatile catalog + DB records.

Order & function-usage are **taught in mid-train (verbalize DAG + function docs + code) → practiced in
SFT (decomposition/function tasks) → verified in RL (chain runs, call executes)** — no single stage owns them.

## 3. Expanded resource list (added per review)
**Mid-training corpus (extend beyond current ~28M internal core):**
- Literature: peS2o bio (ODC-BY), PMC oa_comm, bioRxiv (mining).
- **Bioconductor books/vignettes** + tool docs + all workflow **code** (have) + GTN (have).
- **Textbooks/education:** open bioinformatics textbooks, **The Carpentries/Data Carpentry**, **Rosalind**.
- **Q&A:** Biostars (CC-BY), **Bioinformatics Stack Exchange** (CC-BY-SA), Bioconductor support, SEQanswers.
- **Encyclopedic:** Wikipedia bio (CC-BY-SA).
- **KGs/ontologies (verbalized):** external Hetionet(CC0)/PrimeKG(MIT)/Monarch + GO/EDAM/SO/HPO/ChEBI/MeSH;
  **internal KG** = `tool_compatibility` (9,656 edges) + EDAM ops/topics + workflow step-DAGs → sentences.
- **More workflow code:** Snakemake, **CWL/WDL**, WorkflowHub/Dockstore, The Stack bio subset.
- **Data-type + DB-schema + instrument-manual** verbalizations.
- Keep ~75% general **replay** (anti-forgetting). Exclude KEGG; keep volatile records in RAG.

**SFT (grounded from the same sources, production-format):** decomposition (GTN/chains/methods),
routing rationale (scientific_context), function/param (schema+code, scale 5–10×), data-format,
data-source selection, output interpretation, tool+instrument diagnosis (de-noised real_exec_err +
instrument fix materials), Biostars/SE QA.

**RL:** execution/verifier/correction rewards on chain-runnability, param-executability, fix-resolution,
interpretation-fidelity.

## 4. Multimodal (the base is Qwen3-VL; vision tower verified)
- **Vision SFT track (T17), separate/later:** image→interpretation, grounded/verifiable. Data: figures
  **rendered from known data** (DE→volcano, QC→plots; gold computable) + **PMC-OA figure–caption pairs**
  + domain images (microscopy, gels, cryo-EM density, IGV). LoRA on language layers; vision tower reused.
- **Multimodal mid-training** (interleaved image-text from papers): heavier, defer unless figure quality needs it.
- **Sequence:** text mid-train + SFT + RL first (bulk of tasks); **vision SFT in parallel/after** (tower already works).

## 5. Immediate off-GPU build items (highest value, license-clean)
1. **Internal-KG verbalizer** — `tool_compatibility` + EDAM + step-DAG → text (distinctive, ours).
2. **Workflow-order verbalizer** — `workflow_json`/`step_metadata` → ordered natural-language procedures.
3. Extend `fetch_external_corpora.sh` with KGs/ontologies + textbooks + Stack Exchange + CWL/WDL.

## 6. Protocol collections (added) — real protocols > synthetic
Train-safe (CC-BY only): **Bio-protocol** (CC-BY subset), **protocols.io** (CC-BY, via API), **STAR
Protocols** (CC-BY), **Protocol Exchange** (Nature's OPEN repo, CC-BY). **Exclude from training
(copyrighted):** Nature Protocols (Springer), Current Protocols (Wiley), JoVE — RAG/abstracts only.
Use for: (a) **decomposition SFT** — a real protocol is a gold ordered multi-step procedure (replaces
synthetic); (b) **protocol-QC/troubleshooting SFT** from real QC/notes; (c) mid-training procedural text.
