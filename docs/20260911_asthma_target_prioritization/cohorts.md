# Cohort replication and PheWAS

Retrieved 2026-09-11 using all four requested Life Science Research plugin scripts. Scores are analyst judgments about the retrieved evidence, not probabilities of success.

| Target | Score / 5 | Rationale |
|---|---:|---|
| TSLP | 5 | Strong same-marker direct asthma associations in FinnGen, UKB and BBJ, with PheWAS-wide significant TPMI support (p=3.5e-7; not genome-wide p<5e-8). |
| IL33 | 4 | Strong direct asthma associations for two markers in FinnGen and UKB; tested markers do not establish East Asian replication. rs1342326 is rare in BBJ and missing in TPMI. |
| IL1RL1 | 4 | Intronic rs1420101 directly associated in FinnGen, UKB and BBJ; TPMI only nominal (p=.011). Nearby rs3771166 is at IL18R1 and cannot uniquely identify IL1RL1. |

## Direct asthma comparison

Primary endpoints: FinnGen R12 J10_ASTHMA_EXMORE (59,100 cases / 259,839 controls), UKB-TOPMed phenotype 495 (26,167 / 373,887), BBJ Asthma (13,015 / 162,933), TPMI 495 (20,598 / 297,628). UKB-TOPMed denotes UKB genotypes imputed using TOPMed; it is not a separate TOPMed case cohort.

| Target / marker | FinnGen p | UKB p | BBJ p | TPMI p |
|---|---:|---:|---:|---:|
| TSLP / rs1837253 | 1.35e-37 | 1.3e-26 | 1.2e-17 | 3.5e-07 |
| IL33 / rs1342326 | 1.81e-27 | 2.3e-21 | 0.45 | not available |
| IL33 / rs3939286 | 2.01e-32 | 1.3e-27 | 0.093 | 0.51 |
| IL1RL1 / rs3771166 | 6.72e-27 | 3.3e-22 | 9e-05 | 0.53 |
| IL1RL1 / rs1420101 | 1.25e-24 | 6.3e-21 | 6.1e-09 | 0.011 |

## Interpretation and caveats

- TSLP shows the strongest cross-cohort and cross-ancestry consistency among the markers tested. TPMI supports it at a PheWAS Bonferroni threshold (0.05/719), while p=3.5e-7 does not meet the conventional GWAS threshold. IL1RL1 rs1420101 meets GWAS significance in three cohorts; its Taiwan p=.011 is only nominal. IL33 rs1342326 and rs3939286 support European asthma, but do not establish East Asian replication in these queries. This is not evidence against IL33: rs1342326 ALT frequency is only .00057 in BBJ; rs3939286 T frequency is about .03-.04 in East Asia. Power, LD and phenotype differences matter.
- The tested markers were selected from established asthma literature, not selected as the strongest SNP in each current cohort. rs3771166 lies at IL18R1 in the IL1RL1/IL18R1 region. Neither a nearby-gene label nor replication establishes the causal gene. rs1420101 is a better IL1RL1-specific marker to display, but still needs fine-mapping and functional interpretation.
- FinnGen, UKB, BBJ and TPMI are distinct biobank populations, but may be inputs to later meta-GWAS or Open Targets records. Do not count the portal result plus the meta-analysis as independent replication. Multiple asthma subtypes and multiple SNPs at one locus are correlated, not independent evidence units.
- Direct asthma includes allergic asthma as an asthma subtype. Isolated allergic rhinitis, atopic dermatitis, eczema, eosinophils and nasal polyps are stored separately as adjacent_atopic. Mixed COPD/asthma or infection endpoints and asthma medication records are separate mixed_or_asthma_related. Full extracted rows are in cohorts.json.
- Each script began with max_results=10. These slices are often alphabetical, not top associations. The complete saved raw payloads were filtered locally; absence from the first 10 rows was never treated as a null association. All populated queries report truncated=true in their compact summaries. FinnGen raw payloads retain region/fine-map lists; those regions were not interpreted as proof of variant causality.
- Network access initially failed within the sandbox, then all portals were reached with authorized public network access. rs1342326 was not available in TPMI. Missing variant is not biological absence.
- Important normalization defect: rs3939286 is multiallelic T/A/C. The plugin rsID resolver chose T/A, which was absent in all four portals. Ensembl GRCh38 and GRCh37 mappings were independently saved; explicit T/C queries recovered results. BBJ requires GRCh37 and the others GRCh38. The BBJ cross-build T/C conversion first failed and succeeded with an explicit verified GRCh37 coordinate.
- Signed betas are preserved verbatim from the portals; this report does not infer intervention direction from reference/ALT or assume the reported beta allele is a drug-inhibition proxy. Allele harmonization is required before any meta-analysis.

## Sources and provenance

All per-query URLs, canonical allele/build coordinates, total association counts, truncation flags and warnings are in cohorts.json; exact full API payloads are raw/cohorts_*_raw.json.
- [finngen: TSLP rs1837253](https://r12.finngen.fi/variant/5:111066174-T-C)
- [ukb-topmed: TSLP rs1837253](https://pheweb.org/UKB-TOPMed/variant/5:111066174-T-C)
- [biobank-japan: TSLP rs1837253](https://pheweb.jp/variant/5:110401872-T-C)
- [tpmi: TSLP rs1837253](https://pheweb.ibms.sinica.edu.tw/variant/5:111066174-T-C)
- [finngen: IL33 rs1342326](https://r12.finngen.fi/variant/9:6190076-A-C)
- [biobank-japan: IL1RL1 rs1420101](https://pheweb.jp/variant/2:102957716-C-T)
