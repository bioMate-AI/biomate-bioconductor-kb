# Clinical and regulatory evidence: asthma

Retrieved 2026-09-11 using Life Science Research clinicaltrials-skill, opentargets-skill, chembl-skill and pharmgkb-skill, with primary FDA, publication and sponsor sources for outcomes. This is an asthma therapeutic-validation score, not a novelty or commercial-opportunity score.

| Target | Score /5 | Direct asthma assessment | Confidence |
|---|---:|---|---|
| TSLP | 5 | Approved asthma mechanism; positive pivotal exacerbation trial | High |
| IL33 | 3 | Positive itepekimab phase 2, but tozorakimab FRONTIER-3 primary endpoint missed; ongoing phase 2b | Moderate |
| IL1RL1 (ST2) | 3 | Positive astegolimab phase 2b exacerbation result, without verified pivotal asthma confirmation | Moderate |

Rubric: 1 absent; 2 preclinical or indirect; 3 direct early clinical or mixed phase 2; 4 positive late-stage/replicated clinical evidence; 5 regulatory asthma validation. The score is an ordinal judgment, not a probability. Equal scores do not imply equivalent drugs. No head-to-head study establishes comparative efficacy among these targets.

## Direct asthma evidence

**TSLP.** FDA approved tezepelumab-ekko (Tezspire) on December 17, 2021 for add-on maintenance treatment in patients aged 12 and older with severe asthma. The FDA bulletin identifies TSLP inhibition and absence of restriction to a particular severe-asthma type. In NAVIGATOR (NCT03347279), a 1,061-patient randomized phase 3 trial, annualized exacerbation rates were 0.93 versus 2.10 (rate ratio 0.44, 95% CI 0.37–0.53; P<0.001). This directly validates inhibition of TSLP for asthma exacerbations. [FDA approval bulletin](https://content.govdelivery.com/accounts/USFDA/bulletins/301ce9f), [FDA approval date](https://purplebooksearch.fda.gov/index.cfm?blaNo=761224&event=productdetails), [NAVIGATOR publication](https://pubmed.ncbi.nlm.nih.gov/33979488/), [registry](https://clinicaltrials.gov/study/NCT03347279).

Endpoint caveat: SOURCE (NCT03406078), a 150-patient phase 3 corticosteroid-sparing study, did not meet its primary endpoint in the overall population (OR 1.28, 95% CI 0.69–2.35; P=0.43). Regulatory validation for exacerbations must not become a claim that every endpoint or patient subgroup responds. [SOURCE primary publication](https://pubmed.ncbi.nlm.nih.gov/35364018/).

**IL33.** Itepekimab phase 2 (NCT03387852; 296 adults) showed fewer loss-of-asthma-control events at 12 weeks than placebo: 22% versus 41%, OR 0.42 (95% CI 0.20–0.88; P=0.02). Its short treatment-withdrawal design and control-loss composite differ from a long-term exacerbation trial. Combination with dupilumab did not establish additive benefit. [Primary publication](https://pubmed.ncbi.nlm.nih.gov/34706171/), [registry](https://clinicaltrials.gov/study/NCT03387852).

Tozorakimab FRONTIER-3 (NCT04570657; 235 participants), published in 2026, did **not** meet its primary clinic pre-bronchodilator FEV1 endpoint at week 16. Placebo-adjusted changes were 4 mL (600 mg; P=0.473) and 36 mL (300 mg; P=0.267). A prespecified subgroup with at least two previous exacerbations had a signal at 600 mg, but this does not rescue the failed primary analysis. The Umbriel phase 2b trial (NCT06932263) is recruiting in the registry, updated July 20, 2026, with estimated primary completion June 7, 2027; these future dates are estimates, not outcomes. [FRONTIER-3 publication](https://pubmed.ncbi.nlm.nih.gov/41736737/), [FRONTIER-3 registry](https://clinicaltrials.gov/study/NCT04570657), [Umbriel registry](https://clinicaltrials.gov/study/NCT06932263).

**IL1RL1/ST2.** Astegolimab ZENYATTA (NCT02918019; 502 adults, phase 2b) reduced annualized asthma exacerbations at week 54 by 43% at 490 mg (P=.005), 22% at 210 mg (P=.18), and 37% at 70 mg (P=.01), versus placebo. A low-eosinophil subgroup also showed a signal. This is meaningful direct intervention evidence, but the dose response was non-monotonic and no pivotal asthma confirmation or asthma approval was verified in this bounded search. The registry identifies the asthma trial as completed. [Primary publication](https://pubmed.ncbi.nlm.nih.gov/33872652/), [registry](https://clinicaltrials.gov/study/NCT02918019).

## Adjacent diseases: kept out of asthma score

IL33 has stronger recent **COPD** development evidence than the asthma score alone conveys. AstraZeneca's September 8, 2026 release reports positive OBERON and TITANIA phase 3 COPD results and FDA Priority Review acceptance of the tozorakimab COPD BLA. The same release says asthma development remains phase 2. BLA acceptance is not approval; COPD efficacy is not asthma efficacy. [Current sponsor disclosure](https://www.astrazeneca.com/media-centre/press-releases/2026/tozorakimab-demonstrated-statistically-significant-highly-clinically-meaningful-reduction-copd-exacerbations-oberon-titania-phase-iii-trials.html).

Itepekimab's COPD AERIFY-1 met its endpoint whereas AERIFY-2 did not in May 2025. CRSwNP/CRSsNP and bronchiectasis programs are adjacent context. [Sponsor disclosure](https://www.sanofi.com/en/media-room/press-releases/2025/2025-05-30-05-00-00-3090818). Astegolimab's ALIENTO and ARNASA pivotal programs concern COPD, not asthma. [Roche July 2025 disclosure](https://www.roche.com/media/releases/med-cor-2025-07-21). Atopic dermatitis, rhinitis, nasal polyps, eosinophilic esophagitis and COPD records are not counted as direct asthma validation here.

## Structured-source checks and limitations

ChEMBL returned tezepelumab CHEMBL3707229, first approval 2021, maximum phase 4; itepekimab CHEMBL4594594, astegolimab CHEMBL4594385 and tozorakimab CHEMBL4650490 maximum phase 3 with null first approval. These are global molecule phases, **not asthma-specific phase 3 success**. Open Targets returned TSLP/tezepelumab APPROVAL, IL33/itepekimab PHASE_3 plus etokimab and torudokimab PHASE_2, and IL1RL1/astegolimab PHASE_3. Open Targets' target-level candidate result omitted tozorakimab although ChEMBL, the registry and current primary sources identify it. This illustrates aggregation coverage and release-lag risk.

The plugin's historical `knownDrugs` field is absent from the current Target schema; the successful narrow query uses `drugAndClinicalCandidates`. API responses and raw full trial records are saved under `raw/clinical_*`. Drug-name registry searches were bounded to 10 records/one page. Tezepelumab results were truncated; these results are not an exhaustive trial inventory. Tozorakimab's name search did not retrieve FRONTIER-3, so its exact NCT record was fetched separately. Search membership alone does not prove the target, phenotype or trial outcome.

PharmGKB retrieval failed DNS resolution at the skill-configured `api.pharmgkb.org` for all three genes. This is an **access gap**, not evidence of absent pharmacogenetic annotations or an unfavorable biological result. No PharmGKB evidence was scored. Distinct FDA records, publications, trial records, ChEMBL entries and Open Targets entries often describe the same intervention: they corroborate provenance and must not be counted as independent biological replications.
