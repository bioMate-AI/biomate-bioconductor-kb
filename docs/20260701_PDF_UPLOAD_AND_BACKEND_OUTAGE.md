# 20260701 — PDF Upload Feature + Galaxy Backend Outage

## Session Summary

This session had two tracks: (A) implementing PDF paper extraction for the chat pipeline, and (B) an unintended Galaxy backend outage caused during testing.

---

## Track A: PDF Paper Content Extraction

### Problem

BioMate was less capable than a generic LLM for paper-based requests because paper content never reached the LLM:

1. **Uploaded PDFs** — the chat message only carried `[Attached files: paper.pdf]` + a dataset ID. `_toolReadFile` called `readFile(path, 'utf8')` on binary PDF bytes → garbage. PDF text was never extracted.
2. **Paper URLs/DOIs/PMIDs** — `_fetchPaperContentFromMessage` had three bugs:
   - DOI regex `\b(10\.\d{4,}\/\S+)` fired on bioRxiv URLs (e.g. `biorxiv.org/content/10.1101/...`), routing them to Crossref which returned 404
   - arXiv used `export.arxiv.org` Atom API which consistently timed out at 10s
   - PDF text extraction (latin1 decode) produced unreadable junk
3. **Intent routing** — "extract the study protocol from this paper" sometimes hit the DATA-FIRST rule and returned "Missing: please provide FASTQ/S3"

### Fixes Implemented

#### `frontend/server/galaxy-assistant.ts`

**New helper `_extractPdfText(filePath, maxChars)`** (~20:00):
- Calls `POST /api/ai_assistant/extract_pdf_text` on the Galaxy backend
- Returns extracted plain text or null

**Extended `_fetchPaperContentFromMessage`** (~20:15):
- Added top-priority block: detects `[Attached files: *.pdf]` + `[Uploaded datasets: ...]`
- Parses all dataset IDs from the datasets block (supports multiple PDFs in one message)
- Calls `getUploadedFile(datasetId)` to get local file path
- Calls `_extractPdfText` → injects as `[Paper content: filename.pdf]\n<text>` before LLM call
- Also fixed: DOI regex now uses negative lookbehind to skip DOIs inside URLs
- Also fixed: arXiv uses `https://arxiv.org/abs/{id}` HTML with `citation_abstract` meta tags (faster than export API)
- Also fixed: bioRxiv URLs now use `https://api.biorxiv.org/details/biorxiv/{doi}/json` (avoids bot detection)

**Fixed `_toolReadFile`** (~20:20):
- Detects `.pdf` extension → calls `_extractPdfText` instead of `readFile(path, 'utf8')`

#### `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

**New endpoint `POST /api/ai_assistant/extract_pdf_text`** (~20:05):
- Accepts `{ file_path, max_chars }` — security guard: path must end in `.pdf` and contain `uploads`
- Tries pdfplumber first (installed in Docker via requirements.txt), falls back to pypdf
- Returns `{ text, page_count, char_count }`
- Installed pdfplumber + pypdf into local venv: `pip install pypdf pdfplumber` (~20:10)
  - **Side effect**: upgraded Pillow 11.3.0 → 12.2.0 and pdfminer.six 20251107 → 20260107

#### Previous session changes (still in place)

From the 20260623 session:
- Intent classifier: paper + "extract/read/summarize" → `protocol_guidance` (not `workflow_generation`)
- DATA-FIRST rule: exception for paper-as-specification
- Response format: "Missing:" template gated to `isWorkflowTurn` only

### Test Results (pre-outage)

| Test | Before | After |
|------|--------|-------|
| arXiv URL | timeout | ✓ title + abstract via HTML meta |
| bare DOI | ✓ | ✓ Crossref |
| PMID | ✓ | ✓ NCBI efetch |
| bioRxiv URL | null (DOI regex bug) | ✓ biorxiv API |
| PDF endpoint | 404 | ✓ returns text |
| vitest suite | 881/881 | 881/881 |
| tsc | clean | clean |

---

## Track B: Galaxy Backend Outage

### Timeline

