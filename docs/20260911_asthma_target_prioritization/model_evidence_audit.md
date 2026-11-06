# What BioMate currently uses, and how to integrate Life Science Research

Audit date: 2026-09-11. Scope: the running immune encoder, the target-selection research code and saved results, and the existing immunology literature RAG. This is not an exhaustive audit of every BioMate service or model checkpoint.

## Plugin identity and counting units

The local plugin manifest identifies **Life Science Research 1.0.3**, author **OpenAI**. The cached package contains **50 skills**, including a router and analysis helpers; this is not a count of 50 independent databases. The requested asthma workflow names **20 distinct skills across six lanes** (Open Targets is reused in three lanes). The official example is at https://learn.chatgpt.com/use-cases/target-prioritization .

The scripts run targeted public-database requests. They do not, merely by being installed or called, train BioMate's model or inject their records into its weights. This run used the actual cached plugin scripts; the package was found under `.codex/.tmp/plugins/plugins/life-science-research`, rather than the initially inspected active plugin cache.

## Verified current state

| Component | Count and actual use | What this does not establish |
|---|---|---|
| Running B2.1 cell-state encoder | **One primary omic: RNA counts**, plus cell-type labels and study metadata. Latest verified feature manifest: 568,728 retained cells, 1,017 studies, 2,000 HVGs. NB reconstruction, biological/nuisance KL terms, annotation, contrastive and adversarial objectives. | None of the six external evidence lanes is explicitly supplied as retrieved target-prioritization evidence in this run. CELLxGENE can still be an upstream provenance source for the RNA corpus; that is different from querying its target-expression evidence adapter. No clinical/GWAS/PheWAS/literature knowledge input is wired into this encoder. It is a ~1.32M-parameter cell encoder, not the separately planned text reasoning LLM. |
| Target-selection engine | **Three implemented real channels:** genetics, measured perturbation, pathway. Network degree and global effect magnitude are **two null controls**, not additional positive evidence. | Not six fully populated lanes; channel availability depends on substrate. |
| Saved CZI target-selection result | **Two populated channels:** perturbation (7,864 KO targets), pathway (772 TF candidates). Genetics explicitly unpopulated. | No genetics support can be inferred from the measured-screen AUROC. Combination did not beat best single real channel under the saved verdict. |
| Saved SLE target-selection result | **Two populated channels:** genetics (965 targets), pathway (772 TF candidates); no perturbation. Signature from one within-study SLE/normal comparison. | Not cross-cohort replication, and not an asthma-specific implementation. |
| Literature retrieval | **151,367 vectors/articles**, 768-dimensional BGE embeddings, FAISS IndexFlatIP, title/abstract level, 2,000-character cap. Confirmed from S3 `rag_manifest.json`. | Not 151,367 independent pieces of target evidence; not full-paper passage retrieval; article count is not training-set size. |
| Text reasoning LLM path | Code builds four instruction families: ontology grounding, literature-context QA, MSigDB C7 membership, VDJdb examples. | Presence of code is not proof of a successful trained model. The inspected gpt-oss-20b run's saved log failed during import due to incompatible huggingface-hub/transformers versions; no successful checkpoint was demonstrated by that run. Other model runs were not exhaustively audited. |
| Broader collected knowledge | Registry documents MAP-KG, CollecTRI, STRING, pathway GMTs, PrimeKG, ontologies, immune gene sets and genetics/eQTL resources. | Collected/cached resources are not automatically wired into the running encoder. Registry counts are historical documentation unless separately reverified. |

Saved supporting payloads: `raw/current_rag_manifest.json`, `raw/current_target_selection_czi.json`, `raw/current_target_selection_sle.json`, `raw/current_text_llm_training_log.txt`.

Code anchors:
- `/Users/kky/biomate-audit-fix/research/immune_llm_baseline/target_selection.py`: REAL_CHANNELS, NULL_CHANNELS, substrate-specific population, genetics-only Open Targets datatype selection.
- `/Users/kky/biomate-audit-fix/research/immune_llm_baseline/b2_1_xverse_encoder.py`: inputs, config, loss terms and gate.
- `/Users/kky/biomate-audit-fix/research/immune_llm_baseline/build_rag_index.py`: abstract-only index.
- `/Users/kky/biomate-audit-fix/research/immune_llm_baseline/train_immuno_llm.py`: intended text-LLM instruction families.
- `/Users/kky/biomate-immune-llm/docs/program_control/KG_REGISTRY.md`: stored-versus-wired distinction.

