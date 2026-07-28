# BioMate Resource Registry — Data, Methods, Tools & Models (SOTA-forward)

**Date:** 2026-07-27
**Scope:** every external resource the target-discovery / stratification / harmonization / LLM work draws on — with citation, link, and rationale.
**Principle (design split):** use **latest SOTA** where accuracy of the *evidence/model* matters (integration, antigen prediction, perturbation, per-client models); use **established, transparent, citable** methods at the *decision layer* (ranking, gate-3) — but always cite the **latest version** of those. Both are marked below.

> Legend: **[SOTA]** current state-of-the-art · **[STD]** established/transparent-by-design · **[REF]** reference data.

---

## 1. Data & knowledge bases (public)
| Resource | Link | We use it for |
|---|---|---|
| **Open Targets Platform** (Ochoa 2021 NAR 49:D1302, 10.1093/nar/gkaa1027; Buniello 2025 NAR 53:D1467, 10.1093/nar/gkae1128) **[REF]** | https://platform.opentargets.org · https://api.platform.opentargets.org/api/v4/graphql | target–disease association, tractability, safety prioritisation (scorecard evidence) |
| **gnomAD v4** (Chen 2024 Nature; LOEUF Karczewski 2020 Nature 581:434) **[REF]** | https://gnomad.broadinstitute.org | genetic-constraint (LOEUF) safety axis |
| **ChEMBL** (Zdrazil 2024 NAR) **[REF]** | https://www.ebi.ac.uk/chembl | chemistry / bioactivity, tractability |
| **STRING v12** (Szklarczyk 2023 NAR) **[REF]** | https://string-db.org | PPI network for the network-propagation ranker |
| **GWAS Catalog** (Sollis 2023 NAR) **[REF]** | https://www.ebi.ac.uk/gwas | genetic associations |
| **Reactome** (Milacic 2024 NAR) **[REF]** | https://reactome.org | pathway/biological-relevance |
| **CELLxGENE Census** (CZI, 2024) **[SOTA/REF]** | https://cellxgene.cziscience.com | harmonised single-cell reference → cell-type specificity |
| **Human Protein Atlas** (Uhlén 2015 Science; 2024 updates) **[REF]** | https://www.proteinatlas.org | tissue/cell specificity, safety |
| **LINCS L1000 / CMap** (Subramanian 2017 Cell 171:1437) **[REF]** | https://clue.io | perturbation signatures for repurposing (signature reversal) |
| **AMP AIM** (FNIH/NIH) **[REF]** | https://fnih.org · https://ampaim.omrf.org | autoimmune 3D multi-omic atlas (cohort substrate) |
| **3TR / ADEx** (IMI) **[REF]** | https://3tr-imi.eu · ADEx portal | cross-disease autoimmune meta-analysis |
| **ImmPort / ImmuneSpace / ImmGen** **[REF]** | https://www.immport.org | immune profiling reference cohorts |
| **HuBMAP · Human Cell Atlas · GTEx · TCGA** **[REF]** | https://hubmapconsortium.org · https://www.humancellatlas.org · https://gtexportal.org · https://portal.gdc.cancer.gov | harmonised multi-omic references |
| **VDJdb · IEDB · McPAS-TCR · HLA Ligand Atlas** **[REF]** | https://vdjdb.cdr3.net · https://www.iedb.org · https://hla-ligand-atlas.org | TCR–epitope / immunopeptidome (antigen resolution) |
| **DICE · OneK1K · eQTLGen** **[REF]** | https://dice-database.org · https://onek1k.org · https://www.eqtlgen.org | single-cell eQTL / genetics→cell-type |
| **scPerturb** (Peidli 2024 Nat Methods) **[SOTA/REF]** | http://projects.sanderlab.org/scperturb | harmonised perturbation datasets |

