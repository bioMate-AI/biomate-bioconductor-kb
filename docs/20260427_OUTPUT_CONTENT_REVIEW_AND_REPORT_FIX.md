# Output Content Review, S3 Streaming, and Domain-Aware Reports

**Date:** 2026-04-27  
**Session focus:** Fix output file visibility, S3 preview/streaming, and report domain correctness

---

## Problem Statement

After ADMET AWS Batch runs completed, users saw:
1. `65781309` directory URI appearing as an "output file" 
2. `versions.yml` appearing in output list (Nextflow internal)
3. `ChatOutputAttachments` showing "No outputs" (size=0 filter blocking S3 files)
4. Preview endpoint returning 404 for S3-backed outputs
5. Methods report full of CryoSPARC-specific content for ADMET runs
6. `step-file` endpoint failing with region redirect error when streaming S3 files
7. `ai/analyze` endpoint reading no file content (wrong field: `file_path` vs `metadata.s3Uri`)

---

## Root Causes Found

### 1. Output Filtering Issues (`routes.ts`)
- S3 directory URI `s3://bucket/path/65781309` (no trailing slash) was not caught by `endsWith('/')` filter
- `versions.yml` was stored in DB from earlier server instance (before NF_INTERNAL_FILES check)
- **Fix:** Added response-time post-filter in `/api/invocations/:id/outputs` that filters on `!name.includes('.')` (no extension = directory) and `NF_INTERNAL_FILES.has(name)`

### 2. ChatOutputAttachments Size Filter (`chat-output-attachments.tsx`)
- Line: `if ((o as any).size === 0) return false` — filtered ALL S3-backed outputs (registered with size=0)
- **Fix:** Added S3 exception: `const isS3Backed = !!(o as any).metadata?.s3Uri; if (!isS3Backed && (o as any).size === 0) return false;`

### 3. Preview Endpoint Doesn't Read S3 (`routes.ts` line ~6640)
- `/api/outputs/:id/preview` only supported `localPath` and `galaxyDatasetId`
- **Fix:** Added S3 branch using `@aws-sdk/client-s3` `GetObjectCommand` with `followRegionRedirects: true`
- Required `followRegionRedirects` because `biomate-nextflow-work` is in `us-east-1` but env has `us-west-2`

### 4. Galaxy Backend Syntax Error (`nextflow_executor.py`)
- Line 4608: `f"...{particle_dir.rstrip(\"/\")  }..."` — backslash escape in f-string expression fails
- **Fix:** `particle_dir.rstrip(chr(47))` to avoid backslash in f-string

### 5. Methods Report Wrong Domain (`routes.ts` lines ~3886-4081)
- Entire report was hardcoded for CryoSPARC/cryo-EM (motion correction, CTF, FSC metrics, EMDB)  
- `isCryoEM` check only ADDED extra sections, didn't remove base cryo-EM sections
- **Fix:** Full domain detection + domain-specific extracted metrics + domain-specific LLM prompts
  - CryoEM: CryoSPARC sections with motion/CTF/FSC metrics
  - ADMET/DrugDisc: hERG IC50, DILI probability, Ames mutagenicity, Lipinski RoF
  - RNAseq: aligner, DE genes, tools
  - Variant: caller, SNP/indel counts
  - Generic: parameters + steps

### 6. step-file S3 Region Error (`routes.ts` line ~8532)
- `new S3Client({ region: 'us-west-2' })` → PermanentRedirect (bucket in us-east-1)
- **Fix:** `followRegionRedirects: true` + default region `us-east-1`
- Stream: `s3Obj.Body.pipe(res)` directly (SDK v3 returns Node.js Readable, not Web ReadableStream)

### 7. ai/analyze Missing S3 Content (`routes.ts` line ~8936)
- `const filePath = out.file_path || out.path || ''` — S3 outputs have no `file_path`
- **Fix:** `const filePath = out.metadata?.s3Uri || out.file_path || out.path || ''`
- S3 reading: replaced `aws s3 cp CLI` with `@aws-sdk/client-s3` `GetObjectCommand`

---

## Files Changed

| File | What Changed |
|------|-------------|
| `frontend/server/routes.ts` | Output filter (post-response), S3 preview, domain-aware report, step-file stream fix, ai/analyze S3 read |
| `frontend/client/src/components/chat-output-attachments.tsx` | Allow S3-backed zero-size outputs through |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | F-string syntax error on line 4608 |

---

## Verification

### Output Files (ADMET run `a985b261...`)
```
3 files returned (directory and versions.yml filtered):
- predict_admet_properties_output.txt  (text, S3)
- predict_admet_properties_results.json (table/JSON, S3)
- toxicity_report.json  (table/JSON, S3)
```

### Preview Content (`toxicity_report.json`)
```json
{
  "compounds_assessed": 2,
  "toxicity": {
    "herg_ic50_uM": 0.198,  // Terfenadine — high cardiotoxicity
    "dili_risk": "high",
    "dili_probability": 0.701,
    "ames_positive": false
  },
  "per_compound": [/* per-compound data */]
}
```

### Findings Analysis (from `/api/workflows/runs/:id/findings`)
- Summary: cardiotoxicity and DILI risks identified
- hERG IC50 = 0.198 µM (compound 2) — below 1 µM safety threshold
- DILI probability = 0.701 (high)
- logP = 7.01 (extreme lipophilicity)
- Next steps: in vitro patch-clamp assays, lead optimization
- Citations: DeepPurpose PMID 32540334, Kazius-Bursi PMID 15832503

### Methods Report (ADMET-specific)
- Abstract: hERG IC50, DILI probability, platform
- Sections 1-8: ADMET-specific (no cryo-EM content)
- Per-compound table with actual measured values
- Regulatory references: ICH E14, FDA DDI

### step-file Streaming
```
curl /api/workflows/runs/{id}/step-file?path=s3://... → 200 streaming JSON
```

---

## Test Results (Final)

### Sidebar tests: 8/8 ✅
- SB-1 New Chat ✅
- SB-2 Workflows → StarredDialog ✅  
- SB-3 Runs → /dashboard ✅ (button restored from comment)
- SB-4 CRO Library → /drug-discovery-cro ✅
- SB-5 Billing → /billing ✅ (button restored from comment)
- SB-6 Settings dialog ✅
- SB-7 Collapse/expand lifecycle ✅
- SB-8 Brand + all nav items ✅

### Natural user flow tests (quick): 5/5 ✅
- NUF-0 Galaxy dataset browser 3 tabs + file upload ✅
- NUF-2 FASTA upload → sequence analysis ✅
- NUF-3 VCF upload → variant annotation ✅
- NUF-4 AI text-first then workflow card; wf-chip "In panel" ✅
- NUF-5 Disambiguation routing ✅

### NUF-1 (ADMET AWS Batch end-to-end)
- Runs successfully but takes ~20min (disambiguation retry + 4min AWS Batch)
- Successfully submits ADMET run, monitors in real-time, checks findings
- Verified multiple complete runs: 157ba819, 49c81901 all completed

### Additional fix: sidebar nav buttons
- `button-runs-nav` and `button-billing` were commented out
- Restored both buttons so SB-3, SB-5, SB-8 tests pass

---

## Known S3 Region Issue

`biomate-nextflow-work` bucket is in `us-east-1` (GetBucketLocation returns null).  
Frontend `.env` has `AWS_REGION=us-west-2`.  
Fix: `followRegionRedirects: true` on all S3Client instances that read from this bucket.
Also default region to `us-east-1` for S3 clients (not `us-west-2`).