## Recommended integration: one evidence system, three uses

### 1. Query-time evidence retrieval and structured computation

Keep the six lanes separately queryable under one coordinator and one entity/provenance registry. Use document RAG for papers and trial narratives; use APIs and typed tables for variants, effect estimates, cohorts, expression and trial status; use graph retrieval for gene/pathway relations. **Do not turn every numeric database into text chunks or build 20 disconnected vector RAGs.** A source adapter is not an independent evidence vote.

Suggested routing:

| Sources | Best immediate role |
|---|---|
| GWAS Catalog, Open Targets genetics, GTEx | Structured variant→locus→gene→disease evidence; fine-mapping/colocalization where available; do not treat nearest-gene annotation as causality. |
| FinnGen, UKB/TOPMed, BBJ, TPMI | Cohort replication and phenome-wide safety/context queries, with release, ancestry, endpoint and sample-overlap metadata. |
| gnomAD | Population frequency, constraint and variant interpretation. Gene constraint is not disease association or direct proof of pharmacological safety. |
| EFO | Normalize disease scope, preserve direct asthma and subtype identities; do not silently broaden to all atopy. |
| ClinicalTrials.gov, ChEMBL, PharmGKB, Open Targets drug evidence | Current clinical and pharmacological context; retain trial status, indication, endpoint, dates and regulatory jurisdiction. Keep known-drug evidence separate from genetic nomination. |
| Entrez/PubMed, PMC, bioRxiv | Hybrid lexical/vector retrieval with precise source passages, publication/preprint status, dates and contradictory findings. |
| NCBI Datasets, BioStudies/ArrayExpress | Dataset discovery and metadata/provenance; actual data ingestion and QC remain separate tasks. |
| HPA, GTEx, CELLxGENE, Bgee | Tissue/cell-state plausibility and quantitative context; expression alone does not establish therapeutic causality. |

The LLM should plan queries, reconcile evidence and explain uncertainty. Statistical tools should compute effects and plots. Store returned records and evidence pointers so an answer can be regenerated after a database update.

### 2. Knowledge-guided biological model training

Preserve the planned knowledge-guided model. Stable, curated gene/pathway edges and disease-relevant genetics can become masks, priors or auxiliary objectives in the machinery bottleneck, rather than remaining only prose retrieved at inference. Matched paired multi-omics and perturbation data should train the corresponding biological heads. The plugin helps find and normalize these inputs; it is not itself a training dataset.

Require matched shuffled/degree controls and component ablations. Split by study/donor/perturbation as appropriate; freeze knowledge releases and remove test-derived labels. Keep known-drug/clinical edges out of a drug-blind target-discovery benchmark. Compare against genetics alone, measured effects alone and simple linear baselines; report a negative result if the learned model does not improve.

### 3. Fine-tune reasoning behavior using evidence-grounded examples

Train the text LLM to use retrieved evidence well: distinguish association from causality, recognize source overlap, compare direct and adjacent phenotypes, cite records accurately, expose missingness, and abstain when evidence is inadequate. Use expert-reviewed examples and explicit conflicting-evidence cases. Do not distill this three-target ranking into a training label or teach the model to memorize today's p-values/trial status.

Evaluate four systems on held-out diseases/targets and time-frozen evidence: base LLM, base+retrieval, tuned+retrieval, and tuned+retrieval+biological-model signals. Measure citation support, numeric fidelity, direct/adjacent phenotype errors, contradiction handling, calibration and ranking utility—not just fluency or a model's self-rated confidence.

## Evidence contracts and independence

At minimum retain: source and release, retrieval time, stable target/disease IDs, PMID/NCT/accession, cohort and ancestry, tissue/cell state, variant and genome build, allele and effect unit, p-value/CI, gene-assignment method, direct-versus-adjacent scope, study-overlap group, null/control, license, and raw-payload checksum.

De-duplicate by original study and cohort, not website. One asthma GWAS exposed by GWAS Catalog, Open Targets and a paper is **one study**, not three corroborations. IL33 and IL1RL1 are ligand/receptor members of the same axis; mechanistic coherence should not be presented as independent target-specific clinical proof. A 1–5 lane score is an ordinal review aid, not a calibrated probability of approval.

Immediate implementation priority: structured genetics + cohort/PheWAS adapters, phenotype normalization and an evidence ledger joined to the existing literature index; then the biological priors/paired-data training path; then evaluate whether fine-tuning adds value beyond retrieval. This recommendation does not alter the running experiment.
