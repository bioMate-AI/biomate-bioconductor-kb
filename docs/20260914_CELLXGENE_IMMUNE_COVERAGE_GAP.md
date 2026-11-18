# CZ CELLxGENE — Immune-Disease Coverage Gap Analysis

Date: 2026-09-14  |  Metadata-only (no h5ad downloaded)

## Method

- **Held set:** all `.h5ad` basenames under `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/` (recursive, 1,830 files across 14 sub-prefixes incl. base_corpus, harmonized, immune_expanded, immune_llm_models, etc.) + `autoimmune_sc_corpus/` (6). After dedupe: **1,585 unique basenames**, of which **805 are valid CELLxGENE dataset UUIDs** (remainder are perturbation/GEO-named files, not CELLxGENE-diffable).
- **Available set:** CZ CELLxGENE Discover Curation API `/curation/v1/datasets` — single call returned **all 2,226 public datasets** with metadata (no pagination needed; the endpoint is not paginated). Disease read from the `disease[]` ontology array; multi-disease titles use `||` separators, counted if ANY component is immune-relevant.
- **Immune filter (curated):** SLE, RA, JIA, MS, Crohn, UC, IBD, T1D, prediabetes, psoriasis/PsA, Sjögren, systemic sclerosis, vasculitis, asthma, atopic dermatitis/eczema, COVID-19 (+long/post), influenza, CMV infection, celiac, sarcoidosis, immune-mediated necrotizing myopathy, generic 'immune system disorder'. **Excluded** as non-immune-mediated: type-2 diabetes / diabetic kidney disease, atherosclerosis, osteoarthritis, ALS/dementia, all cancers.

## Headline

| metric | value |
|---|---|
| Total public CELLxGENE datasets | 2,226 |
| Immune-disease datasets on CELLxGENE (unique) | **148** |
| — already held | **138** |
| — **MISSING** | **10** |

Coverage of immune-disease CELLxGENE datasets is **~93% (138/148)**. Only 10 datasets are missing, concentrated in 4 collections.

## Per-disease: available vs held vs missing

(A dataset can map to >1 disease, so column sums exceed the 148 unique total.)

| Disease | Avail | Held | Missing | Cells avail | Cells missing |
|---|---:|---:|---:|---:|---:|
| cytomegalovirus infection | 25 | 20 | 5 | 21,579,373 | 4,059,728 |
| immune system disorder | 4 | 1 | 3 | 19,968 | 14,976 |
| rheumatoid arthritis | 3 | 1 | 2 | 2,288,363 | 2,179,646 |
| atopic eczema | 1 | 0 | 1 | 280,518 | 280,518 |
| immune-mediated necrotizing myopathy | 1 | 0 | 1 | 96,822 | 96,822 |
| COVID-19 | 66 | 66 | 0 | 9,105,087 | 0 |
| Crohn disease | 21 | 21 | 0 | 7,097,089 | 0 |
| Sjogren syndrome | 12 | 12 | 0 | 149,139 | 0 |
| celiac disease | 2 | 2 | 0 | 1,818,100 | 0 |
| inflammatory bowel disease | 9 | 9 | 0 | 3,804,619 | 0 |
| influenza | 5 | 5 | 0 | 1,084,183 | 0 |
| juvenile idiopathic arthritis | 3 | 3 | 0 | 306,013 | 0 |
| long COVID-19 | 1 | 1 | 0 | 32,588 | 0 |
| multiple sclerosis | 2 | 2 | 0 | 4,158,252 | 0 |
| post-COVID-19 disorder | 1 | 1 | 0 | 422,220 | 0 |
| prediabetes syndrome | 4 | 4 | 0 | 430,489 | 0 |
| psoriasis | 1 | 1 | 0 | 24,126 | 0 |
| pulmonary sarcoidosis | 2 | 2 | 0 | 2,754,352 | 0 |
| systemic lupus erythematosus | 1 | 1 | 0 | 1,263,676 | 0 |
| type 1 diabetes mellitus | 4 | 4 | 0 | 3,189,920 | 0 |
| ulcerative colitis | 11 | 11 | 0 | 3,875,223 | 0 |

## Missing datasets (all 10, grouped by collection)

### Progression to rheumatoid arthritis in at-risk individuals is defined by systemic inflammation and by T and B cell dysregulation
_5 dataset(s), 4,059,728 cells — collection `3a518635-c062-4c66-a9bd-c4581a5e3c63`_

