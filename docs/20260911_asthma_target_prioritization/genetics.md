# Human genetics and GWAS lane

Retrieved 2026-09-11 with the Life Science Research plugin's **gwas-catalog-skill, opentargets-skill, and gnomad-graphql-skill** scripts. Raw public API responses and exact requests are in `raw/genetics_*`. Scores are analyst assessments on the agreed 1–5 scale, not scores returned by a database.

| Target | Score | Direct asthma evidence and interpretation |
|---|---:|---|
| TSLP | 4 | Strong direct asthma GWAS plus functional evidence consistent with reduced TSLP secretion being protective; the common association does not alone establish causal molecular perturbation. |
| IL33 | 5 | Strong common-variant association plus a rare experimentally characterized splice-disrupting variant protecting against asthma provides the clearest genetic direction-of-effect support. |
| IL1RL1 | 4 | Strong direct asthma locus association and lung/airway functional evidence; attribution at the IL1RL1/IL18R1 locus and opposite functions of membrane versus soluble ST2 complicate simple target-inhibition inference. |

## Figure-ready lead asthma-linked variants

All three selected associations are from **the same study: GCST90480249, Verma et al., 2024, PMID 39024449, Million Veteran Program**. These are reported locus associations from a specified study, not a claim of the globally strongest or causal variant. The study contains 55,213 cases and 561,487 controls: 36,823/398,278 European, 12,093/105,134 African American or Afro-Caribbean, 5,688/52,071 Hispanic or Latin American, and 609/6,004 East Asian cases/controls. Catalog study metadata lists no separate replication stage. [Study metadata](https://www.ebi.ac.uk/gwas/rest/api/v2/studies/GCST90480249).

| Target | Variant and reported allele | Asthma P | Effect exactly as Catalog reports | Catalog mapped genes |
|---|---|---:|---|---|
| TSLP | rs1837253-T | 1 × 10⁻⁴⁰ | 0.1191 unit decrease; range [0.1–0.13] | BCLAF1P1, TSLP |
| IL33 | rs1888909-T | 5 × 10⁻³¹ | 0.08906 unit increase; range [0.073–0.105] | GTF3AP1, IL33 |
| IL1RL1 | rs13001714-A | 1 × 10⁻⁴³ | 0.09795 unit decrease; range [0.085–0.11] | IL18R1, IL1RL1 |

Exact association payloads: [TSLP](https://www.ebi.ac.uk/gwas/rest/api/v2/associations/226258978), [IL33](https://www.ebi.ac.uk/gwas/rest/api/v2/associations/226259178), [IL1RL1](https://www.ebi.ac.uk/gwas/rest/api/v2/associations/226258966). These alleles are **reported effect alleles**, not uniformly risk alleles. The beta scale was not independently resolved, so no odds-ratio transformation is performed. The reported ranges are preserved verbatim; do not display them as signed confidence intervals without applying direction. GWAS P strength does not measure therapeutic efficacy.

## Functional direction and historical replication

**IL33:** rs146597587-C disrupts a splice acceptor and experimentally impairs IL-33 function. In European samples, carriers had lower asthma risk (OR 0.47, 95% CI 0.32–0.70, P=1.8×10⁻⁴; 6,465 cases, 302,977 controls), with lower total IL33 transcript. This strengthens causal and direction evidence beyond common-variant mapping, while its asthma P in this experiment is not genome-wide significant. Eosinophil reduction is a separate intermediate phenotype. [Original study, PMID 28273074](https://pubmed.ncbi.nlm.nih.gov/28273074/). A separate rare-coding study reported asthma OR 0.56, CI 0.45–0.70, P=2.6×10⁻⁷, and separately allergic rhinitis OR 0.55, P=4.2×10⁻⁴; overlapping populations must be checked before treating these as independent replication. [PMID 28787443](https://pubmed.ncbi.nlm.nih.gov/28787443/).

**TSLP:** primary nasal epithelial cells carrying rs1837253-T secreted less TSLP after dsRNA stimulation, supporting the protective direction in the figure. This is a genotype–functional association, not a randomized perturbation or complete fine-mapping proof. [Original functional study, PMID 25515628](https://pubmed.ncbi.nlm.nih.gov/25515628/). Earlier asthma associations included sex-specific effects, cautioning against unqualified generalization across populations. [Original study, PMID 20560908](https://pubmed.ncbi.nlm.nih.gov/20560908/).

**IL1RL1:** functional work on rs1420101 and rs11685480 links asthma-associated variants to soluble ST2 protein and tissue-specific lung/airway expression. Soluble ST2 neutralizes IL-33, while membrane ST2 transduces its signal, so reducing total IL1RL1 expression cannot be equated automatically with therapeutic blockade of membrane signaling. [Original study, PMID 27699235](https://pubmed.ncbi.nlm.nih.gov/27699235/). GABRIEL previously established direct asthma associations at IL33 (rs1342326) and the IL1RL1/IL18R1 locus (rs3771166); the latter's high linkage disequilibrium with IL1RL1 variants illustrates gene-assignment ambiguity. [GABRIEL, PMID 20860503](https://pubmed.ncbi.nlm.nih.gov/20860503/).

## Adjacent phenotype evidence kept separate

TSLP rs1837253 also has allergic-rhinitis evidence in children already selected for asthma; that contrast is rhinitis comorbidity, not independent asthma susceptibility. [PMID 21244681](https://pubmed.ncbi.nlm.nih.gov/21244681/). IL33 eosinophil and allergic-rhinitis associations support shared allergic biology but do not substitute for asthma outcomes. IL1RL1 sST2, eosinophils, and type-2 inflammation are functional/endotype context, not equivalent to case-control asthma GWAS.

The Catalog query's first 10 associations per target contains family-history and medication-use phenotypes as well as asthma. The figure selects only rows explicitly reported as **Asthma**. No claim is made that 30 rows are 30 independent pieces of evidence.

## Open Targets and gnomAD

The current asthma identifier is MONDO_0004979. Narrow Open Targets `gwas_credible_sets` evidence queries returned counts of 123 (TSLP), 126 (IL33), and 92 (IL1RL1), with three rows retrieved per target. These are database evidence-record counts, not independent cohorts, causal variants, or separate validation experiments. They must be deduplicated against Catalog and constituent studies before model training or evidence aggregation. [Open Targets](https://platform.opentargets.org/disease/MONDO_0004979/associations).

| Target | gnomAD LoF observed/expected | Lower–upper interval | pLI |
|---|---:|---|---:|
| TSLP | 0.967 | 0.620–1.566 | 0.0000705 |
| IL33 | 1.356 | 1.043–1.783 | 2.31×10⁻¹⁶ |
| IL1RL1 | 0.629 | 0.475–0.845 | 4.86×10⁻⁷ |

These came from the gnomAD GraphQL `gnomad_constraint` field on GRCh38; the field's dataset release was not specified by this response, so do not relabel them as current v4 LOEUF. Constraint is population tolerance context, **not asthma evidence, proof of efficacy, or safety clearance**. Absence of strong pLI constraint does not establish that pharmacological inhibition is safe. [TSLP gnomAD](https://gnomad.broadinstitute.org/gene/ENSG00000145777), [IL33 gnomAD](https://gnomad.broadinstitute.org/gene/ENSG00000137033), [IL1RL1 gnomAD](https://gnomad.broadinstitute.org/gene/ENSG00000115602).

## Confidence and limits

High confidence that all three have direct human asthma genetics; highest directional confidence for IL33. Moderate confidence in the exact ordinal spacing because this is a bounded evidence review, not a complete fine-mapping/colocalization audit. A shared multi-ancestry study improves comparability of the figure but does not establish ancestry-specific replication or equal effect sizes. Functional evidence and variant-to-gene mapping require their own confidence fields. Do not double-count Open Targets, Catalog and papers reporting the same underlying data.
