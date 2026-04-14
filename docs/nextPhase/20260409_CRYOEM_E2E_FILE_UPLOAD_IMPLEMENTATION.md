# Cryo-EM E2E File Upload Implementation

**Date**: 2026-04-09  
**Branch**: integration/next-phase  
**Status**: 6/6 E2E tests PASS, 39/43 internal assertions PASS

---

## Summary

Implemented end-to-end file upload simulation in the cryo-EM E2E test suite, where a user uploads a `.mrc` movie file via the chat file picker and it automatically populates the `movies_path` workflow parameter.

---

## Changes Made

### 1. `frontend/client/src/components/chat-input.tsx`

**Problem**: The `#chat-file-input` element was inside `<PopoverContent>` (Radix UI portal). Radix only mounts portal content when the popover is open. Playwright's `setInputFiles()` timed out with 60s because the element wasn't in the DOM.

**Fix**: Moved `<input type="file" id="chat-file-input">` **outside** the `<PopoverContent>`, making it always present in the DOM. Added `data-testid="chat-file-input"` and `data-testid="chat-attach-button"` for E2E selector reliability.

```tsx
{/* Hidden file input — always in DOM so E2E tests can setInputFiles at any time */}
<input
  ref={fileInputRef}
  type="file"
  accept={acceptedTypes}
  multiple
  onChange={handleFileSelect}
  className="hidden"
  id="chat-file-input"
  data-testid="chat-file-input"
  aria-hidden="true"
/>
```

Also extended `acceptedTypes` to include cryo-EM formats: `.mrc,.mrcs,.tif,.tiff,.eer,.spi,.dm4`

---

### 2. `frontend/server/routes.ts`

**Problem**: The multer `fileFilter` rejected `.mrc` and other cryo-EM formats with HTTP 500 ("File type not supported"), causing `[Upload warnings: actin_movies.mrc (HTTP 500)]` in the backend log.

**Fix**: Added cryo-EM file extensions to the `allowedExtensions` list:

```typescript
// Cryo-EM / electron microscopy formats
'.mrc', '.mrcs', '.tif', '.tiff', '.eer', '.spi', '.dm4', '.map',
```

Also improved upload rejection toast message to show the rejected extension and list supported types.

---

### 3. `backend/lib/galaxy/ai/ai_assistant.py`

**Added**: `_FILE_TYPE_TO_PARAM` class dict and `_inject_uploaded_files_into_params()` method (already present from prior session).

**Added**: Format mismatch detection at the end of `_inject_uploaded_files_into_params`. When an uploaded file's extension maps to a cryo-EM or sequencing param type but the selected workflow has no matching parameter, a `format_mismatch_warning` is attached to the first param with a human-readable message:

```python
"Your uploaded file (.mrc) appears to be a cryo-EM movie file (.mrc/.tif/.eer). 
This workflow may not be designed for this data type — 
consider using a cryo-EM SPA or ET workflow instead."
```

---

### 4. `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Added**: Format mismatch warning banner at the top of the Parameters section. Reads `format_mismatch_warning` from any param in `required_params` or `optional_params`:

```tsx
{/* Format mismatch warning */}
<div className="... border-amber-300 bg-amber-50 ..." data-testid="format-mismatch-warning">
  ⚠️ {mismatch.format_mismatch_warning}
</div>
```

Also added `data-testid="workflow-overall-status-badge"` and `data-status={status}` to the top-level status badge to fix terminal status detection in E2E tests.

---

### 5. `frontend/client/src/components/chat-interface.tsx`

**Improved**: Upload rejection toast now shows rejected extension and supported types:

```typescript
toast({
  title: `1 file could not be uploaded`,
  description: `Unsupported format: .xyz. Supported types: FASTQ, BAM, SAM, CSV, TSV, FASTA, VCF, BED, MRC, TIFF, EER.`,
  variant: 'destructive',
});
```

---

### 6. `frontend/e2e/cryoem-workflows-ux-e2e.e2e.ts`

**Fixed**: `attachFileAndSendMessage()` — now uses `[data-testid="chat-file-input"]` with `waitFor({ state: "attached" })` + try/catch.

**Fixed**: `movies_path` assertion selector — `type='file'` params render `<Input id="{name}">` not `data-testid="param-inline-edit-{name}"`:

```typescript
const moviesInput = page.locator(
  'input#movies_path, ' +
  '[data-testid="param-inline-edit-movies_path"] input, ' +
  '[data-testid="param-inline-edit-movies_path"]'
).first();
```

**Fixed**: CE-2 `helical_rise_angstroms` and `helical_twist_deg` selectors — same issue, use `input#helical_rise_angstroms`.

**Fixed**: CE-1 triage assertion — changed to `[data-testid="execution-triage-summary"]` which is the actual testid in the viewer.

---

## File Upload Flow (End-to-End)

```
User picks .mrc via chat + icon
    │
    ▼
handleFileSelect() → attachedFiles state
    │
    ▼
handleSend() → onSend(message, [file])
    │
    ▼
POST /api/datasets/upload (multer, local disk)
  → req.session.uploadedDatasets.push({ name, file_path: "/path/to/upload.mrc" })
    │
    ▼
POST /api/chat/message
  → sessionDatasets built from req.session.uploadedDatasets
  → includes file_path
    │
    ▼
AI: _return_nextflow_match()
  → _inject_uploaded_files_into_params(req, opt, uploaded_datasets)
  → maps .mrc → movies_path → sets default = "/path/to/upload.mrc"
  → autoFilled = true
    │
    ▼
Viewer: movies_path input shows local path
Run button enabled (movies_path no longer empty)
```

---

## Test Results

| Test | Assertions | Status |
|------|-----------|--------|
| CE-0 QC profiles API | 1/1 | ✅ PASS |
| CE-1 CryoSPARC SPA full journey | 14/14 | ✅ PASS |
| CE-2 Helical SPA params | 7/7 | ✅ PASS |
| CE-3 QC settings panel | 10/10 | ✅ PASS |
| CE-4 Output visualization | 4/8 (4 expected failures*) | ✅ PASS |
| CE-5 Session isolation | 3/3 | ✅ PASS |

*CE-4 output assertions require a real completed run. Stub 1KB MRC data fails immediately with no output files produced. These are soft assertions (don't fail the test).

---

## Format Incompatibility Notifications

| Scenario | User notification |
|----------|------------------|
| Unsupported extension (e.g. `.xyz`) | Toast: "Unsupported format: .xyz. Supported types: ..." |
| Right format, wrong workflow (e.g. `.mrc` + genomics) | Yellow banner in Parameters panel: "Your file appears to be a cryo-EM movie file. Consider using a cryo-EM SPA or ET workflow." |
| Right format, right workflow | File auto-fills `movies_path`, blue highlight on field |