| dataset_id | title | disease(s) | cells |
|---|---|---|---:|
| `789ad837-9bf5-436c-9b60-9f1153546e4c` | altra all samples | cytomegalovirus infection, rheumatoid arthritis | 2,029,864 |
| `6d06c94d-25ff-4d7b-9a09-659289dd4621` | altra ARI-CONV subjects | cytomegalovirus infection | 977,608 |
| `40cca468-a415-498e-b25c-77875760eaa0` | altra ARI-NONC subjects | cytomegalovirus infection | 508,300 |
| `71dfd52f-106b-40f4-a66d-c7dab1142e95` | altra HC1 subjects | cytomegalovirus infection | 394,174 |
| `20fae564-230a-4998-8380-13d57784dd55` | altra ERA subjects | cytomegalovirus infection, rheumatoid arthritis | 149,782 |

### Multi-modal skin atlas identifies a multicellular immune-stromal community associated with altered cornification and specific T cell expansion in atopic dermatitis
_1 dataset(s), 280,518 cells — collection `5e143645-177c-45b6-952d-48770e29a54b`_

| dataset_id | title | disease(s) | cells |
|---|---|---|---:|
| `b0ef440b-e303-4ad2-ada8-ce13336280ba` | Multi-modal skin atlas identifies a multicellular immune-stromal community associated with altered cornification and specific T cell expansion in atopic dermatitis (Atopic Dermatitis Atlas) | atopic eczema | 280,518 |

### Priming of tissue-resident stromal cells sustains chronic inflammation in myositis
_1 dataset(s), 96,822 cells — collection `bec32fb0-9b52-423a-83c4-5e15053b84ad`_

| dataset_id | title | disease(s) | cells |
|---|---|---|---:|
| `c7c1fff0-4c9f-4353-afbf-d6a6768d22c3` | FAPs in IIMs | antisynthetase syndrome, immune-mediated necrotizing myopathy, inclusion body myositis | 96,822 |

### Single cell and spatial transcriptomics in Sjögren’s Disease-affected Human Salivary Glands
_3 dataset(s), 14,976 cells — collection `21bbfaec-6958-46bc-b1cd-1535752f6304`_

| dataset_id | title | disease(s) | cells |
|---|---|---|---:|
| `e28f0c23-7922-4a18-85c5-b2201c06b681` | spRNA-seq for GZMK+CD8+ T cells Target A Specific Acinar Cell Type in Sjögren’s Disease - Block #25 | immune system disorder | 4,992 |
| `1218b9f0-4f95-47a0-b69a-847c92087ded` | spRNA-seq for GZMK+CD8+ T cells Target A Specific Acinar Cell Type in Sjögren’s Disease - Block #26 | immune system disorder | 4,992 |
| `344f27ab-428c-4a0e-a7e1-d4441f2f9b80` | spRNA-seq for GZMK+CD8+ T cells Target A Specific Acinar Cell Type in Sjögren’s Disease - Block #30 | immune system disorder | 4,992 |

## Notes / caveats

- **RA cluster is one study.** 6 of 10 missing (all 5 'CMV infection' + 1 'early RA') belong to the single collection *'Progression to rheumatoid arthritis in at-risk individuals'*. Samples there are disease-labeled by serostatus (CMV) and RA stage — so the 4M 'CMV-infection' cells are really an RA-progression cohort, not a CMV atlas. Acquiring this one collection closes the RA and CMV gaps together.
- **CMV 'coverage'** looks large (25 avail / 21.6M cells) but is dominated by this RA study; treat CMV as a byproduct label, not a standalone immune target.
- **Held-UUID mapping is exact.** 0 of the held basenames matched a CELLxGENE `dataset_version_id` instead of `dataset_id`, so no missing dataset is a false positive from version-id storage.
- **Normal/atlas datasets excluded** from the immune count by design (1,877 datasets carry a 'normal' label; only disease-labeled ones counted). Tabula-Sapiens-style healthy atlases were not tallied.
- **Ambiguity:** 'immune system disorder' (generic) contributes 3 missing spatial datasets (~15k cells) from a salivary-gland Sjögren study — borderline, low value. 'prediabetes syndrome' included as T1D-adjacent; drop if you want strict autoimmune scope.
- Systemic sclerosis / vasculitis / asthma / PsA: **0 datasets on CELLxGENE** under those exact ontology labels (nothing to miss).
