# ACMG Variant Interpretation (evidence aggregation + computable criteria)

Clinical variant interpretation for BioMate that is **honest by construction**:
it aggregates real per-variant evidence and applies **only** the ACMG/AMP-2015
criteria that are *mechanically computable* from that evidence. It never emits a
black-box "this variant is Pathogenic" verdict, and it **honest-fails** when the
required evidence is unavailable.

## Honesty boundary (enforced in code)

- **No black-box clinical verdict.** The `provisional.tier` is a *transparent
  additive sum* of the auto-applied criteria (Tavtigian et al. 2020 points
  scheme) and is explicitly labelled `NOT a final clinical classification`.
- **Missing evidence → unknown → VUS.** A criterion whose evidence is absent is
  reported as `unknown` (not "not met"), and the provisional call defaults
  toward VUS.
- **ClinVar is reference-only.** ClinVar's clinical significance + review-star
  level are surfaced for comparison but are **never** copied into the computed
  tier. (A known-pathogenic BRCA1 variant with only PM2+PP3 computable stays VUS.)
- **Honest-fail.** If no variant carries a usable evidence axis, `build_dossier.py`
  exits non-zero and writes no dossier.
- **No RNG.** Deterministic: identical evidence → identical output. Unit-tested.

## Criteria: auto-applied vs deferred

| Criterion | Auto-applied? | Evidence used | Threshold |
|---|---|---|---|
| **BA1** (stand-alone benign) | ✅ | gnomAD AF (max across pops) | AF > 5% |
| **BS1** (strong benign) | ✅ | gnomAD AF | AF > disease-max (default 1%, or `--max-credible-af`), ≤ 5% |
| **PM2_Supporting** | ✅ | gnomAD AF / confirmed absence | AF < 0.01% or absent-when-queried |
| **PP3** (path. support) | ✅ | REVEL ≥0.75 / AlphaMissense ≥0.564 / CADD ≥25 (concordant) | predictors agree deleterious |
| **BP4** (benign support) | ✅ | REVEL ≤0.25 / AlphaMissense ≤0.34 / CADD ≤10 (concordant) | predictors agree tolerated |
| **PVS1** (null variant) | ⚠️ **FLAG only** | LoF consequence + pLI≥0.9 / LOEUF≤0.35 | preconditions computed; final strength needs expert NMD/last-exon/transcript review |
| PS1, PS2, PS3, PS4, PM1, PM3, PM5, PM6, PP1, PP2, PP4, PP5, BS3, BS4, BP1, BP2, BP3, BP5, BP6, BP7 | ❌ **requires expert review** | functional / segregation / phasing / hotspot / phenotype | listed in every dossier, never auto-applied |

Conflicting in-silico predictors → **neither** PP3 nor BP4 (conservative).
BA1 fired → provisional is Benign and supersedes PM2 (ClinGen rule).

## Dossier schema (`biomate.acmg_dossier.v1`)

```
{
  "schema": "biomate.acmg_dossier.v1",
  "engine": "acmg_variant_interpretation",
  "honesty_boundary": "<the boundary statement>",
  "n_variants": <int>, "n_evaluated": <int>, "n_insufficient_evidence": <int>,
  "variants": [
    {
      "variant": "BRCA1 p.Arg1699Gln",
      "status": "evaluated" | "insufficient_evidence",
      "applied_criteria":        [ {code, applied:true, strength, direction, evidence:{...}, rationale} ],
      "flagged_criteria":        [ {code:"PVS1", applied:"flag", ...} ],
      "not_applicable_criteria": [ {code, applied:false, ...} ],
      "unknown_criteria":        [ {code, applied:null,  ...} ],
      "requires_expert_review":  [ {code, reason} ],
      "clinvar_reference":       {clinical_significance, review_status, review_stars, note} | null,
      "provisional": {
        "tier": "Uncertain Significance (VUS)",
        "points": <int>,
        "n_automatable_criteria_applied": <int>,
        "label": "PROVISIONAL -- ... NOT a final clinical classification ...",
        "points_scheme": "Tavtigian et al. 2020 (PMID 32720330) additive summary",
        "default_toward_vus_on_missing_evidence": true
      },
      "raw_evidence": { ...the normalized input evidence... }
    }
  ]
}
```

Every `evidence` object cites the exact value + source field that triggered the
criterion (e.g. `{"gnomad_af": 1e-05, "source_field": "gnomad_af_grpmax",
"threshold": 0.0001}`), so each call is fully auditable.

## Running

**From a VCF (runs Ensembl VEP for evidence):**
```
nextflow run main.nf --input variants.vcf.gz --outdir results/
```

**From an already-annotated VEP TSV / CSV / JSON list:**
```
nextflow run main.nf --input annotated.tsv --pre_annotated true --outdir results/
```

Optional gene/disease-specific max-credible-AF for BS1 (Whiffin et al. 2017):
`--max_credible_af 0.0005`.

## Accepted evidence columns (VEP / alias tolerant)

- **AF**: `gnomADg_AF`, `gnomADe_AF`, `gnomAD_grpmax_AF`, `gnomAD_popmax_AF`, `AF`, `MAX_AF`
- **In-silico**: `REVEL`, `am_pathogenicity`/`AlphaMissense`, `am_class`, `CADD_PHRED`
- **Constraint**: `pLI`, `LOEUF`/`oe_lof_upper`
- **Consequence**: `Consequence`
- **ClinVar**: `CLNSIG`/`CLIN_SIG`, `CLNREVSTAT`
- **Identity**: `SYMBOL`, `HGVSp`, `HGVSc`, `CHROM`/`POS`/`REF`/`ALT`

## Tests

`python test_acmg_criteria.py` — 40 deterministic unit tests (BA1/BS1/PM2/PP3/BP4/
PVS1 thresholds, ClinVar-reference-not-used, no-RNG guard, evidence gate).
Passes on Python 3.9 and 3.13.

## References

- Richards et al. *Genet Med* 2015 — ACMG/AMP-2015 (PMID 25741868)
- Tavtigian et al. *Genet Med* 2020 — Bayesian points framework (PMID 32720330)
- Abou Tayoun et al. *Hum Mutat* 2018 — ClinGen PVS1 (PMID 30192042)
- Whiffin et al. *Genet Med* 2017 — max credible AF (PMID 28518168)
- Ioannidis et al. *AJHG* 2016 — REVEL; Cheng et al. *Science* 2023 — AlphaMissense
