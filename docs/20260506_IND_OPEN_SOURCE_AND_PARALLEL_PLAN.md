# IND Product — Open Source Tools and Parallel Build Plan

**Date:** 2026-05-06  
**Context:** Three gaps to close to make the IND report a real product:
1. PDF ingestion of GLP study reports
2. Full §2.6 coverage (§2.4, §2.6.3.1–3.5)
3. Regulatory writer workflow (tracked edits, cross-references)

---

## Gap 1 — PDF Ingestion of GLP Study Reports

### What we have already

- **PyMuPDF** (v1.27.2, installed) — fast PDF text and layout extraction
- **pdfplumber** (v0.11.9, installed) — table extraction from PDFs, already used in the EPAR collector

These two together can handle most CRO study reports. We do not need to install Docling or Unstructured for the MVP.

### Open source tools

| Tool | License | What it does | Fit |
|------|---------|-------------|-----|
| **PyMuPDF** | AGPL/commercial | Text + layout + table extraction | ✅ Already installed |
| **pdfplumber** | MIT | Table extraction, works well for structured tables | ✅ Already installed |
| **Docling** (IBM) | Apache 2.0 | Full document understanding, markdown output, table + figure detection | Strong option, not installed |
| **Marker** | GPL 3.0 | PDF→Markdown conversion, good on scientific PDFs | Medium fit |
| **Camelot** | MIT | PDF table extraction only | Too narrow |
| **GROBID** | Apache 2.0 | ML-based header/section/reference extraction, needs Java server | Overkill |

**Recommendation: use PyMuPDF + pdfplumber first.** We already have them. The extraction pipeline is:

```python
# Step 1: Text extraction (PyMuPDF)
import fitz  # PyMuPDF
doc = fitz.open("study_report.pdf")
text = "\n".join(page.get_text() for page in doc)

# Step 2: Table extraction (pdfplumber)
import pdfplumber
with pdfplumber.open("study_report.pdf") as pdf:
    tables = [table for page in pdf.pages for table in page.extract_tables()]

# Step 3: LLM field extraction (Qwen3-8B, already running)
# Pass text chunks to local model with prompt:
# "Extract: species, dose_groups, NOAEL, findings, study_director, GLP_statement, study_dates"
# This is exactly what our fine-tuned model is good at
```

**If table extraction quality is insufficient** (CRO PDFs with complex formatting): install Docling (`pip install docling`). It uses a layout model to detect table regions and reconstruct them more reliably. One-line replacement:

```python
from docling.document_converter import DocumentConverter
result = DocumentConverter().convert("study_report.pdf")
markdown = result.document.export_to_markdown()
```

### What the ingestion pipeline looks like

```
POST /api/drug-discovery/:id/ingest-study-report
  → Upload PDF
  → PyMuPDF: extract text + page layout
  → pdfplumber: extract data tables
  → Qwen3-8B (or Gemini): extract structured fields
      { species, dose_groups, NOAEL, key_findings, study_type, GLP_statement }
  → Map to §2.6 section:
      - "28-day repeat dose rat" → §2.6.3.2 slot
      - "Ames test" → §2.6.3.3 slot
      - "hERG patch clamp" → §2.6.3.7 slot
  → Store in campaign DB
  → Trigger §2.6 section regeneration with real data

GET /api/drug-discovery/:id/ind-assembly (already exists)
  → Now uses real study data where uploaded, computational where not
```

This endpoint already has a stub (`/api/drug-discovery/:id/ingest-assay` in `routes.ts`). We extend it for full study reports, not just assay CSVs.

**Build time: 1–2 weeks.** The extraction code is the EPAR collector pattern in reverse.

---

## Gap 2 — Full §2.6 Coverage

### What's missing

| Section | Status | Blocker |
|---------|--------|---------|
| **§2.4 Nonclinical Overview** | ❌ Missing | Pure LLM work, no new infra needed |
| §2.6.3.1 Single-dose toxicity | ❌ Missing | Needs study data input |
| §2.6.3.2 Repeat-dose toxicity | ❌ Missing | Needs study data input (Gap 1 dependency) |
| §2.6.3.5 Reproductive toxicity | ❌ Missing | Needs study data input |

### Open source tools

