# Plan A — IEDB web population coverage audit (manual)

**Claim to verify:** Chile tier A+B surface epitope set → **48.81%** population coverage (17-allele strict dual-tool panel).

**Local cross-check:** **PASS** — see `PLAN_A_IEDB_CROSSCHECK.md`.

---

## Files

| File | Purpose |
|------|---------|
| `PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` | Upload to IEDB (peptide + allele columns) |
| `PLAN_A_CHILE_POPULATION_COVERAGE.md` | BioMate recomputation summary |
| `PLAN_A_CHILE_POPULATION_COVERAGE.json` | Machine-readable coverage by subset |

---

## Steps

1. Open [IEDB Population Coverage](https://tools.iedb.org/population/).
2. Choose **Class I** (HLA-A/B) population coverage tool.
3. Upload **`PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv`**.
4. Set population to **Chile** (or the closest AFND-matched population available in the UI).
5. Run calculation and record:
   - Reported **population coverage %**
   - Allele frequency source shown by IEDB
   - Any peptides dropped due to allele name mismatch
6. Paste result into `PLAN_A_IEDB_CROSSCHECK.md` table (IEDB web tool row).

---

## Pass criteria

| Check | Target |
|-------|--------|
| Coverage vs BioMate | **48.81% ± 1.0 pp** |
| Peptides accepted | **28/28** unique peptides (30 allele rows) |
| Allele naming | No silent drops (compare rejected rows in UI) |

---

## If mismatch

- Compare allele strings in upload TSV vs IEDB allele picker (e.g. `HLA-A*02:01` formatting).
- Confirm population = Chile, not World/Argentina default.
- Re-run local script: `python3 research/anti-virus/scripts/crosscheck_plan_a_chile_iedb.py --publication-run …`

---

## Regenerate upload TSV

```bash
PUB=research/anti-virus/runs/publication_20260528T223525Z
python3 research/anti-virus/scripts/crosscheck_plan_a_chile_iedb.py --publication-run "$PUB"
```
