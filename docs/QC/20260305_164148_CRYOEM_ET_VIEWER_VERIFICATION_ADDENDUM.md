# Independent Verification Addendum — Cryo-EM ET Viewer

**Timestamp:** 2026-03-05 16:41:48 CST  
**Verifier:** Cursor coding agent (independent run)  
**Target document:** `docs/QC/20260305_CRYOEM_ET_VIEWER_IMPLEMENTATION.md`

---

## Scope

Re-ran the documented commands directly in this environment to validate reproducibility and identify any mismatch between expected outputs and current behavior.

---

## Verified Passing Results

1. **Gap 2 — QC profiles snippet:** Pass (output matches expected profile list and pass/fail behavior).
2. **Gap 3 — Orientation anisotropy snippet:** Pass (`1.8x` pass, `7.0x` advisory-only, `12.0x` blocking).
3. **Section 7 — Full QC suite:** Pass (`213 passed`).
4. **Section 7 — Cryo-EM subset:** Pass (`31 passed`, `0 failed`).
5. **Section 7 — FSC key fix snippet:** Pass (`fsc_0143_resolution` alias correctly mapped to `fsc_resolution_angstrom`).
6. **Gap 4 — ET pipeline test profile run:** Pass (all 5 processes submitted/completed).
7. **Gap 4 — ET pipeline stub profile run:** Pass (all 5 processes submitted/completed).
8. **Gap 4 — individual `import_tiltseries` module:** Pass (`num_tiltseries=3` in report).
9. **Gap 4 — QC dispatch snippet (`TILT_ALIGNMENT`):** Pass (advisory-only failure, no blocking failure).

---

## Mismatches Found (Needs Doc Update)

### M1. ET summary output folder name mismatch

- **Document expects:** `results/test_et/05_et_pipeline_summary/et_pipeline_summary.json`
- **Actual path generated:** `results/test_et/05_pipeline_summary/et_pipeline_summary.json`
- **Impact:** Follow-up command in the document that reads the expected path fails with `FileNotFoundError`.

### M2. `num_tiltseries` location mismatch in summary JSON

- **Document expects:** top-level `num_tiltseries`
- **Actual JSON:** `acquisition.num_tiltseries`
- **Observed value:** `3`
- **Impact:** Spot-check command should query nested field (`acquisition.num_tiltseries`) rather than top-level key.

### M3. Frontend TypeScript compile expectation mismatch

- **Document expectation (Gap 5/6):** `npx tsc --noEmit` returns no errors.
- **Actual result:** compile fails in current repo state with:
  - `client/src/components/viewers/structure-viewer.tsx`: `window.$3Dmol` type errors (4 occurrences)
  - `server/vite.ts`: `watch` property not allowed on `InlineConfig`
- **Impact:** “Expected: no errors” is currently not reproducible.

---

## Suggested Text Fixes for Source Doc

1. Replace all `05_et_pipeline_summary` references with `05_pipeline_summary`.
2. Update summary spot-check expectation:
   - from `num_tiltseries: 3`
   - to `acquisition.num_tiltseries: 3`
3. In sections asserting clean TypeScript build, either:
   - narrow claims to the modified viewer files only, or
   - explicitly note known unrelated/ambient TypeScript issues currently present.

---

## Execution Notes

- Python snippets were executed exactly as instructed from `backend/` using `.venv/bin/python` and `sys.path.insert(0, 'lib')`.
- Nextflow is available in this environment (`25.10.0`).