None needed — this is prompt engineering + LLM work on top of what we have. The ICH M4S(R2) structure defines the exact schema. Our fine-tuned Qwen3-8B model writes the prose.

### §2.4 — Start immediately, no dependencies

§2.4 Nonclinical Overview is a 3–8 page narrative that summarizes §2.6.1–§2.6.3 at a high level. It does not need additional study data — it synthesizes what we already generate.

```python
# New section type in ind_assembly.py
def _build_24_overview(ctx: dict, region: str) -> str:
    """
    §2.4 Nonclinical Overview — synthesizes §2.6.1–§2.6.3 into 
    a 600–1200 word executive summary for the reviewer.
    """
    user_prompt = f"""
    Write §2.4 Nonclinical Overview for {ctx['drug']} targeting {ctx['target']}.
    
    Available data:
    - PBPK qualification: {ctx.get('pbpk_summary', 'not available')}
    - ADMET screening: {ctx.get('admet_summary', 'not available')}
    - Genotoxicity: {ctx.get('genotox_summary', 'not available')}
    - Cardiac safety: {ctx.get('cardiac_summary', 'not available')}
    
    Per ICH M4S(R2): state the primary pharmacodynamics, safety pharmacology,
    PK profile, and toxicology findings in 600–1200 words.
    Cite applicable ICH guidelines (M3(R2), S7A, S7B, S2(R1)).
    """
    return _llm_narrative("nonclinical_overview", ctx, region)
```

**Build time: 3–5 days.** New section type, new system prompt, wire into the DOCX builder.

### §2.6.3.1 and §2.6.3.2 — Depend on Gap 1

These sections require actual in vivo toxicology data. The right approach while Gap 1 is building:

```python
# Structured placeholder that becomes real when data is uploaded
def _build_2631_single_dose(ctx: dict, region: str) -> str:
    if ctx.get("single_dose_study"):
        # Real data: generate from study parameters
        return _llm_narrative("single_dose_tox", ctx, region)
    else:
        # Placeholder: structured template with study design gaps marked
        return """
        Section 2.6.3.1 — Single-Dose Toxicity
        
        [AWAITING DATA: Upload GLP single-dose toxicity study report via 
        the "Add study data" button to populate this section.]
        
        Planned study design:
        - Species: {species} (primary), {secondary_species} (secondary)  
        - Route: {route_of_administration}
        - Dose range: [to be determined from dose-range finding study]
        """.format(**ctx)
```

This gives the document a complete structure immediately, with slots that fill in when data arrives. The regulatory writer sees the skeleton and knows exactly what studies are still pending.

---

## Gap 3 — Regulatory Writer Workflow

### Open source tools

| Tool | License | What it does | Fit |
|------|---------|-------------|-----|
| **TipTap** | MIT (core) | ProseMirror-based rich text editor, React component | ✅ Best fit |
| **TipTap Track Changes** | Commercial (Pro) | Track changes extension | ⚠️ Paid |
| **Yjs** | MIT | CRDT for real-time collaboration | ✅ Optional |
| **ProseMirror** | MIT | Core editor, TipTap builds on it | Underlying |
| **Quill** | BSD | Simpler editor, less extensible | Lower fit |
| **Monaco Editor** | MIT | VS Code editor, overkill for prose | Wrong tool |

**Track changes alternatives (open source):**
- **`prosemirror-changeset`** (MIT) — computes diffs between document versions. We can track v0 (AI draft) vs vN (human-edited) and display additions/deletions.
- **DOCX export with revisions** — python-docx can generate DOCX files with tracked change markup (`<w:ins>`, `<w:del>` elements). The regulatory writer can then accept/reject in Microsoft Word.

**Recommendation:** TipTap (free core) + `prosemirror-changeset` for diff tracking + DOCX export with revisions. This avoids the TipTap Pro fee while still giving the workflow.

### What the workflow looks like

