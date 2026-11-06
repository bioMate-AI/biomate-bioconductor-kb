# Target-disease evidence and disease context

Retrieved 2026-09-11 using the installed Life Science Research Open Targets and EFO skills. All three score **4/5** for strong direct-asthma association convergence; this lane does not independently distinguish their mechanistic validity.

## Exact asthma association scores

Open Targets query explicitly sets `enableIndirect:false`; disease is `MONDO_0004979`. These 0–1 database scores are distinct from our 1–5 lane ratings.

|Target|Lane score|Overall OT|GWAS credible sets|Gene burden|Europe PMC|Clinical precedence|
|---|---:|---:|---:|---:|---:|---:|
|TSLP|4|0.718035|0.879161|Not present|0.971603|0.939732|
|IL33|4|0.720426|0.957466|0.784077|0.942942|0.169704|
|IL1RL1|4|0.592829|0.910590|Not present|0.937779|0.159117|

IL33 has slightly higher composite association than TSLP, driven partly by gene-burden evidence; TSLP has much higher clinical-precedence score. This illustrates why composite association rank is not a drug-development rank. No direct asthma animal-model or Expression Atlas datasource is present in the retrieved asthma rows.

## Phenotype boundaries

Asthma is MONDO:0004979 in the EFO collection. HP:0002099 is a phenotypic abnormality and should retain its separate identity. Childhood-onset asthma (MONDO:0005405), adult-onset asthma (EFO:1002011), allergic asthma (MONDO:0004784), and atopic asthma (EFO:0010638) are asthma subtypes, not generic adjacent atopy. EFO lists allergic asthma as an exact synonym of atopic asthma, so the two database rows cannot be assumed to be independent replications. Allergic rhinitis, atopic eczema, and allergic disease are adjacent context only; none contributed to these ratings. Eosinophil count, FeNO, and airway hyperresponsiveness are traits/biomarkers, not equivalent asthma diagnoses.

## Subtype and adjacent evidence (OT overall scores)

|Phenotype|Class|TSLP|IL33|IL1RL1|
|---|---|---:|---:|---:|
|Childhood onset asthma|Asthma subtype|0.463681|0.503947|0.504566|
|Allergic asthma|Asthma subtype|0.420525|0.301249|0.358308|
|Atopic asthma|Asthma subtype / overlapping label|0.321571|0.292849|0.281131|
|Allergic rhinitis|Adjacent|0.487667|0.601727|0.522675|
|Atopic eczema|Adjacent|0.102932|0.198550|0.427222|

## Rubric and confidence

- **1:** No retrieved direct asthma evidence; adjacent context only.
- **2:** One direct asthma evidence family, limited support.
- **3:** Two direct asthma families or moderate convergent support.
- **4:** Strong direct asthma literature plus human genetic association and clinical-precedence context; mechanistic direction still requires record-level adjudication.
- **5:** Level 4 plus independently adjudicated causal mechanism/direction across direct human asthma evidence within this lane.

Confidence is moderate-high for the existence of direct database association convergence. Confidence is limited for new mechanistic inference: Europe PMC association does not establish causality, direction, airway compartment, or isoform, and the constituent records were not re-adjudicated in this lane.

**Do not add this lane as an independent corroboration multiplier.** Its genetic, clinical, and literature components overlap the other lanes; recommend zero independent weight in the numerical synthesis and use it as a consistency and phenotype-mapping check. Ontology mapping adds no experimental evidence.

- Scores are qualitative evidence-strength judgments, not probabilities, effect sizes, safety scores, or clinical recommendations.
- enableIndirect:false used; target disease-score rows represent database annotations, not independently reviewed constituent study phenotypes.
- First 200 rows per target retrieved; asthma and specified major subtypes/adjacent phenotypes found, low-scoring associations may be missing.
- Absent datasource entries are missing curated support, not evidence of no biological relationship.
- Europe PMC scores reflect literature association and do not establish mechanism or direction.
- Current datasource IDs are clinical_precedence and gwas_credible_sets, differing from older helper labels.

Sources: [Open Targets asthma](https://platform.opentargets.org/disease/MONDO_0004979), [EFO asthma term](https://www.ebi.ac.uk/ols4/ontologies/efo/classes/http%253A%252F%252Fpurl.obolibrary.org%252Fobo%252FMONDO_0004979). Raw payloads: `raw/disease_ot_direct.json`, `raw/disease_ot.json`, `raw/disease_efo.json`; exact datasource/datatype and subtype scores are preserved in `disease_context.json`.
