# BioMate Report Generation Architecture

**Document Created:** 2025-10-28
**Priority:** P2 - Platform Maturity (Month 2-4)
**Status:** Architecture Specification
**Estimated Implementation:** 4-6 weeks

---

## Executive Summary

This document defines the report generation system for BioMate platform, enabling users to create publication-ready analysis reports, clinical reports, and custom documentation from workflow results. The system must support multiple report types, custom templates, citations, and export formats (PDF, HTML, DOCX).

**Key Features:**
- Automated report generation from workflow results
- Template library (RNA-seq, variant calling, spatial transcriptomics, etc.)
- Custom template upload support
- Citation management (automatic bibliography)
- Interactive figures and tables
- Multiple export formats (PDF, HTML, DOCX, LaTeX)
- Compliance-ready reports (clinical labs)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Report Types](#report-types)
3. [Template System](#template-system)
4. [Data Extraction](#data-extraction)
5. [Rendering Engine](#rendering-engine)
6. [Citation Management](#citation-management)
7. [Export Formats](#export-formats)
8. [API Design](#api-design)
9. [Implementation Plan](#implementation-plan)

---

## Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      Workflow Results                            │
├─────────────────────────────────────────────────────────────────┤
│  • Output files (BAM, VCF, plots, tables)                       │
│  • Execution metadata (parameters, runtime)                     │
│  • Tool citations                                               │
│  • Quality metrics                                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                   Data Extraction Service                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │   File       │   │   Metadata   │   │  Citations   │       │
│  │  Parsers     │   │  Extractor   │   │  Collector   │       │
│  └──────────────┘   └──────────────┘   └──────────────┘       │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                            ↓                                     │
│                  ┌──────────────────┐                           │
│                  │  Structured Data │                           │
│                  │     (JSON)       │                           │
│                  └──────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Template Engine                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐      │
│  │             Template Library                          │      │
│  ├──────────────────────────────────────────────────────┤      │
│  │  • RNA-seq Analysis Report                            │      │
│  │  • Variant Calling Report                             │      │
│  │  • Spatial Transcriptomics Report                     │      │
│  │  • Clinical Variant Report (CAP/CLIA)                │      │
│  │  • QC Summary Report                                  │      │
│  │  • Custom Templates (user-uploaded)                   │      │
│  └──────────────────────────────────────────────────────┘      │
│                            ↓                                     │
│                  ┌──────────────────┐                           │
│                  │  Template Parser │                           │
│                  │   (Handlebars)   │                           │
│                  └──────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Rendering Engine                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │   Markdown   │──▶│     HTML     │──▶│     PDF      │       │
│  │  + Citations │   │  (with CSS)  │   │  (WeasyPrint)│       │
│  └──────────────┘   └──────────────┘   └──────────────┘       │
│         │                   │                   │               │
│         │                   ├──────────▶ DOCX (Pandoc)         │
│         │                   └──────────▶ LaTeX (optional)      │
│         │                                                        │
│         └────────────────────────────────▶ Interactive HTML    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Report Storage (S3)                         │
├─────────────────────────────────────────────────────────────────┤
│  • Generated reports (PDF, HTML, DOCX)                          │
│  • Report metadata (author, date, version)                      │
│  • Audit trail (for clinical reports)                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                         User Access                              │
├─────────────────────────────────────────────────────────────────┤
│  • Download report                                              │
│  • Share report (secure link)                                   │
│  • Re-generate with different template                          │
│  • Customize sections                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Report Types

### 1. RNA-seq Analysis Report

**Use Case:** Gene expression analysis, differential expression

**Sections:**
1. Executive Summary
   - Sample information
   - Key findings
   - Differentially expressed genes (up/down)

2. Methods
   - Workflow description
   - Tool versions and parameters
   - Reference genome

3. Quality Control
   - FastQC results
   - Alignment statistics
   - PCA plot

4. Results
   - Differential expression table
   - Volcano plot
   - Heatmap (top DEGs)
   - GO enrichment analysis

5. Discussion
   - Biological interpretation (AI-generated summary)
   - Limitations

6. References
   - Tool citations
   - Method citations

**Example Output:**

```markdown
# RNA-seq Analysis Report

## Executive Summary

**Project:** Mouse Brain Development Study
**Sample Count:** 12 (6 control, 6 treated)
**Date:** 2025-10-28
**Analyst:** BioMate AI

### Key Findings
- 1,234 differentially expressed genes (FDR < 0.05)
- 678 upregulated, 556 downregulated
- Top enriched pathways: neuronal development, synapse formation

---

## Methods

### Workflow
1. Quality Control: FastQC v0.11.9
2. Alignment: STAR v2.7.10b (GRCm39 reference)
3. Quantification: featureCounts v2.0.1
4. Differential Expression: DESeq2 v1.34.0

### Parameters
- Minimum read count: 10
- FDR threshold: 0.05
- Log2 fold change: ±1.5

---

## Quality Control

### Sequencing Quality
- Mean Phred score: 36.5
- Adapter contamination: <0.1%
- Duplication rate: 12.3%

### Alignment Statistics
- Uniquely mapped reads: 85.2% (avg)
- Multi-mapped reads: 5.3%
- Unmapped reads: 9.5%

[INSERT: PCA plot showing sample clustering]

---

## Results

### Differential Expression

Table 1: Top 10 differentially expressed genes

| Gene    | Log2FC | FDR      | Function                    |
|---------|--------|----------|-----------------------------|
| Bdnf    | 3.45   | 1.2e-45  | Neuronal growth factor      |
| Syn1    | 2.89   | 3.4e-38  | Synaptic vesicle protein    |
| ...

[INSERT: Volcano plot]
[INSERT: Heatmap of top 50 DEGs]

### GO Enrichment Analysis

Top enriched biological processes:
- Synapse organization (FDR: 1.2e-12)
- Axon guidance (FDR: 3.4e-10)
- Neuronal development (FDR: 5.6e-09)

---

## Discussion

The analysis revealed significant upregulation of neuronal development genes,
consistent with the expected brain maturation phenotype. Key markers include
Bdnf and Syn1, which are critical for synapse formation...

### Limitations
- Sample size relatively small (n=6 per group)
- Batch effects not fully corrected
- Recommend validation by qPCR

---

## References

1. Dobin et al. (2013) STAR: ultrafast universal RNA-seq aligner. Bioinformatics.
2. Liao et al. (2014) featureCounts: an efficient general purpose program...
3. Love et al. (2014) Moderated estimation of fold change and dispersion...

---

**Report Generated:** 2025-10-28 10:30:00
**BioMate Version:** 1.0.0
**Workflow ID:** wf_abc123
```

---

### 2. Variant Calling Report

**Use Case:** WGS/WES variant analysis, clinical genomics

**Sections:**
1. Patient Information (de-identified for research, full for clinical)
2. Sequencing QC
3. Variant Calling Statistics
4. Variant Classification (pathogenic, likely pathogenic, VUS, benign)
5. Clinically Relevant Variants (table)
6. Structural Variants (if applicable)
7. Interpretation and Recommendations

**Clinical Variant Report (CAP/CLIA Compliant):**

```markdown
# Clinical Variant Report

**Patient ID:** [REDACTED]
**Accession Number:** 2025-10-28-001
**Ordering Physician:** Dr. Jane Smith
**Report Date:** 2025-10-28
**Reporting Lab:** BioMate Clinical Laboratory (CLIA #: 123456)

---

## Clinical Indication

**Test Ordered:** Whole Exome Sequencing (WES)
**Indication:** Suspected hereditary cancer syndrome

---

## Results

### Pathogenic Variants Detected

#### Variant 1: BRCA1 c.5266dupC (p.Gln1756fs)
- **Classification:** Pathogenic
- **Inheritance:** Autosomal Dominant
- **Zygosity:** Heterozygous
- **VAF:** 48.2%
- **Evidence:**
  - ClinVar: Pathogenic (4-star)
  - ACMG Criteria: PVS1, PM2, PP5
  - Reference: Myriad Genetics database

**Clinical Significance:** This frameshift variant in BRCA1 is associated with
increased risk of breast and ovarian cancer. Recommend genetic counseling and
consideration of risk-reducing strategies.

---

### Variants of Uncertain Significance (VUS)

[None detected]

---

## Interpretation

A pathogenic variant in BRCA1 was identified, confirming the clinical suspicion
of hereditary breast and ovarian cancer syndrome (HBOC). The patient should be
referred to genetic counseling for discussion of cancer screening and prevention
options.

---

## Methods

- **Platform:** Illumina NovaSeq 6000
- **Coverage:** 150x mean depth (>20x for 99.5% of target)
- **Variant Caller:** GATK HaplotypeCaller v4.3.0
- **Reference:** GRCh38
- **Variant Interpretation:** ACMG guidelines (2015)

---

## Quality Metrics

- **Total Reads:** 245M
- **Mapped Reads:** 98.7%
- **On-Target Reads:** 92.3%
- **Mean Coverage:** 152x
- **>20x Coverage:** 99.6% of target

---

## Limitations

- This test does not detect large deletions/duplications (consider MLPA)
- Deep intronic variants not assessed
- Variants in GC-rich regions may be underrepresented

---

## Approved By

Dr. John Doe, PhD, FACMG
Clinical Laboratory Director
CLIA #: 123456

---

**Report Generated:** 2025-10-28 14:30:00
**BioMate Version:** 1.0.0 (CAP/CLIA Validated)
**Workflow ID:** wf_clinical_001
```

---

### 3. QC Summary Report

**Use Case:** Quick quality assessment for multiple samples

**Sections:**
- Sample overview table
- QC metrics summary
- Failed samples (if any)
- Pass/Fail criteria

**Example:**

```markdown
# QC Summary Report

**Project:** Batch 2025-10
**Samples:** 96
**Date:** 2025-10-28

---

## Summary

- **Passed:** 94 samples (97.9%)
- **Failed:** 2 samples (2.1%)

---

## QC Metrics

| Sample   | Reads | Q30 | Duplication | Alignment | Status |
|----------|-------|-----|-------------|-----------|--------|
| Sample01 | 45M   | 92% | 15%         | 88%       | PASS   |
| Sample02 | 38M   | 91% | 18%         | 85%       | PASS   |
| ...      | ...   | ... | ...         | ...       | ...    |
| Sample95 | 12M   | 78% | 45%         | 62%       | FAIL   |
| Sample96 | 9M    | 75% | 52%         | 58%       | FAIL   |

---

## Failed Samples

**Sample95:** Low read count (12M < 20M threshold), high duplication
**Sample96:** Low read count (9M < 20M threshold), poor alignment

**Recommendation:** Re-sequence Sample95 and Sample96.
```

---

## Template System

### Template Format (Handlebars + Markdown)

**Example Template: `rnaseq_report.hbs`**

```handlebars
# RNA-seq Analysis Report

## Executive Summary

**Project:** {{project.name}}
**Sample Count:** {{samples.length}} ({{controls.length}} control, {{treated.length}} treated)
**Date:** {{report.date}}
**Analyst:** BioMate AI

### Key Findings
- {{deg.total}} differentially expressed genes (FDR < {{parameters.fdr}})
- {{deg.upregulated}} upregulated, {{deg.downregulated}} downregulated
- Top enriched pathways: {{#each pathways}}{{this.name}}{{#unless @last}}, {{/unless}}{{/each}}

---

## Methods

### Workflow
{{#each workflow.steps}}
{{@index}}. {{this.name}}: {{this.tool}} v{{this.version}}
{{/each}}

### Parameters
- Minimum read count: {{parameters.minCount}}
- FDR threshold: {{parameters.fdr}}
- Log2 fold change: ±{{parameters.logFC}}

---

## Quality Control

### Sequencing Quality
- Mean Phred score: {{qc.meanPhred}}
- Adapter contamination: {{qc.adapterPct}}%
- Duplication rate: {{qc.duplicationPct}}%

### Alignment Statistics
- Uniquely mapped reads: {{qc.alignmentPct}}% (avg)
- Multi-mapped reads: {{qc.multiMappedPct}}%
- Unmapped reads: {{qc.unmappedPct}}%

![PCA Plot]({{figures.pca}})

---

## Results

### Differential Expression

**Table 1:** Top 10 differentially expressed genes

| Gene    | Log2FC | FDR      | Function                    |
|---------|--------|----------|-----------------------------|
{{#each deg.top10}}
| {{this.gene}} | {{this.log2fc}} | {{this.fdr}} | {{this.function}} |
{{/each}}

![Volcano Plot]({{figures.volcano}})
![Heatmap]({{figures.heatmap}})

### GO Enrichment Analysis

Top enriched biological processes:
{{#each pathways}}
- {{this.name}} (FDR: {{this.fdr}})
{{/each}}

---

## Discussion

{{discussion.summary}}

### Limitations
{{#each discussion.limitations}}
- {{this}}
{{/each}}

---

## References

{{#each citations}}
{{@index}}. {{this.formatted}}
{{/each}}

---

**Report Generated:** {{report.timestamp}}
**BioMate Version:** {{report.version}}
**Workflow ID:** {{workflow.id}}
```

---

### Custom Template Upload

**Requirements:**
- Handlebars syntax
- Markdown formatting
- Define expected data schema (JSON schema)

**Template Metadata:**

```json
{
  "id": "custom_rnaseq_v1",
  "name": "Custom RNA-seq Report",
  "description": "Lab-specific RNA-seq report format",
  "author": "user_123",
  "version": "1.0.0",
  "reportType": "rnaseq",
  "dataSchema": {
    "type": "object",
    "required": ["project", "samples", "deg", "qc"],
    "properties": {
      "project": {"type": "object", "properties": {...}},
      "samples": {"type": "array", "items": {...}},
      "deg": {"type": "object", "properties": {...}},
      "qc": {"type": "object", "properties": {...}}
    }
  },
  "createdAt": "2025-10-28T10:00:00Z"
}
```

---

## Data Extraction

### File Parsers

**Supported Output Files:**

| File Type | Parser | Extracted Data |
|-----------|--------|----------------|
| BAM/SAM | pysam | Alignment statistics |
| VCF | PyVCF | Variants, annotations |
| FASTQ | BioPython | Read counts, quality |
| CSV/TSV | Pandas | Tables (DEG, counts) |
| JSON | Native | Structured data |
| HTML | BeautifulSoup | Tool outputs (FastQC, MultiQC) |

**Example: Extract DEG Results**

```python
import pandas as pd

def extract_deseq2_results(results_file: str) -> dict:
    # Parse DESeq2 output CSV
    df = pd.read_csv(results_file)

    # Filter significant DEGs
    sig_df = df[df['padj'] < 0.05]

    return {
        'total': len(sig_df),
        'upregulated': len(sig_df[sig_df['log2FoldChange'] > 0]),
        'downregulated': len(sig_df[sig_df['log2FoldChange'] < 0]),
        'top10': sig_df.nsmallest(10, 'padj').to_dict('records'),
        'all': sig_df.to_dict('records'),
    }
```

---

### Metadata Extraction

**Workflow Metadata:**

```python
def extract_workflow_metadata(workflow_id: str) -> dict:
    workflow = db.workflows.findOne({'id': workflow_id})

    return {
        'id': workflow.id,
        'name': workflow.name,
        'steps': [
            {
                'name': step.name,
                'tool': step.tool,
                'version': step.version,
                'parameters': step.parameters,
            }
            for step in workflow.steps
        ],
        'executionTime': workflow.executionTime,
        'completedAt': workflow.completedAt,
    }
```

---

## Rendering Engine

### Markdown to HTML

**Using Marked.js + Syntax Highlighting:**

```typescript
import { marked } from 'marked';
import hljs from 'highlight.js';

marked.setOptions({
  highlight: function(code, lang) {
    if (lang && hljs.getLanguage(lang)) {
      return hljs.highlight(code, { language: lang }).value;
    }
    return code;
  },
});

function renderMarkdown(markdown: string): string {
  return marked(markdown);
}
```

---

### HTML to PDF

**Using WeasyPrint (Python):**

```python
from weasyprint import HTML, CSS

def generate_pdf(html_content: str, css_content: str, output_path: str):
    html = HTML(string=html_content)
    css = CSS(string=css_content)

    html.write_pdf(output_path, stylesheets=[css])
```

**CSS for Professional Reports:**

```css
/* report-styles.css */
@page {
  size: letter;
  margin: 1in;
  @top-center {
    content: "BioMate Analysis Report";
  }
  @bottom-right {
    content: "Page " counter(page) " of " counter(pages);
  }
}

body {
  font-family: 'Helvetica', 'Arial', sans-serif;
  font-size: 11pt;
  line-height: 1.6;
  color: #333;
}

h1 {
  font-size: 24pt;
  color: #0066cc;
  page-break-before: always;
}

h2 {
  font-size: 18pt;
  color: #0066cc;
  border-bottom: 2px solid #0066cc;
  padding-bottom: 5pt;
  margin-top: 20pt;
}

table {
  border-collapse: collapse;
  width: 100%;
  margin: 15pt 0;
}

th {
  background-color: #0066cc;
  color: white;
  padding: 8pt;
  text-align: left;
}

td {
  border: 1px solid #ddd;
  padding: 6pt;
}

img {
  max-width: 100%;
  page-break-inside: avoid;
}

code {
  background-color: #f4f4f4;
  padding: 2pt 4pt;
  border-radius: 3pt;
  font-family: 'Courier New', monospace;
}

.page-break {
  page-break-after: always;
}
```

---

### HTML to DOCX

**Using Pandoc:**

```bash
pandoc report.html -o report.docx \
  --reference-doc=template.docx \
  --standalone \
  --citeproc
```

---

## Citation Management

### Citation Collection

**Automatic Tool Citations:**

```python
def collect_citations(workflow: Workflow) -> List[Citation]:
    citations = []

    for step in workflow.steps:
        tool = db.tools.findOne({'id': step.toolId})

        # Extract citations from tool metadata
        for cite in tool.citations:
            citations.append({
                'doi': cite.doi,
                'title': cite.title,
                'authors': cite.authors,
                'year': cite.year,
                'journal': cite.journal,
                'pmid': cite.pmid,
            })

    return deduplicate(citations)
```

---

### Bibliography Generation

**Using Citation Style Language (CSL):**

```python
from citeproc import CitationStylesStyle, CitationStylesBibliography
from citeproc.source.json import CiteProcJSON

def generate_bibliography(citations: List[dict], style: str = 'nature') -> str:
    # Load CSL style
    style = CitationStylesStyle(f'styles/{style}.csl')

    # Create bibliography
    bib = CitationStylesBibliography(style, CiteProcJSON(citations))

    # Format citations
    for cite in citations:
        bib.register(cite)

    # Render
    return '\n'.join([str(item) for item in bib.bibliography()])
```

**Supported Citation Styles:**
- Nature
- Science
- Cell
- PLoS
- APA
- Harvard
- Vancouver

---

## Export Formats

### 1. PDF (Primary)

**Features:**
- High-quality figures (300 DPI)
- Professional styling
- Page headers/footers
- Table of contents
- Bookmarks

**Use Case:** Final reports, publication supplements

---

### 2. Interactive HTML

**Features:**
- Embedded interactive plots (Plotly)
- Collapsible sections
- Searchable content
- Responsive design

**Use Case:** Online sharing, presentations

---

### 3. Microsoft Word (DOCX)

**Features:**
- Editable text and tables
- Embedded figures
- Styles preserved

**Use Case:** Collaborative editing, customization

---

### 4. LaTeX (Advanced)

**Features:**
- High-quality typesetting
- Advanced math equations
- Custom formatting

**Use Case:** Publication submission (journals requiring LaTeX)

---

## API Design

```typescript
// Generate report
POST /api/reports/generate
Body: {
  workflowId: "wf_abc123",
  templateId: "rnaseq_report",  // or "custom_template_xyz"
  format: "pdf",  // pdf, html, docx, latex
  options: {
    includeFigures: true,
    includeTables: true,
    citationStyle: "nature",
    customSections: {
      discussion: "Custom discussion text...",
    },
  },
}

Response: {
  reportId: "report_123",
  status: "generating",
  estimatedTime: 60,  // seconds
}

// Check report status
GET /api/reports/{reportId}/status
Response: {
  reportId: "report_123",
  status: "completed",  // generating, completed, failed
  downloadUrl: "https://biomate-reports.s3.amazonaws.com/...",
  expiresAt: "2025-11-28T10:00:00Z",  // 30 days
}

// List reports for workflow
GET /api/reports?workflowId=wf_abc123

// Get report metadata
GET /api/reports/{reportId}

// Delete report
DELETE /api/reports/{reportId}

// Upload custom template
POST /api/templates/upload
Body: (multipart/form-data)
  - template: (file, .hbs)
  - metadata: (JSON)

// List templates
GET /api/templates?type=rnaseq
```

---

## Implementation Plan

### Phase 1: Core Engine (Weeks 1-2)

**Week 1:**
- [ ] Set up Handlebars template engine
- [ ] Implement basic data extraction (DESeq2, FastQC)
- [ ] Markdown to HTML rendering
- [ ] PDF generation (WeasyPrint)

**Week 2:**
- [ ] Create RNA-seq report template
- [ ] Create variant calling report template
- [ ] Create QC summary template
- [ ] Testing with sample data

**Deliverable:** 3 basic report templates working (PDF output)

---

### Phase 2: Advanced Features (Weeks 3-4)

**Week 3:**
- [ ] Citation management system
- [ ] Bibliography generation (CSL)
- [ ] Interactive HTML reports (Plotly)
- [ ] DOCX export (Pandoc)

**Week 4:**
- [ ] Custom template upload
- [ ] Template validation
- [ ] Report storage (S3)
- [ ] API implementation

**Deliverable:** Full report system with custom templates

---

### Phase 3: Clinical & Compliance (Weeks 5-6)

**Week 5:**
- [ ] Clinical variant report template (CAP/CLIA)
- [ ] Audit trail for clinical reports
- [ ] Digital signatures (e-signature)
- [ ] Report versioning

**Week 6:**
- [ ] Report gallery UI
- [ ] Batch report generation
- [ ] Email delivery
- [ ] Production deployment

**Deliverable:** Clinical-grade reporting system

---

## Success Metrics

### Launch (Week 2)
- ✅ 3 report templates available
- ✅ PDF generation working
- ✅ <60 seconds report generation time
- ✅ 100% of pilot users generate at least one report

### Month 1
- ✅ 5+ report templates
- ✅ Custom template upload working
- ✅ Interactive HTML reports
- ✅ 80%+ user satisfaction

### Month 2
- ✅ Clinical variant report (CAP/CLIA)
- ✅ 10+ templates in library
- ✅ 50+ reports generated/week
- ✅ <30 seconds generation time

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Next Review:** Before Phase 1 implementation
**Owner:** BioMate Reporting Team
