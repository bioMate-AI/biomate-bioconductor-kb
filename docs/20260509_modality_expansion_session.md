# Modality Expansion Session — 2026-05-09

## Goal

Close the major therapeutic modality gaps identified in the coverage audit. Build workflows for ADC, PROTAC, mRNA, AAV, CAR-T, and ASO so BioMate can credibly claim full-modality coverage.

---

## What Shipped

### 6 New Workflows (in DB and indexed)

| ID | Workflow | Domain | Required params |
|---|---|---|---|
| 12925 | `protac_design` | drug_discovery | target_protein, indication |
| 12926 | `cart_construct_design` | drug_discovery | target_antigen, indication |
| 12927 | `aso_gapmer_design` | molecular_biology | target_mrna, target_tissue |
| 12928 | `adc_design` | drug_discovery | target_antigen, indication |
| 12929 | `mrna_therapeutic_design` | drug_discovery | protein_sequence, target_tissue |
| 12930 | `aav_serotype_selection` | drug_discovery | target_tissue, payload_size_kb |

All workflows are pure-Python Nextflow modules running in the `biomni-tools` container, no new dependencies.

### Routing Rules

`frontend/server/galaxy-assistant.ts` updated with:
- 5 new triggers in `DOMAIN_ROUTING_RULES.drug_discovery` (adc, protac, mrna, aav, cart)
- New `molecular_biology` domain key with aso_gapmer and sirna_design triggers
- 12 new few-shot query→workflow examples

### Capabilities Page

`frontend/client/src/pages/capabilities.tsx` updated:
- Hero subtitle now claims full-modality coverage
- 3 new job clusters: ADC Design, Targeted Protein Degradation, Cell Therapy Construct Design
- Existing clusters extended: Lead Optimization (+adc/protac), RNA Therapeutic Design (+mrna/aso), Rare Disease (+aav)
- Comparison table extended with 4 new rows; total estimated stack replacement value now $1.5M+/year

### Coverage Audit Doc

`docs/20260509_modality_coverage_audit.md` updated to reflect that ADC, PROTAC, mRNA, AAV, CAR-T, ASO are now all fully covered.

---

## Why These Six

The blog survey identified gene/cell therapy and "next-generation" modalities as the trend BioMate needs to catch. After DB audit:

- **CRISPR, antibody, siRNA, small molecule** were already covered → no new work needed
- **ADC** was the highest-priority gap: fastest-growing oncology drug class (14 approved), no platform has end-to-end computational ADC design
- **PROTAC** was a complete gap: 5 in Phase II/III, distinct design problem from small molecule
- **mRNA** had pieces (P0_mrna_validation, lnp_formulation) that needed chaining into one workflow
- **AAV** is the dominant in vivo gene therapy delivery vehicle; CRISPR design alone without delivery is incomplete
- **CAR-T** had pieces (scFv, single-cell) but no construct assembly chain
- **ASO** is mechanistically distinct from siRNA (RNase H vs RISC); approved drugs (nusinersen, inclisiran, givosiran) prove the modality

---

## Pitch Implications

The pitch can now credibly claim:

> "BioMate covers every major therapeutic modality in active clinical development — small molecule, antibody, ADC, mRNA, siRNA, ASO, CRISPR, CAR-T, PROTAC, and AAV gene therapy — in a single AI platform. No other tool does this."

This is fact-checkable against the DB. Every modality named has at least one indexed workflow with documented inputs/outputs and clinical precedent.

---

## Remaining Lower-Priority Gaps

| Gap | Notes |
|---|---|
| Cryo-EM atomic model building | ModelAngelo + Phenix; reconstruction → depositable PDB |
| Base editing / prime editing pegRNA | DSB-free CRISPR; therapeutically preferred |
| Fc engineering | ADCC enhancement (S239D/I332E), half-life extension (YTE/LS) |
| Radiopharmaceutical chelator/linker | DOTA/NOTA selection for PSMA/FAPi ligands |
| Network polypharmacology | Multi-target combination from disease network |
| HDR template design | Donor DNA for precise CRISPR knock-in |
| circRNA / saRNA | Next-gen RNA vaccine platforms |
| NK cell therapy | Alternative to CAR-T |

---

## Files Changed

```
backend/nf-core-workflows/modules/biomate-ai-tools/adc_design/main.nf            (new)
backend/nf-core-workflows/modules/biomate-ai-tools/protac_design/main.nf         (new)
backend/nf-core-workflows/modules/biomate-ai-tools/mrna_therapeutic_design/main.nf (new)
backend/nf-core-workflows/modules/biomate-ai-tools/aav_serotype_selection/main.nf (new)
backend/nf-core-workflows/modules/biomate-ai-tools/cart_construct_design/main.nf  (new)
backend/nf-core-workflows/modules/biomate-ai-tools/aso_gapmer_design/main.nf      (new)
backend/database/galaxy_ai_tools.db                  (6 INSERTs: ids 12925-12930)
frontend/server/galaxy-assistant.ts                  (routing rules + few-shot)
frontend/client/src/pages/capabilities.tsx           (job clusters + table + hero)
docs/20260509_modality_coverage_audit.md             (updated)
docs/20260509_marketing_positioning_strategy.md      (updated)
```