## 2. Target scoring / prioritisation methods (decision layer)
| Method | Citation / link | Use · type |
|---|---|---|
| OT association harmonic-sum | Ochoa 2021/2023, Buniello 2025 NAR — https://platform-docs.opentargets.org/associations | rank aggregation **[STD]** |
| Genetic support of clinical success | Nelson 2015 Nat Genet 47:856 (10.1038/ng.3314); **Minikel 2024 Nature 629:624** (10.1038/s41586-024-07316-0) | weight genetic axis **[STD]** |
| Target Development Level (tractability) | Oprea 2018 Nat Rev Drug Discov 17:317 (10.1038/nrd.2018.14) | tractability **[STD]** |
| OT Target Prioritisation traffic-light panel | Buniello 2025 NAR 53:D1467 | prioritisation panel **[STD]** |

## 3. Stratification / integration methods — **use latest SOTA**
| Method | Citation / link | Use |
|---|---|---|
| **scVI / scANVI** | Lopez 2018 Nat Methods; Xu 2021 Mol Syst Biol — https://scvi-tools.org **[SOTA]** | deep single-cell integration (top scIB performer) |
| **scArches** reference mapping | Lotfollahi 2022 Nat Biotech **[SOTA]** | map new cohorts onto a reference (harmonisation) |
| **Harmony** | Korsunsky 2019 Nat Methods **[SOTA]** | fast batch integration (first-to-try) |
| Scanorama · FastMNN · LIGER | Hie 2019 · Haghverdi 2018 · Welch 2019 **[SOTA]** | integration menu (no universal winner) |
| **Single-cell foundation models: scGPT, Geneformer, UCE, scFoundation** | Cui 2024 Nat Methods; Theodoris 2023 Nature; Rosen 2023; Hao 2024 **[SOTA]** | zero/few-shot cell embedding, annotation, perturbation |
| **MOFA+ / MEFISTO** | Argelaguet 2020 Genome Biol; Velten 2022 Nat Methods — https://biofam.github.io/MOFA2 **[SOTA]** | multi-omic factor integration → endotypes |
| totalVI / MultiVI · DIABLO | scvi-tools · Singh 2019 Bioinformatics **[SOTA]** | multimodal / supervised integration |
| **Integration evaluation: scIB, LISI** | **Luecken 2022 Nat Methods** (10.1038/s41592-021-01336-8); Korsunsky 2019; Tran 2020 Genome Biol; 2025 Nat Methods multimodal benchmark | select-and-evaluate + over-correction detection (our `integration_benchmark`) **[SOTA]** |

## 4. Antigen / immunopeptidomics — **SOTA (the moat lane)**
| Method | Citation / link | Use |
|---|---|---|
| **NetMHCpan-4.1 / NetMHCIIpan-4.x** | Reynisson 2020 NAR **[SOTA]** | HLA-I/II binding prediction (focus DP/DQ gap) |
| **MHCflurry 2.0** | O'Donnell 2020 Cell Systems **[SOTA]** | MHC-I presentation prediction |
| nf-core/airrflow · hlatyping · epitopeprediction | https://nf-co.re **[SOTA]** | TCR/BCR repertoire · HLA typing · epitope prediction (existing in catalog) |

## 5. Causal / genetics / perturbation
| Method | Citation | Use |
|---|---|---|
| **GEARS** (GPU) | Roohani 2024 Nat Biotech (10.1038/s41587-023-01905-6) **[SOTA]** | perturbation-response prediction (validation stage) |
| Mendelian randomisation (GMRP/MAGMA/LDSC/TorchGWAS) | Willer 2010; de Leeuw 2015; Bulik-Sullivan 2015 **[STD]** | causal genetic support |

## 6. Repurposing
| Method | Citation | Use |
|---|---|---|
| Connectivity Map | **Lamb 2006 Science 313:1929** (10.1126/science.1132939); Subramanian 2017 Cell **[STD]** | signature-reversal ranking (our `repurposing_signature_reversal`) |

