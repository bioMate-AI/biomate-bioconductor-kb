# RStudio Integration E2E Test Plan
**Date**: 2026-06-01
**Feature**: Step output → RStudio launch integration
**Component**: `step-output-preview.tsx` (new RStudio affordances)

---

## What was added

1. **R object viewer** (`.rds`, `.rdata`): File routed to `RObjectPreview` — shows file info + "Open in RStudio" button. Clicking opens `InteractiveLauncher` dialog with file pre-loaded.

2. **Table viewer + RStudio action** (`.csv`, `.tsv`, `.json`, `.tabular`): Existing inline table viewer unchanged. After table renders, a "Analyze in RStudio" secondary button appears below a divider. Clicking opens `InteractiveLauncher` with file pre-loaded.

3. **InteractiveLauncher wiring**: Both paths pass `{ id: file.path, name: file.name, size: 0, type: file.extension }` as the `outputs` prop, with RStudio pre-selectable in the dialog.

---

## Test scenarios

### Scenario A: CSV step output → "Analyze in RStudio" button
**Trigger**: Run a DESeq2 / RNA-seq differential expression workflow that produces a `.csv` results file.
**Expected steps**:
1. Send query: "Run differential expression analysis with DESeq2 on example RNA-seq data. Output results as a CSV file."
2. Wait for workflow card in panel.
3. Click Run → wait for completed state.
4. Expand step outputs → find a `.csv` file.
5. Click the file → step output preview opens.
6. Verify: table renders (rows visible).
7. Verify: "Analyze in RStudio" button appears below table.
8. Verify: hint text "Opens with this file pre-loaded" is visible.
9. Click "Analyze in RStudio" → `InteractiveLauncher` dialog opens.
10. Verify: dialog title contains "Launch Interactive Environment".
11. Verify: file name appears in "Data to Load" section.
12. Verify: RStudio option is available in tool selection.

**Pass criteria**: Button visible, dialog opens, file listed in dialog.

### Scenario B: RDS step output → "Open in RStudio" button
**Trigger**: Run a workflow that saves an R object as `.rds` (e.g., DESeq2 object, Seurat object).
**Expected steps**:
1. Send query: "Run DESeq2 analysis and save the DESeqDataSet object as an RDS file."
2. Wait for workflow completion.
3. Expand step outputs → find a `.rds` file.
4. Click the file → `RObjectPreview` renders.
5. Verify: description "R serialised object (RDS)" is shown.
6. Verify: "Open in RStudio" button is visible (no inline table/image content).
7. Click "Open in RStudio" → `InteractiveLauncher` dialog opens.
8. Verify: file name in dialog outputs list.

**Pass criteria**: "Open in RStudio" button visible, no table/image rendered, dialog opens correctly.

### Scenario C: Extension routing correctness (UI verification)
**Goal**: Confirm correct viewer routing without running a full pipeline.
**Method**: Directly test the `resolveViewer` logic by checking which viewer is rendered per file extension.
**Assertions (via the UI after a completed run)**:
- `.png` → image viewer with lightbox, no RStudio button
- `.csv` → table grid + "Analyze in RStudio" button
- `.tsv` → table grid + "Analyze in RStudio" button  
- `.rds` → "R serialised object" message + "Open in RStudio" button, no table
- `.rdata` → same as `.rds`
- `.vcf` → variant table, no RStudio button
- `.fasta` → sequence viewer, no RStudio button
- `.pdb` → 3Dmol.js viewer, no RStudio button
- `.mrc` → density slice viewer, no RStudio button

### Scenario D: InteractiveLauncher dialog state
**Goal**: When opened from step output, dialog must default correctly.
**Assertions**:
- Dialog contains tool options (Jupyter, RStudio, CellxGene)
- The pre-loaded file appears in "Data to Load" section
- "Launch RStudio" button is active after selecting RStudio
- Cancel dismisses the dialog without launching

### Scenario E: TSV file from RNA-seq (real pipeline)
**Trigger**: nf-core/rnaseq or similar pipeline that outputs `.tsv` count matrix.
**Expected**: table viewer + "Analyze in RStudio" visible when step file is opened.

---

## Test implementation notes

### File: `e2e/rstudio-step-integration.e2e.ts`

**Approach**: 
- Use a real DESeq2 / bioinformatics query (no mocking)
- Wait up to 15 min for workflow completion (matches existing output-visualization.e2e.ts pattern)
- If workflow doesn't produce expected file type, test logs a skip note and passes
- Screenshot every key state

**Key selectors**:
- Step output trigger: `[data-testid="step-file-item"]` or file name buttons in step output list
- Preview container: `[data-testid="step-output-preview"]` or `.mt-2.border.rounded-md`
- RStudio button (table): `button:has-text("Analyze in RStudio")`
- RStudio button (R object): `button:has-text("Open in RStudio")`
- InteractiveLauncher dialog: `[role="dialog"]:has-text("Launch Interactive Environment")`
- File in dialog: `text=Data to Load`

**Known limitations**:
- Full Bioconductor pipeline runs can take 10–30 min on AWS Batch
- RDS output files require a Bioconductor workflow to actually run (not just select)
- The InteractiveLauncher sends to `/api/interactive/launch` — this will fail unless a Galaxy interactive tool backend is running; test should verify the dialog opens, not that the session starts

---

## What NOT to test here
- Whether the RStudio session successfully launches (that's backend/Galaxy infrastructure)
- Whether the file actually loads in RStudio (requires running session)
- API contract of `/api/interactive/launch` (already tested in integration tests)

---

## Success criteria

| Test | Pass condition |
|------|---------------|
| A (CSV) | "Analyze in RStudio" button appears after CSV preview loads |
| B (RDS) | "Open in RStudio" button appears; no table/image rendered |
| C (routing) | Each file type renders correct viewer affordances |
| D (dialog) | Dialog opens, file listed, cancel works |
| E (TSV) | Same as A but with TSV format |
