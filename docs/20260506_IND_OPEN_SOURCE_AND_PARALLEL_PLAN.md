# IND Product — Open Source Tools and Parallel Build Plan

**Date:** 2026-05-06  
**Context:** Three gaps to close to make the IND report a real product:
1. PDF ingestion of GLP study reports
2. Full §2.6 coverage (§2.4, §2.6.3.1–3.5)
3. Regulatory writer workflow (tracked edits, cross-references)

---

## Gap 1 — PDF Ingestion of GLP Study Reports (Realistic Assessment)

### Why this is harder than it looks

Tested on real EMA EPAR PDFs (Otezla/apremilast, Pluvicto, Zegalogue). Findings:

- **Text extraction works fine** via PyMuPDF/pdfplumber. The regulatory prose is clean ASCII.
- **Table extraction is unreliable.** CRO study tables use merged cells, multi-line rows,
  abbreviated headers, and no standardised column ordering. pdfplumber extracts partial rows
  with empty cells. A NOAEL row extracted as:
  ```
  'NOEL for female fertility, maternal &\ndevelopmental NOAEL was 10\nmg/kg/day; AUC24h of 29,215\nng.h/mL'
  ```
  This requires heavy post-processing to extract `NOAEL = 10 mg/kg/day`.
- **No standard schema.** Charles River, Covance, Eurofins, and Covance all use different
  table layouts. A model trained on one CRO's format will fail on another's.
- **The LLM extraction step is not straightforward.** Asking Qwen3-8B (or Gemini) to extract
  structured fields from a messy 5-column regulatory table with merged cells and wrapped text
  requires careful prompt engineering and validation. Hallucination risk is real — a wrong NOAEL
  unit (mg/kg vs mg/kg/day) or species (rat vs dog) invalidates the entire section.

**This is a 3–6 month engineering effort, not 2 weeks.** The plan below reflects that.



### Realistic build plan for PDF ingestion

**Phase 1 — Text-only extraction (2 weeks, do now)**

For the prose sections of a CRO study report (the "Discussion," "Conclusion," and "Summary" pages), PyMuPDF text extraction is reliable. We can build:

```
Upload PDF → PyMuPDF text extraction → 
  LLM (Gemini, higher capacity than local) extracts:
    - Study type (Ames, micronucleus, hERG patch clamp, 28-day rat, etc.)
    - Species
    - Route of administration
    - Key conclusion (positive/negative/equivocal)
    - NOAEL (from the "Conclusion" sentence, not the table)
    - Study ID and GLP statement (regex)
  → Store in campaign DB
  → Populate §2.6.3.x placeholder
```

This avoids the table parsing problem entirely by extracting from the study conclusion paragraph. Every GLP study report has a "Results and Conclusion" section in plain prose — that's where the NOAEL and interpretation live in narrative form.

**Phase 2 — Table extraction with validation (2–3 months)**

Build a CRO-specific table extractor for the top 3 CROs (Charles River, Covance, Eurofins). This requires:
1. Collecting real GLP study report PDFs (requires CRO partnerships or anonymized sponsor donations)
2. Manual annotation of 50–100 study tables (NOAEL, dose groups, findings)
3. Train a small extraction model (or few-shot LLM with validated examples)
4. Validation layer: cross-check extracted NOAEL against narrative conclusion

**Phase 3 — LLM fine-tuning (3–6 months)**

Fine-tune a model specifically on (CRO study table → structured JSON) pairs. This is a separate training pipeline from the §2.6 prose model. Requires the annotated dataset from Phase 2.

**Key constraint:** We cannot build this without real GLP study PDFs. These are proprietary. Acquiring them requires:
- A sponsor willing to share anonymised reports
- Or a CRO partnership (Charles River, Covance) who provides sample reports

Without real training data, the extraction model will be prompt-engineered against EMA EPARs (which have summary tables) — a weaker but available proxy.

### What we have already

- **PyMuPDF** (v1.27.2, installed) — reliable text extraction from regulatory PDFs
- **pdfplumber** (v0.11.9, installed) — table extraction, works on simple tables

These are sufficient for Phase 1 (prose extraction). Phase 2 needs additional work.

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