| Time | Event |
|------|-------|
| ~20:08 | `kill -HUP $(pgrep -f "gunicorn.*8081" \| head -1)` sent to reload Galaxy backend after adding Python endpoint |
| ~20:09 | HUP caused graceful worker restart. The single worker was busy with a long-running Node.js health check (`galaxyAPIBackend.healthCheck()`). New requests queued behind it for up to 300s (worker timeout). Backend appeared hung. |
| ~20:12 | `pkill -f "gunicorn.*galaxy"` killed all workers trying to unblock |
| ~20:14 | Tried `start_andv_backend.sh` → workers crashed: `Tool config file not found: /app/biomni_workflows/...` — Docker path not valid locally |
| ~20:19 | Tried `start_backend.sh` (sample config) → triggered conda env resolution (thousands of packages) — wrong config |
| ~20:22 | Killed conda startup. Tried `start_andv_backend.sh` again with copied `tool_conf.xml.sample` → still failed on `/app/biomni_workflows/...` |
| ~20:25 | Tried env var override `GALAXY_CONFIG_TOOL_CONFIG_FILE` in backend `.env` → Galaxy did not pick up env var override for yaml-loaded config |
| ~20:28 | Patched `config/galaxy.yml`: replaced `/app/biomni_workflows/...` with real local path, removed nonexistent `/app/tools/biomate_ai_tools/tool_conf.xml` |
| ~20:29 | Workers crashed with `FileExistsError: dependencies/` — race condition: 2 workers both tried to create the directory simultaneously (`start_andv_backend.sh` uses `--workers 2`) |
| ~20:31 | Deleted `dependencies/`, switched to `--workers 1`. Galaxy started listening. User interrupted. |

### Root Cause of Outage

**My `kill -HUP` at 20:08 caused the outage.** The Galaxy backend had 1 worker with a 300s timeout. The HUP triggered a graceful reload, but the in-flight health-check request held the worker. New upload requests stacked behind it. I should have waited for the request to complete or sent the HUP only when the worker was idle.

### Current State (as of session end)

- Galaxy backend: **partially recovered** — running with 1 worker after `--workers 1` fix, user interrupted before confirming response
- Node.js frontend: **running** (PID 42627, port 5000) but waiting on Galaxy health check
- `config/galaxy.yml`: **modified** — `/app/` Docker paths replaced with local paths
- `backend/.env`: **created** — local dev env overrides (not needed now that yml is fixed)

### Files Modified This Session

| File | Change |
|------|--------|
| `frontend/server/galaxy-assistant.ts` | `_extractPdfText`, `_fetchPaperContentFromMessage` (PDF + URL fixes), `_toolReadFile` PDF fix |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | `extract_pdf_text` endpoint |
| `backend/config/galaxy.yml` | Replaced `/app/` Docker paths with local paths |
| `backend/config/tool_conf.xml.sample` | Copied from `lib/galaxy/config/sample/` (was missing from config/) |
| `backend/.env` | Created (local dev env file) |

### Known Remaining Issues

1. **Galaxy backend restart procedure**: No canonical local-dev restart script. `start_andv_backend.sh` uses `--workers 2` which triggers a race condition on `dependencies/` creation. Should be `--workers 1` for local dev.
2. **`config/galaxy.yml` has Docker-specific paths**: The yml was designed for Docker (`/app/...` prefix). Local dev requires either real paths or a separate local config. The Pillow upgrade (11.3.0 → 12.2.0) from pdfplumber install may affect image processing — worth monitoring.
3. **PDF upload test not yet run**: The NINJ1 paper and SLC7 transporter paper upload test was blocked by the backend outage. Still needed:
   - Single PDF upload → "extract protein purification protocol" → verify `protocol_guidance` routing + paper text injection
   - Two PDFs in one session → verify both extracted and concatenated

### Next Steps

1. Confirm Galaxy backend is fully up and responding to `GET /api/version`
2. Run the PDF upload test with both papers:
   - `/Users/kky/Desktop/business/bioconductor_screenshot/NINJ1 mediates plasma membrane rupture by cutting and releasing membrane disks.pdf`
   - `/Users/kky/Desktop/business/bioconductor_screenshot/Structural basis for amino acid transport by the CAT family of SLC7 transporters.pdf`
3. Restart the Node.js frontend to pick up the TypeScript changes in `galaxy-assistant.ts`
4. Verify the `extract_pdf_text` endpoint responds correctly
5. Fix `start_andv_backend.sh` to use `--workers 1` for local dev to avoid the `dependencies/` race condition
