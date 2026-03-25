"""
Regenerate BioMate drug discovery docx files from updated markdown content.
"""

from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import copy

# ── helpers ──────────────────────────────────────────────────────────────────

BRAND_BLUE  = RGBColor(0x1A, 0x56, 0xDB)   # #1A56DB
DARK_GRAY   = RGBColor(0x1F, 0x29, 0x37)   # #1F2937
MID_GRAY    = RGBColor(0x6B, 0x72, 0x80)   # #6B7280
LIGHT_GRAY  = RGBColor(0xF9, 0xFA, 0xFB)   # table header bg
WHITE       = RGBColor(0xFF, 0xFF, 0xFF)
RULE_GRAY   = RGBColor(0xD1, 0xD5, 0xDB)

def set_cell_bg(cell, rgb: RGBColor):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    hex_color = str(rgb)   # RGBColor.__str__ returns 'RRGGBB'
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), hex_color)
    tcPr.append(shd)

def set_cell_border(cell, **kwargs):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcBorders = OxmlElement('w:tcBorders')
    for side in ('top', 'left', 'bottom', 'right'):
        tag = OxmlElement(f'w:{side}')
        tag.set(qn('w:val'), 'single')
        tag.set(qn('w:sz'), '4')
        tag.set(qn('w:color'), 'D1D5DB')
        tcBorders.append(tag)
    tcPr.append(tcBorders)

def add_horizontal_rule(doc):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after  = Pt(6)
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement('w:pBdr')
    bottom = OxmlElement('w:bottom')
    bottom.set(qn('w:val'), 'single')
    bottom.set(qn('w:sz'), '6')
    bottom.set(qn('w:color'), 'D1D5DB')
    pBdr.append(bottom)
    pPr.append(pBdr)
    return p

def base_doc():
    doc = Document()
    # margins
    for section in doc.sections:
        section.top_margin    = Cm(2.5)
        section.bottom_margin = Cm(2.5)
        section.left_margin   = Cm(3.0)
        section.right_margin  = Cm(3.0)

    # Normal style
    normal = doc.styles['Normal']
    normal.font.name = 'Calibri'
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = DARK_GRAY

    # Heading 1
    h1 = doc.styles['Heading 1']
    h1.font.name  = 'Calibri'
    h1.font.size  = Pt(20)
    h1.font.bold  = True
    h1.font.color.rgb = BRAND_BLUE
    h1.paragraph_format.space_before = Pt(0)
    h1.paragraph_format.space_after  = Pt(4)

    # Heading 2
    h2 = doc.styles['Heading 2']
    h2.font.name  = 'Calibri'
    h2.font.size  = Pt(13)
    h2.font.bold  = True
    h2.font.color.rgb = DARK_GRAY
    h2.paragraph_format.space_before = Pt(18)
    h2.paragraph_format.space_after  = Pt(4)

    # Heading 3
    h3 = doc.styles['Heading 3']
    h3.font.name  = 'Calibri'
    h3.font.size  = Pt(11)
    h3.font.bold  = True
    h3.font.color.rgb = BRAND_BLUE
    h3.paragraph_format.space_before = Pt(12)
    h3.paragraph_format.space_after  = Pt(2)

    return doc