```
Current state:
  [Generate] → [View PDF/DOCX] → [Sign]

Target state:
  [Generate AI draft]
       ↓
  [TipTap editor: regulatory writer annotates inline]
  - AI-generated text: blue highlight
  - Human-edited text: no highlight  
  - Flagged for review: amber border (maps to our current audit finding display)
       ↓
  [Section completeness checker]
  - Checklist against ICH M4S(R2) requirements
  - Per-section: ✅ Complete / ⚠️ Placeholder / ❌ Missing
       ↓
  [Cross-reference validator]  
  - Any numeric value (IC50, NOAEL, AUC) → linked to source study
  - Clicking a value shows the page in the uploaded study PDF
       ↓
  [Regulatory writer approves] → [eSig (already built)] → [Locked DOCX]
```

### Implementation: TipTap in the document panel

```tsx
// Replace current static document render in ind-report.tsx
// with a TipTap editor instance

import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import { Highlight } from '@tiptap/extension-highlight'

const DocumentEditor = ({ content, onEdit, isLocked }) => {
  const editor = useEditor({
    extensions: [
      StarterKit,
      Highlight.configure({ multicolor: true }),  // AI vs human spans
    ],
    content,
    editable: !isLocked,
    onUpdate: ({ editor }) => onEdit(editor.getJSON()),
  })
  return <EditorContent editor={editor} />
}
```

The current document panel renders markdown as static HTML. TipTap replaces that with an editable div. The rest of the eSig and DOCX infrastructure stays identical.

**Build time: 1–2 weeks** for the editor integration + diff tracking.

---

## Parallel Execution Plan

These three tracks are almost entirely independent. They share only the `/api/drug-discovery/:id/ind-assembly` endpoint as integration point.

```
Week 1–2:    TRACK A (Backend)          TRACK B (LLM)           TRACK C (Frontend)
             PDF ingestion endpoint      §2.4 section type       TipTap editor in document panel
             PyMuPDF + pdfplumber        New prompt + training    Replace static markdown render
             Field extraction LLM call   pair for §2.4           AI-generated text highlighting

Week 3–4:    TRACK A                    TRACK B                  TRACK C
             Map study types → §2.6     §2.6.3.1–3.2 placeholders Diff tracking (prosemirror-changeset)
             slots in DB                "Awaiting data" UX        Section completeness checklist

Week 5–6:    TRACK A                    TRACK B                  TRACK C
             Test on real CRO PDFs      Wire placeholders →       Cross-reference linking
             (Charles River template)    real data pipeline        (value → study PDF page)
             Section regeneration        from Track A              DOCX export with revisions
```

**Integration point at week 6:** All three tracks converge in a demo where:
- A GLP Ames test report PDF is uploaded (Track A)
- It fills the §2.6.3.3 section with real extracted data (Track A+B)
- The regulatory writer edits the generated prose in the TipTap editor (Track C)
- Diff shows AI draft vs human-edited version (Track C)
- Writer clicks Sign → 21 CFR Part 11 compliant eSig on the final document (existing)

---

## What to Build First

If this is a single engineer or two engineers in parallel:

**Do first (one person, 3–5 days):** §2.4 Nonclinical Overview  
- No new infrastructure. Pure LLM section. Immediate value.
- Every IND needs a §2.4 — this alone closes a gap that blocks real use.

**Do in parallel (two tracks, 2 weeks):**
- Backend: PDF ingestion endpoint (PyMuPDF + pdfplumber, already installed)
- Frontend: TipTap editor replacing the static document viewer

The PDF ingestion backend and the TipTap frontend have zero shared code and can be built simultaneously. The backend engineer writes the extractor; the frontend engineer replaces the markdown renderer with TipTap. They connect at week 2 when the backend returns section data that TipTap renders as editable content.

**Do last (dependency on both):** Actual §2.6.3.x sections with real data, cross-reference linking.

---

## Install Checklist (when ready to build)

```bash
# Backend (Gap 1)
pip install docling  # If PyMuPDF+pdfplumber prove insufficient

# Frontend (Gap 3)
npm install @tiptap/react @tiptap/core @tiptap/starter-kit @tiptap/extension-highlight
npm install prosemirror-changeset  # For diff tracking (MIT)
npm install @tiptap/extension-placeholder @tiptap/extension-character-count
# Note: do NOT install @tiptap/extension-track-changes (Pro, paid)
# Use prosemirror-changeset instead

# No new backend ML dependencies needed
# Qwen3-8B v2 adapter (already trained) handles §2.4 extraction
```