## 7. Clinical-evaluation frameworks (the gate ladder)
| Framework | Citation | Use |
|---|---|---|
| **FDA–NIH BEST** | BEST Resource 2016 **[STD]** | predictive vs prognostic, interaction testing |
| **PROFILE** (canonical gate-3 failure) | Parkes 2024 Lancet Gastro Hepatol (10.1016/S2468-1253(24)00034-7) | gate-3 example |
| REMARK · STARD · CLSI EP05/06/15 | McShane 2005 JNCI 97:1180; STARD 2015; CLSI | reporting/analytical standards (gate 1/2) |

## 8. Metadata harmonization & ontologies — **grounded + human-in-the-loop (never LLM-alone)**
| Resource | Link | Use |
|---|---|---|
| **EFO · Mondo · HPO · Cell Ontology · UBERON** | https://www.ebi.ac.uk/efo · https://mondo.monarchinitiative.org · https://hpo.jax.org · http://obofoundry.org/ontology/cl · uberon | controlled vocabularies for metadata mapping |
| **text2term** (Gonçalves 2024 *Database* 2024:baae119, 10.1093/database/baae119) · MetaHarmonizer | https://github.com/ccb-hms/ontology-mapper **[SOTA]** | deterministic ontology mapping (our `metadata_harmonizer`) |
| **OMOP CDM · FHIR · CDISC SDTM · Phenopackets** | https://ohdsi.github.io/CommonDataModel · https://hl7.org/fhir · https://www.cdisc.org · http://phenopackets.org | clinical-data schemas |
| Provenance: **BRISQ** (Moore 2011) · **MIxS** (Yilmaz 2011) · MIAME · SPREC | https://gensc.org/mixs | QC-triage provenance fields (our `cohort_qc_triage`) |

## 9. ML / LLM infra & models — **latest SOTA for per-client adaptation**
| Resource | Citation / link | Use |
|---|---|---|
| **Ludwig** | Molino 2019; https://ludwig.ai **[SOTA]** | declarative multimodal + LLM training (`ml_training`, in-repo) |
| **vLLM** | Kwon 2023 SOSP; https://docs.vllm.ai **[SOTA]** | multi-adapter serving (`infra/vllm`) |
| **LoRA / QLoRA / PEFT** | Hu 2021; Dettmers 2023; https://github.com/huggingface/peft **[SOTA]** | parameter-efficient per-client fine-tuning |
| **MLflow** | https://mlflow.org **[SOTA]** | experiment tracking / per-client eval |
| Base models (pick latest at build time) | e.g. current small open LLMs for CPU LoRA; larger for GPU QLoRA **[SOTA]** | per-client adapters (data isolation) |

## 10. Orchestration
| Tool | Citation / link | Use |
|---|---|---|
| **Nextflow** | Di Tommaso 2017 Nat Biotech; https://www.nextflow.io **[SOTA]** | workflow execution (all workflows) |
| **nf-core** | Ewels 2020 Nat Biotech; https://nf-co.re **[SOTA]** | best-practice pipelines (rnaseq, scrnaseq, sarek, airrflow, hlatyping…) |

---

## Design rationale (why this split, and where "latest SOTA" applies)
- **Evidence-generation & models → latest SOTA** (integration: scVI/scANVI/scArches + foundation models; antigen: NetMHCIIpan/MHCflurry; perturbation: GEARS; per-client: Ludwig+LoRA/QLoRA+vLLM). Accuracy of the raw signal is the whole point here.
- **Decision layer → established + transparent, cited to the latest version** (OT harmonic-sum ranking, gate-3 interaction test, CMap reversal). A black-box here destroys the trust that *is* the product — UCB's explicit requirement. We use the *newest* citable formulation (OT 2025, Minikel 2024, scIB 2022, Subramanian 2017), not outdated ones.
- **Metadata harmonization → grounded + human-in-the-loop, per-client model as PROPOSER only** (deterministic mappers + text2term; per-client LLM adapter suggests, human confirms) — because LLM-only mapping is ~17% out-of-dictionary and hallucinates IDs (survey-verified).
- **Continuously refresh:** single-cell foundation models and immunopeptidome DL move fast — pin the current best at each build and re-benchmark (scIB) rather than freezing a method.