def add_meta_line(doc, text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name  = 'Calibri'
    run.font.size  = Pt(10)
    run.font.color.rgb = MID_GRAY
    run.font.italic = True
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after  = Pt(2)
    return p


def add_body(doc, text, space_after=Pt(8)):
    p = doc.add_paragraph(text)
    p.paragraph_format.space_after = space_after
    return p


def add_bold_intro(doc, bold_part, rest):
    """Add a paragraph with a bold lead-in followed by normal text."""
    p = doc.add_paragraph()
    run_b = p.add_run(bold_part)
    run_b.bold = True
    run_b.font.color.rgb = DARK_GRAY
    run_n = p.add_run(rest)
    run_n.font.color.rgb = DARK_GRAY
    p.paragraph_format.space_after = Pt(7)
    return p


def add_italic(doc, text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.italic = True
    run.font.color.rgb = MID_GRAY
    p.paragraph_format.space_after = Pt(6)
    return p


def add_code_block(doc, lines):
    for line in lines:
        p = doc.add_paragraph()
        run = p.add_run(line)
        run.font.name = 'Courier New'
        run.font.size = Pt(9)
        run.font.color.rgb = RGBColor(0x1E, 0x40, 0xAF)
        p.paragraph_format.left_indent   = Cm(0.8)
        p.paragraph_format.space_before  = Pt(1)
        p.paragraph_format.space_after   = Pt(1)
        # light blue background
        pPr = p._p.get_or_add_pPr()
        shd = OxmlElement('w:shd')
        shd.set(qn('w:val'), 'clear')
        shd.set(qn('w:color'), 'auto')
        shd.set(qn('w:fill'), 'EFF6FF')
        pPr.append(shd)


def add_table(doc, headers, rows, col_widths=None):
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.LEFT

    # header row
    hdr = table.rows[0]
    for i, h in enumerate(headers):
        cell = hdr.cells[i]
        set_cell_bg(cell, BRAND_BLUE)
        set_cell_border(cell)
        p = cell.paragraphs[0]
        run = p.add_run(h)
        run.bold = True
        run.font.color.rgb = WHITE
        run.font.size = Pt(10)
        p.paragraph_format.space_before = Pt(3)
        p.paragraph_format.space_after  = Pt(3)

    # data rows
    for r_idx, row_data in enumerate(rows):
        row = table.rows[r_idx + 1]
        bg = RGBColor(0xF9, 0xFA, 0xFB) if r_idx % 2 == 0 else WHITE
        for c_idx, cell_text in enumerate(row_data):
            cell = row.cells[c_idx]
            set_cell_bg(cell, bg)
            set_cell_border(cell)
            p = cell.paragraphs[0]
            # handle bold markers **...**
            parts = cell_text.split('**')
            for k, part in enumerate(parts):
                run = p.add_run(part)
                run.bold = (k % 2 == 1)
                run.font.size = Pt(10)
            p.paragraph_format.space_before = Pt(3)
            p.paragraph_format.space_after  = Pt(3)

    # column widths
    if col_widths:
        for i, w in enumerate(col_widths):
            for row in table.rows:
                row.cells[i].width = Cm(w)

    doc.add_paragraph()  # spacer


def add_numbered_list(doc, items):
    for item in items:
        p = doc.add_paragraph(style='List Number')
        # handle bold lead-in
        if item.startswith('**'):
            end = item.index('**', 2)
            bold_part = item[2:end]
            rest = item[end+2:]
            run_b = p.add_run(bold_part)
            run_b.bold = True
            p.add_run(rest)
        else:
            p.add_run(item)
        p.paragraph_format.space_after = Pt(5)


def add_bullet_list(doc, items):
    for item in items:
        p = doc.add_paragraph(style='List Bullet')
        if '**' in item:
            parts = item.split('**')
            for k, part in enumerate(parts):
                run = p.add_run(part)
                run.bold = (k % 2 == 1)
        else:
            p.add_run(item)
        p.paragraph_format.space_after = Pt(4)


# ══════════════════════════════════════════════════════════════════════════════
#  DOCUMENT 1 — Introduction
# ══════════════════════════════════════════════════════════════════════════════

def build_introduction():
    doc = base_doc()

    # Title block
    p = doc.add_heading('BioMate for Clinical Drug Discovery Research', level=1)
    add_meta_line(doc, 'A Platform Overview for the Department of Medicine — Zhejiang People\'s Hospital')
    add_meta_line(doc, 'March 2026  ·  BioMate AI  ·  Research collaboration overview')
    add_horizontal_rule(doc)

    # Executive Summary
    doc.add_heading('Executive Summary', level=2)
    add_body(doc,
        'BioMate is an AI-native drug discovery platform designed to work alongside clinicians and '
        'physician-scientists. A researcher describes the task — screen candidate compounds for a specific '
        'target, evaluate which drugs from an existing regimen are best tolerated by a patient population, '
        'or identify new therapeutic candidates for a disease of interest — and BioMate runs the full '
        'computational pipeline, applies clinical-grade quality checks, and returns results with a complete '
        'audit trail, all within one session.')
    add_body(doc,
        'The platform does not require a bioinformatics background. It speaks the language of the science, '
        'not the command line. For a department whose primary work is patient care and clinical research '
        'rather than software engineering, BioMate is the bridge between cutting-edge computational chemistry '
        'and the clinical question at hand.')
    add_body(doc,
        'The pipeline covers target identification through literature and database mining, ADMET toxicity and '
        'pharmacokinetics profiling, virtual screening and compound ranking, and iterative lead optimisation '
        'guided by assay data. Every result is accompanied by an exportable methods report and a complete '
        'quality audit log — ready for a research manuscript or an internal review committee.')
    add_horizontal_rule(doc)

    # What BioMate Does
    doc.add_heading('What BioMate Does', level=2)

    capabilities = [
        ('Natural language pipeline execution. ',
         'Describe the scientific question; BioMate runs the pipeline. Tool selection, parameter configuration, '
         'environment management, and result organisation are handled automatically. A clinical researcher does '
         'not need to know which docking engine, which ADMET predictor, or which molecular dynamics package to '
         'use — BioMate selects and configures these based on the question and the target.'),
        ('Target identification from clinical evidence. ',
         'Starting from a disease of interest, a gene, or a published clinical finding, BioMate surveys '
         'biomedical literature, protein databases, and drug-target interaction networks to identify and '
         'prioritise candidate targets. For targets where structural data exists, it maps the binding site and '
         'assesses druggability. For novel targets, AlphaFold3 structure prediction is applied automatically.'),
        ('ADMET profiling — the clinical safety screen. ',
         'Before any compound advances in a campaign, BioMate evaluates its toxicological and '
         'pharmacokinetic profile against a full panel of endpoints: cardiac liability (hERG), liver toxicity '
         '(DILI), mutagenicity (Ames), clinical toxicology flags (ClinTox), intestinal permeability (Caco-2), '
         'and blood-brain barrier penetration. Thresholds are grounded in published clinical guidelines and '
         'labelled by evidence tier. When a compound fails, BioMate explains which metric failed, what the '
         'measured value was, and what the guideline threshold is — and asks whether to proceed.'),
        ('Virtual screening and compound ranking. ',
         'Compound libraries are pre-filtered by physicochemical properties and pharmacophore rules before '
         'docking, eliminating obviously unsuitable candidates before expensive computation. Docking runs '
         'AutoDock Vina and DiffDock in parallel. Results are merged with ADMET scores into an integrated '
         'compound ranking. The top candidates are returned with a rationale for their ranking.'),
        ('Generative lead design and analogue suggestion. ',
         'Starting from a hit compound, BioMate generates analogues constrained to improved property ranges — '
         'for example, reducing cardiac liability while preserving binding affinity. It predicts retrosynthesis '
         'routes with AiZynthFinder to ensure proposed compounds can actually be synthesised, and flags '
         'compounds with impractical routes before they reach the ordering decision.'),
        ('Drug MoA characterisation from clinical RNA-seq. ',
         'For departments with access to patient RNA-seq data from drug-treated samples, BioMate can '
         'characterise how a drug perturbs gene expression: differential expression analysis, pathway '
         'enrichment, and LINCS CMap matching to identify which known drugs produce a similar transcriptomic '
         'signature. This supports mechanism-of-action hypotheses and drug repurposing investigations.'),
        ('Iterative optimisation with assay data. ',
         'When wet lab or CRO assay results return, they are uploaded to BioMate in a structured CSV. BioMate '
         'updates the compound ranking and runs multi-objective Bayesian optimisation to propose the next '
         'synthesis batch — balancing potency, selectivity, and ADMET profile in a Pareto-optimal design. '
         'Each round is informed by all accumulated experimental evidence.'),
        ('CRO-ready compound export. ',
         'The proposed compound set is exportable directly in formats accepted by major contract research '
         'organisations (WuXi AppTec, Pharmaron, Enamine), with per-compound scientific rationale, ADMET '
         'pre-filter results, and commercial availability checks. The step from BioMate output to a synthesis '
         'order is a single export.'),
        ('Complete audit trail and methods report. ',
         'Every session produces a timestamped audit log: tools used, parameters set, QC outcomes, and any '
         'analyst override decisions. This log is auto-formatted as a computational methods section — ready '
         'to include in a research manuscript without manual write-up.'),
    ]
    for bold, rest in capabilities:
        add_bold_intro(doc, bold, rest)

    add_horizontal_rule(doc)

    # Discovery Pipeline Coverage
    doc.add_heading('Discovery Pipeline Coverage', level=2)

    sections = [
        ('Target Identification and Characterisation',
         'BioMate combines literature synthesis (PubMed, bioRxiv, clinical trial registries), drug-target '
         'interaction networks (DrugBank, ChEMBL, DGIdb), and AI-based target prioritisation to surface '
         'candidates relevant to a specific disease or patient population. For targets with existing structural '
         'data, pocket detection and druggability assessment run automatically. For novel targets, AlphaFold3 '
         'structure prediction is applied and the AlphaFold Human Proteome database is searched for '
         'structural relatives.'),
        ('ADMET Filtering and Compound Triage',
         'ADMET profiling runs on every compound before computationally expensive docking steps, eliminating '
         'candidates with unacceptable toxicity or pharmacokinetics early. The panel covers cardiac, hepatic, '
         'mutagenic, and clinical toxicology endpoints, plus permeability and CNS penetration where relevant. '
         'Compounds that fail are clearly labelled with the failing metric, the evidence source, and the '
         'threshold — not just a pass/fail flag.'),
        ('Virtual Screening and Hit Identification',
         'For compound libraries of 10 to several thousand compounds, BioMate performs pharmacophore '
         'pre-filtering, similarity-based pre-screen, and multi-engine docking (Vina + DiffDock), returning '
         'an integrated ranked list. ADMET gate results and docking scores are combined into a single compound '
         'view. Top hits are returned with poses and ranking rationale.'),
        ('Lead Optimisation',
         'REINVENT4 generative design and matched molecular pair analysis drive analogue generation. '
         'AiZynthFinder retrosynthesis route prediction screens out compounds with impractical synthesis paths. '
         'Binding free energy calculations with GROMACS MM-GBSA re-rank the shortlist before synthesis '
         'decisions. Off-target selectivity can be evaluated by running anti-target rescoring against '
         'homologous structures.'),
        ('Iterative Campaigns and MoA Characterisation',
         'Assay results from the lab or a CRO are ingested, mapped to campaign compounds, and used to update '
         'the multi-objective Bayesian optimisation model. For mechanistic questions — how does a drug '
         'candidate alter cell biology — the drug MoA pipeline produces a differential expression and pathway '
         'enrichment report from patient RNA-seq data and cross-references LINCS CMap for mechanism hypothesis '
         'generation.'),
    ]
    for title, body in sections:
        doc.add_heading(title, level=3)
        add_body(doc, body)

    add_horizontal_rule(doc)

    # Quality and Reproducibility
    doc.add_heading('Quality and Reproducibility', level=2)
    add_body(doc,
        'BioMate applies evidence-graded QC at each pipeline stage. Named profiles cover standard oral small '
        'molecules, CNS-penetrant compounds, fragment-based campaigns, and oncology series. Custom profiles '
        'can be defined for a specific disease area or patient population.')
    add_body(doc,
        'Every run produces a complete audit log ready to serve as the computational methods section of a '
        'research paper. All QC thresholds are cited to their source — ICH S7B (hERG cardiac liability), '
        'FDA/EMA DILI guidance, Lipinski and Veber physicochemical rules, ChEMBL benchmark distributions, '
        'or published clinical guidelines — so a reviewing editor or committee can verify the evidence behind '
        'each quality decision.')
    add_horizontal_rule(doc)

    # Pilot Evaluation Framework
    doc.add_heading('Pilot Evaluation Framework', level=2)
    add_body(doc, 'For the initial collaboration, the evaluation is structured around four measurable outcomes:')

    add_table(doc,
        headers=['Metric', 'Target', 'Measurement'],
        rows=[
            ['Workflow quality (H1)',
             '≥ 80% of queries run end-to-end without manual parameter correction',
             'Platform telemetry + post-run survey'],
            ['Time-to-result (H2)',
             'Query submission to complete result in ≤ 30 minutes for a 10–20 compound screen',
             'Backend timestamp log'],
            ['QC defensibility (H3)',
             '≥ 70% of results rated publication-ready (score 4–5 / 5)',
             'Researcher exit survey'],
            ['Hallucination incidents (H5)',
             '0 — every command maps to a real installed tool',
             'Exit survey + backend monitoring'],
        ],
        col_widths=[4.5, 7.5, 5.0]
    )

    add_body(doc,
        'The deliverable at the end of the pilot is a QC audit log and an exportable methods report for the '
        'compounds analysed — ready for direct inclusion in a manuscript or internal research record.')
    add_horizontal_rule(doc)

    # Discussion questions
    doc.add_heading('What We Would Like to Understand From You', level=2)
    questions = [
        'What is the current focus of your department\'s drug-related research — identifying new therapeutic '
        'targets, evaluating approved drugs for new indications, or optimising lead compounds for a specific disease?',
        'For a recent clinical project involving a drug or compound series, how was the computational analysis '
        'handled — internally, through a bioinformatics core, or outsourced? What was the biggest bottleneck?',
        'Do you have patient cohort data (RNA-seq, proteomics, or clinical outcomes) that could be used to '
        'profile drug mechanism of action or identify response predictors? What would it take to make that '
        'data available for computational analysis?',
        'When your department evaluates a drug candidate for clinical relevance — cardiac safety, liver toxicity, '
        'metabolic stability — what tools or databases are currently used, and who is responsible for that evaluation?',
        'Is there a specific disease target, compound set, or clinical hypothesis that you would want to run '
        'through BioMate in an initial session — so you can compare BioMate\'s output directly against what '
        'you already know?',
        'What would need to be true — in terms of result quality, explanation clarity, and audit documentation '
        '— for BioMate to become a routine part of your department\'s research workflow?',
    ]
    add_numbered_list(doc, questions)
    add_horizontal_rule(doc)

    # Appendix
    doc.add_heading('Appendix — Example Queries', level=2)
    add_body(doc, 'These illustrate how researchers interact with BioMate. Replace bracketed values with your own parameters.')

    examples = [
        ('Target survey for a specific disease',
         ['I am working on [gastric adenocarcinoma]. Survey the published literature',
          'and drug-target databases for candidate therapeutic targets: what proteins',
          'are most frequently implicated, which have known inhibitors, and which',
          'targets have published structural data for docking?']),
        ('ADMET evaluation of a compound set',
         ['I have 12 candidate compounds [SMILES list] that we are considering for',
          'a [KRAS-mutant colorectal cancer] programme. Evaluate all 12 for ADMET:',
          'flag any with cardiac liability (hERG IC50 < 10 uM), high DILI risk,',
          'or mutagenicity risk. Return a ranked table and show me which passed all gates.']),
        ('Drug repurposing from patient RNA-seq',
         ['I have bulk RNA-seq from [15 hepatocellular carcinoma patients treated with',
          'sorafenib] and [15 untreated controls]. Run differential expression with',
          'DESeq2, identify significantly dysregulated pathways, and search LINCS CMap',
          'to identify approved drugs that produce a similar transcriptomic signature —',
          'potential candidates for combination or repurposing.']),
        ('Virtual screening on a clinical target',
         ['I have a target protein [UniProt ID or PDB ID] implicated in [disease].',
          'Screen these [50] candidate small molecules against it: first apply ADMET',
          'filtering, then dock the passing compounds with AutoDock Vina, and return',
          'the top 10 ranked by integrated score. Include the docking pose for each.']),
        ('Lead optimisation from a flagged compound',
         ['I have a lead compound [SMILES] with good target binding but a hERG IC50',
          'of 3 uM. Generate 20 analogues that improve cardiac safety while keeping',
          'the core pharmacophore intact. Score each for synthetic accessibility and',
          'flag any with impractical retrosynthesis routes.']),
        ('Assay data upload and next-round proposal',
         ['I received IC50 data from the CRO for the 15 compounds from our last',
          'round [CSV attached]. Update the campaign ranking and propose the next',
          '10 compounds for synthesis — optimised for potency, hERG safety, and',
          'metabolic stability simultaneously.']),
    ]
    for title, code_lines in examples:
        doc.add_heading(title, level=3)
        add_code_block(doc, code_lines)

    doc.save('/home/yzhang/biomate/business/BioMate_DrugDiscovery_Introduction.docx')
    print('✓ BioMate_DrugDiscovery_Introduction.docx saved')


# ══════════════════════════════════════════════════════════════════════════════
#  DOCUMENT 2 — Study Proposal
# ══════════════════════════════════════════════════════════════════════════════

def build_study_proposal():
    doc = base_doc()

    # Title block
    doc.add_heading('Pilot Study Proposal', level=1)
    p = doc.add_heading('Evaluating AI-Native Computational Drug Discovery in a Clinical Medicine Setting', level=2)
    p.runs[0].font.color.rgb = MID_GRAY
    p.runs[0].font.size = Pt(12)

    meta = [
        ('Proposing parties: ', 'BioMate AI · Department of Medicine, Zhejiang People\'s Hospital'),
        ('Pilot window: ',      'March 30 – April 8, 2026 (10 days, range 7–14)'),
        ('Scope: ',             '10–20 compounds, one active therapeutic target'),
        ('Compute cost to partner: ', '$0'),
    ]
    for bold, rest in meta:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(2)
        rb = p.add_run(bold)
        rb.bold = True
        rb.font.size = Pt(10.5)
        rn = p.add_run(rest)
        rn.font.size = Pt(10.5)

    add_italic(doc, 'March 2026 · Draft for discussion')
    add_horizontal_rule(doc)

    # Executive Summary
    doc.add_heading('Executive Summary', level=2)
    add_body(doc,
        'BioMate is an AI-native drug discovery platform. A researcher describes a task — screen this compound '
        'set against a target, evaluate cardiac and liver safety, propose optimised analogues — and BioMate '
        'runs the full computational pipeline and returns results with a complete quality audit trail, in a '
        'single session.')
    add_body(doc,
        'This pilot evaluates whether BioMate can operate as a reliable computational research partner for a '
        'clinical medicine department: delivering correct, well-documented results without requiring '
        'bioinformatics expertise from the research team, and doing so fast enough to fit into a '
        'clinician-researcher\'s working day.')
    add_body(doc,
        'The pilot runs for 10 days (range 7–14) on 10–20 real compounds from an active or recently '
        'completed project at the Department of Medicine. Three hypotheses are tested. The deliverable is a '
        'QC audit log and an exportable methods report — ready for inclusion in a research record or manuscript.')
    add_horizontal_rule(doc)

    # Background
    doc.add_heading('Background', level=2)
    add_body(doc,
        'Computational drug discovery has become essential to translational medicine. ADMET profiling, virtual '
        'screening, and lead optimisation can now be run on commodity cloud infrastructure using open-source '
        'tools. The remaining barrier for clinical research departments is not capability — it is access: the '
        'workflows require bioinformatics expertise and pipeline infrastructure that most medical departments '
        'do not have in-house.')
    add_body(doc,
        'BioMate removes that barrier. The platform orchestrates the computational pipeline automatically — '
        'tool selection, parameter configuration, quality gating, and result formatting — in response to plain '
        'language from the researcher. A physician-scientist can describe a therapeutic question and receive a '
        'structured, auditable computational result without writing a line of code.')
    add_body(doc, 'This pilot tests whether that promise holds in practice for a real Department of Medicine use case.')
    add_horizontal_rule(doc)

    # Hypotheses
    doc.add_heading('Hypotheses', level=2)
    add_body(doc, 'The pilot is designed to produce a clear answer on three falsifiable claims:')

    hypotheses = [
        ('H1 — Workflow quality.  ',
         'At least 80% of the compound analysis queries submitted during the pilot produce a complete, correct '
         'result without requiring manual parameter correction or re-submission.',
         'Measurement:  Platform telemetry tracking queries that complete without intervention versus queries '
         'that require correction. Denominator is all queries submitted during the pilot window.'),
        ('H2 — Time-to-result.  ',
         'The average time from query submission to a complete, review-ready result is 30 minutes or less for '
         'a 10–20 compound ADMET + docking screen.',
         'Measurement:  Backend timestamp from query submission to result delivery. Compared against the '
         'department\'s estimate of how long the equivalent analysis currently takes by any existing method.'),
        ('H3 — QC defensibility.  ',
         'At least 70% of results returned during the pilot are rated by the research team as scientifically '
         'defensible — meaning the quality thresholds applied are appropriate for a research manuscript and '
         'the audit trail is sufficient for a methods section.',
         'Measurement:  Researcher rating on a structured exit form completed at the end of the pilot. '
         'Five-point scale per session; defensible is defined as rating 4 or 5 ("publication-ready" or '
         '"publication-ready with minor edits").'),
    ]
    for bold, body, measurement in hypotheses:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(2)
        rb = p.add_run(bold)
        rb.bold = True
        p.add_run(body)
        add_italic(doc, measurement)

    add_horizontal_rule(doc)

    # Pilot Scope
    doc.add_heading('Pilot Scope and Dataset', level=2)
    add_bold_intro(doc, 'Target:  ',
        'One protein with a published structure or high-confidence AlphaFold model from a current or recently '
        'active project at the Department. A defined binding site and one reference compound for docking '
        'validation are sufficient to begin.')
    add_bold_intro(doc, 'Compound library:  ', '10–20 small molecules. These can be:')
    add_bullet_list(doc, [
        'Compounds the department has previously tested, with known activity or toxicity data available as a ground truth',
        'Approved drugs being evaluated for repurposing against the target',
        'Candidate compounds from an ongoing discovery programme',
    ])
    add_bold_intro(doc, 'Reference data:  ',
        'If available, any existing docking, ADMET, or assay results for these compounds — used to compare '
        'BioMate\'s output against the department\'s existing analysis, not as a requirement to participate.')
    add_horizontal_rule(doc)

    # Study Design
    doc.add_heading('Study Design', level=2)
    add_body(doc,
        'The pilot runs across three structured arms over 21 days. Each arm maps directly to one hypothesis '
        'and one KPI in the evaluation framework.')

    arms = [
        ('Arm 1 — Workflow Quality (Days 1–6)',
         [('What happens. ',
           'The research team submits queries covering the full pipeline: ADMET profiling of the compound set, '
           'docking against the target, and integrated ranking. Target: 5–8 sessions across Days 1–6 (one or '
           'two sessions per day, each ≤ 30 minutes). Sessions are conducted by the researchers themselves — '
           'not by BioMate engineers — to test real-world usability.'),
          ('What is measured. ',
           'For each query: did it complete without manual correction? If not, what type of correction was '
           'required (parameter error, tool failure, format issue, or ambiguous input)? Results are logged automatically.'),
          ('Success criterion. ',
           '≥ 80% of queries complete without manual correction (H1 threshold).'),
          ('Zero hallucination standard. ',
           'BioMate must not issue commands for non-existent tools or use parameters with no valid values. '
           'This is a hard gate: any hallucinated command counts as a failure regardless of whether it was '
           'caught before execution. Target: 0 incidents.')]),
        ('Arm 2 — Time-to-Result (Days 1–6, concurrent with Arm 1)',
         [('What happens. ',
           'Every Arm 1 session automatically generates an Arm 2 data point — no separate sessions required. '
           'The time from query submission to result delivery is recorded for each run. At the end of Day 6, '
           'the research team provides a single estimate of how long the equivalent analysis would have taken '
           'by their existing process (manual search, outsourced core facility, or no prior process).'),
          ('What is measured. ',
           'Backend timestamp delta per session; self-reported baseline time from the research team.'),
          ('Success criterion. ',
           'Average time-to-result ≤ 30 minutes for a 10–20 compound ADMET + docking screen (H2 threshold).')]),
        ('Arm 3 — QC Defensibility (Days 4–9, overlapping Arms 1 and 2)',
         [('What happens. ',
           'From Day 4, results from Arms 1 and 2 are available for review as they are completed — no waiting '
           'for all sessions to finish. The research team reviews QC audit logs, quality gate decisions, and '
           'auto-generated methods reports as they accumulate, rating each on a five-point scale. The exit '
           'survey is completed on Day 9 to capture overall ratings across all sessions.\n\nWhere existing '
           'results are available for the same compounds, the research team compares BioMate\'s rankings '
           'against them and identifies where they agree, diverge, and whether any divergence would have '
           'changed an advancement decision.'),
          ('What is measured. ',
           'Exit form ratings (five-point scale, per session). Concordance between BioMate rankings and '
           'existing results where ground truth is available.'),
          ('Success criterion. ',
           '≥ 70% of sessions rated 4 or 5 on defensibility (H3 threshold).')]),
    ]
    for arm_title, points in arms:
        doc.add_heading(arm_title, level=3)
        for bold, text in points:
            add_bold_intro(doc, bold, text)

    add_horizontal_rule(doc)

    # Division of Labor
    doc.add_heading('Division of Labor', level=2)
    add_table(doc,
        headers=['Task', 'Department', 'BioMate'],
        rows=[
            ['Target structure and compound set (10–20 compounds)', '✓', ''],
            ['Existing results for comparison (optional)',           '✓', ''],
            ['Researcher time for query submission (≤ 2 hrs/week)', '✓', ''],
            ['Exit form completion at pilot end',                    '✓', ''],
            ['Platform execution and cloud infrastructure',          '',  '✓'],
            ['QC audit log and methods report generation',           '',  '✓'],
            ['Compute costs',                                        '',  '✓'],
            ['Data governance (platform Terms of Service via registration)', '', '✓'],
        ],
        col_widths=[10.5, 2.5, 2.5]
    )

    doc.add_heading('Pre-pilot commitments (BioMate, by April 5):', level=3)
    add_bullet_list(doc, [
        'Platform configured with the department\'s target and compound set',
        'ADMET profile set for the relevant disease area',
        'QC audit log export and methods report format confirmed with the research team',
    ])

    doc.add_heading('Pre-pilot commitments (Department, by April 5):', level=3)
    add_bullet_list(doc, [
        'Pilot account registered on BioMate platform (user agreement completed at registration)',
        'Target structure and compound SMILES (10–20 compounds) shared via secure upload',
        'Designated point of contact for query submission and exit form',
    ])
    add_horizontal_rule(doc)

    # Timeline
    doc.add_heading('Timeline', level=2)
    add_table(doc,
        headers=['Phase', 'Days', 'Dates', 'Activities'],
        rows=[
            ['**Pre-pilot setup**', '−5 to 0', 'March 25 – 29',
             'Account registered; target + compounds shared; ADMET profile configured'],
            ['**Arm 1 + Arm 2**',  'Days 1–6', 'March 30 – April 4',
             'Workflow quality sessions + time-to-result logging; 5–8 runs; researchers self-directed'],
            ['**Arm 3**',          'Days 4–9', 'April 2 – 7',
             'QC review of completed sessions; exit survey; concordance analysis where ground truth is available'],
            ['**Debrief**',        'Day 10', 'April 8',
             'Results summary; go/no-go for full collaboration; next steps'],
        ],
        col_widths=[3.5, 2.0, 2.5, 8.5]
    )
    add_body(doc,
        'Duration range: 7 days minimum (if researcher can run 2 sessions/day in the first week) · '
        '14 days maximum (buffer for scheduling conflicts or extended review). Recommended baseline: 10 days.')
    add_italic(doc,
        'Risk note: Because every Arm 1 session simultaneously satisfies Arm 2, and Arm 3 begins '
        'reviewing completed sessions from Day 4, there is no serial dependency between arms — the critical '
        'path is simply the number of sessions the researcher can complete in the available days.')

    # Deliverables
    doc.add_heading('Deliverables', level=2)
    add_body(doc, 'At the end of the 21-day pilot, the Department of Medicine receives:')
    deliverables = [
        '**QC audit log** — a complete record of every query, every tool run, every quality gate outcome, '
        'and every analyst decision across all pilot sessions. Formatted for inclusion in a research record '
        'or regulatory submission.',
        '**Exportable methods report** — a structured methods section for the computational analysis, ready '
        'to include in a manuscript without manual write-up. Tool versions, parameters, and evidence citations '
        'for each quality threshold included.',
        '**Pilot evaluation summary** — H1, H2, and H3 outcomes against their targets; concordance analysis '
        'against any existing results; comparison of time-to-result versus current department baseline.',
        '**Go/no-go recommendation** — a joint assessment of whether BioMate is ready to support a full '
        'research collaboration, and what (if anything) would need to change before the full study begins.',
    ]
    add_numbered_list(doc, deliverables)
    add_horizontal_rule(doc)

    # Data and Confidentiality
    doc.add_heading('Data and Confidentiality', level=2)
    add_body(doc,
        'Compound structures and target identifiers shared for the pilot remain under the Department\'s '
        'governance at all times. BioMate processes data only within the agreed computational environment. '
        'No proprietary compound data is retained by BioMate after the pilot window closes. All session '
        'memory is exportable and deletable.')
    add_body(doc,
        'Data governance is covered by BioMate\'s Terms of Service, which researchers accept at platform '
        'registration. The Terms explicitly prohibit BioMate from using research data for model training or '
        'retaining compound data beyond the pilot window, and guarantee deletion within 14 days of pilot '
        'completion upon request.')
    add_horizontal_rule(doc)

    # Path to Full Collaboration
    doc.add_heading('Path to Full Collaboration', level=2)
    add_body(doc,
        'A successful pilot is the entry point to a deeper research collaboration. The full study — which '
        'this pilot de-risks — would evaluate BioMate across a complete DMTA (Design-Make-Test-Analyse) '
        'campaign cycle, including CRO assay data integration, multi-objective Bayesian optimisation for '
        'next-round compound design, and drug MoA characterisation from patient RNA-seq. The outcome would '
        'be a jointly authored methods evaluation paper, with the Department\'s clinical context as the '
        'scientific anchor.')
    add_body(doc, 'The full study design, timeline, and authorship arrangement will be agreed after the pilot debrief.')

    add_horizontal_rule(doc)
    add_italic(doc, 'March 2026  ·  BioMate AI  ·  Draft for discussion with Zhejiang People\'s Hospital, Department of Medicine')

    doc.save('/home/yzhang/biomate/business/BioMate_DrugDiscovery_Study_Proposal.docx')
    print('✓ BioMate_DrugDiscovery_Study_Proposal.docx saved')


if __name__ == '__main__':
    build_introduction()
    build_study_proposal()
    print('\nDone.')
