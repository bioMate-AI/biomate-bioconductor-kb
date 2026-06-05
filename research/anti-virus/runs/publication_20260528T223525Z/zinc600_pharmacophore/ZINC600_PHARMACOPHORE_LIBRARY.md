# ZINC600 pharmacophore-filtered library

_Generated: 2026-06-05T03:27:37.286477Z_

## Design

- **Parent deck:** AAAC tranche first 600 (`assets/zinc600_library.tsv`)
- **Reference actives:** `reference_actives_antiviral.smi` (ribavirin, favipiravir, umifenovir, oseltamivir)
- **Filter:** RDKit SMARTS consensus model, **min_features = 3**
- **Pass rate:** **91 / 600** (15.17%)

## vs raw AAAC slice

| | Raw ZINC600 | Pharmacophore-filtered |
|---|---:|---:|
| Target-informed pre-filter | No | **Yes** |
| Compounds | 600 | 91 |
| Reference actives in deck | 0/4 | screened separately |

## Outputs

- `zinc600_pharmacophore_filtered.tsv` — substance ID + SMILES + match stats
- `zinc600_pharmacophore_filtered.smi` — Vina input deck
- `match_report.tsv` — full 600-row screen
- `pharmacophore_model.json` — feature model from references

## Next step

Dock `zinc600_pharmacophore_filtered.smi` with the same 9P3I box as ZINC600 (compare hit rates and chemotype overlap vs unfiltered AAAC).