---

## Citation-verification notes (2026-07-27 audit)

All ~40 bibliographic citations above were verified against primary sources (correct authors, year, journal, volume:pages, DOI). One author error was corrected in place: **text2term** was previously attributed to "Vasudevan 2024" — the correct citation is **Gonçalves et al. 2024, *Database* 2024:baae119 (10.1093/database/baae119)**. DOIs were confirmed for every entry that carries a specific vol/page (Ochoa 10.1093/nar/gkaa1027; Buniello 10.1093/nar/gkae1128; Minikel 10.1038/s41586-024-07316-0; Nelson 10.1038/ng.3314; Oprea 10.1038/nrd.2018.14; Karczewski 10.1038/s41586-020-2308-7; Luecken 10.1038/s41592-021-01336-8; Lopez 10.1038/s41592-018-0229-2; Xu/scANVI 10.15252/msb.20209620; Korsunsky 10.1038/s41592-019-0619-0; scArches 10.1038/s41587-021-01001-7; MOFA+ 10.1186/s13059-020-02015-1; MEFISTO 10.1038/s41592-021-01343-9; scGPT 10.1038/s41592-024-02201-0; Geneformer 10.1038/s41586-023-06139-9; Reynisson 10.1093/nar/gkaa379; O'Donnell 10.1016/j.cels.2020.06.010; GEARS 10.1038/s41587-023-01905-6; Lamb 10.1126/science.1132939; Subramanian 10.1016/j.cell.2017.10.049; Peidli 10.1038/s41592-023-02144-y; STRING 10.1093/nar/gkac1000; ChEMBL 10.1093/nar/gkad1004; Sollis/GWAS Catalog 10.1093/nar/gkac1010; Reactome 10.1093/nar/gkad1025; Uhlén 10.1126/science.1260419; Nextflow 10.1038/nbt.3820; nf-core 10.1038/s41587-020-0439-x; Parkes/PROFILE 10.1016/S2468-1253(24)00034-7). All resolved correctly.

**Two quantitative claims used in companion docs could NOT be traced to a primary source and are flagged `[UNVERIFIED]` — verify or soften before external use:**
- **"~96% in-dictionary vs ~17% out-of-dictionary" LLM ontology-mapping accuracy** (HARMONIZATION_SURVEY, INTERNAL_MODEL_EXPERIMENT1/BUILD_PLAN). The *qualitative* claim (LLM ontology mappers hallucinate non-existent IDs and generalize poorly out-of-dictionary) is well-supported (e.g. PMC12162076, text2term/baae119); the *specific 96%/17% figures* were not found in any source checked. `[UNVERIFIED]`
- **"DL expanded HLA Ligand Atlas coverage 46–100%"** (WHERE_TO_TRAIN §3.2). DL-driven immunopeptidomics gains are real and documented (CAPTAn HLA-II DL, *Immunity* 2023, 10.1016/j.immuni.2023.05.009; Prosit ~7× ID boost; 20–50% more peptides via fractionation/ion-mobility), but the exact "46–100%" range was not sourced. `[UNVERIFIED]`

*Verified (2–3 vote) with primary-source confirmation: EMA CHMP qualification of PROCOVA (Sept 2022, prognostic covariate adjustment, Phase 2/3 continuous-endpoint RCTs); ~9–15% total sample-size reduction (Wang 2025 AbbVie/Unlearn Alzheimer's, ~13% reported); PRECISESADS lupus QSP built from 337 patients → anti-IFNα virtual-patient biomarker prediction (iScience 2025).*

---

*This registry is the single source for citations/links across the target-discovery, stratification, harmonization, and LLM work; update as the two in-flight workflows (`cohort_qc_triage`, `metadata_harmonizer`) land their references.*
