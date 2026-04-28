#!/usr/bin/env python3
"""
Create BioMate_Intro_Deck_v7.pptx by revising v5.pptx with v7 content.
Updates slide titles and body text while preserving the v5 visual design.
Adds 2 new slides (QC + Competitive Position) by duplicating existing slides.

Run: python3 scripts/create_deck_v7.py
"""

import copy
from pptx import Presentation
from pptx.util import Pt
from pptx.dml.color import RGBColor
from lxml import etree

SRC  = 'business/BioMate_Intro_Deck_v5.pptx'
DEST = 'business/BioMate_Intro_Deck_v7.pptx'


def set_text(shape, text: str, preserve_runs=True):
    """Replace all text in a shape's text frame with new text, preserving paragraph/run format."""
    tf = shape.text_frame
    # Keep formatting of first run in first paragraph
    try:
        first_para = tf.paragraphs[0]
        first_run  = first_para.runs[0] if first_para.runs else None
    except Exception:
        first_run = None

    # Clear all paragraphs
    tf.clear()
    lines = text.strip().split('\n')
    for li, line in enumerate(lines):
        if li == 0:
            para = tf.paragraphs[0]
        else:
            para = tf.add_paragraph()
        run = para.add_run()
        run.text = line
        # Try to keep original font properties
        if first_run and preserve_runs:
            try:
                run.font.bold   = first_run.font.bold
                run.font.size   = first_run.font.size
                run.font.color.rgb = first_run.font.color.rgb
            except Exception:
                pass


def duplicate_slide(prs, slide_index: int):
    """Append a copy of slide at slide_index to the presentation. Returns new slide."""
    template = prs.slides[slide_index]
    blank_layout = prs.slide_layouts[0]  # use first available layout
    new_slide = prs.slides.add_slide(blank_layout)

    # Copy all shapes from template
    for shape in template.shapes:
        sp = copy.deepcopy(shape._element)
        new_slide.shapes._spTree.insert(2, sp)

    # Remove the placeholder that add_slide added
    for ph in new_slide.placeholders:
        sp = ph._element
        sp.getparent().remove(sp)

    return new_slide


def clear_shape_text(shape):
    """Clear all text from a shape's text frame."""
    tf = shape.text_frame
    # Keep first paragraph, clear its runs
    for para in tf.paragraphs:
        for run in para.runs:
            run.text = ''
    # Remove all but the first paragraph
    from lxml import etree
    txBody = tf._txBody
    paras = txBody.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/main}p')
    for p in paras[1:]:
        p.getparent().remove(p)


def update_slide(slide, title: str, body: str):
    """Clear ALL text shapes, then set title in topmost and body in largest."""
    text_shapes = [s for s in slide.shapes if s.has_text_frame]
    if not text_shapes:
        return

    # Clear every text shape first (removes all old v5 content)
    for s in text_shapes:
        clear_shape_text(s)

    # Title = topmost text shape
    by_top = sorted(text_shapes, key=lambda s: getattr(s, 'top', 999999))
    title_shape = by_top[0] if by_top else None

    # Body = largest remaining shape by area
    others = [(s.width * s.height, i, s) for i, s in enumerate(text_shapes)
              if s != title_shape]
    body_shape = sorted(others, reverse=True)[0][2] if others else None

    if title_shape and title:
        set_text(title_shape, title)
    if body_shape and body:
        set_text(body_shape, body)


# ── Slide content for v7 ──────────────────────────────────────────────────────

SLIDES_V7 = [
    # (title, body_text)
    (
        "BioMate AI — A virtual lab that thinks.",
        "AI-powered computational platform for pharma, biotech, and life sciences.\n\n"
        "Describe a scientific objective in plain language — BioMate selects the right\n"
        "validated workflow, executes it, and returns a defensible, audit-ready result.\n"
        "No code. No specialist required. Minutes, not days.\n\n"
        "biomate.ai  ·  contact@biomate.ai  ·  Confidential — April 2026"
    ),
    (
        "The Problem",
        "Computationally demanding biomedical work is a bottleneck at every stage.\n\n"
        "SPEED\n"
        "  Bioinformatics analysis:     2–5 days per study\n"
        "  ADMET / DMPK profiling:     2–8 weeks via CRO\n"
        "  IND computational sections: 3–6 weeks manual\n\n"
        "COST\n"
        "  Consulting:                 $150–300/hour\n"
        "  CRO analytical services:    $10,000–100,000/project\n"
        "  In-house bioinformatician:  $150,000–200,000/year\n\n"
        "QUALITY\n"
        "  Generic AI hallucinates tool configurations\n"
        "  No validated QC standards → indefensible results\n"
        "  No audit trail → not submission-ready\n\n"
        "Every slow cycle means slower decisions. Every missed QC standard means regulatory risk."
    ),
    (
        "The Solution: Ask the question. BioMate handles everything in between.",
        "1  ASK\n"
        "   Describe your objective in plain language.\n"
        "   BioMate maps it to the right validated workflow.\n\n"
        "2  CONFIRM\n"
        "   Review the plan, adjust parameters, approve — all in one conversation.\n\n"
        "3  RESULTS\n"
        "   QC-graded outputs · AI Findings summary\n"
        "   Auto-generated Methods section · Full audit trail · Ready for submission\n\n"
        "2,000+ validated workflows · 34 biomedical domains\n"
        "Gold / Silver / Bronze evidence-graded QC\n"
        "GPU-backed cloud execution — minutes, not days"
    ),
    (
        "Product: One Platform. The Full Biomedical Computation Stack.",
        "DRUG DISCOVERY (6 stages)\n"
        "  Target Discovery · Hit Discovery · ADMET & Lead Optimization\n"
        "  Preclinical DMPK · Clinical Pharmacology · Pharmacovigilance\n\n"
        "GENOMICS & MULTI-OMICS\n"
        "  WGS · WES · RNA-seq · scRNA-seq · ATAC-seq · ChIP-seq\n"
        "  Proteomics · Metabolomics · Metagenomics · Epigenomics\n\n"
        "STRUCTURAL BIOLOGY\n"
        "  Cryo-EM SPA · AlphaFold3 · Molecular dynamics · Docking\n\n"
        "REGULATORY & COMPLIANCE\n"
        "  IND §2.6.1 computational narrative · CRO submission packages\n"
        "  21 CFR Part 11 audit trail · Gold / Silver / Bronze QC export"
    ),
    (
        "Differentiator: The only platform where every QC decision is citable.",
        "GOLD    — Universally accepted consensus\n"
        "          GATK Best Practices · FDA guidance · ICH guidelines\n\n"
        "SILVER  — Community standard\n"
        "          ENCODE4 · RELION guidelines · ISSX benchmarks\n\n"
        "BRONZE  — Field heuristic from benchmark literature\n\n"
        "32 named protocol-aware QC profiles\n"
        "(FFPE RNA-seq · Clinical WGS · Phase-plate cryo-EM · etc.)\n\n"
        "Auto-loop QC: 96.4% convergence within 3 iterations (96/96 tests)\n"
        "Full per-run audit trail — every threshold, every override, every user action.\n\n"
        "Nature Methods publication in preparation."
    ),
    (
        "Traction: Built. Validated. Running.",
        "PLATFORM\n"
        "  ✓  2,000+ validated workflows · 34 domains\n"
        "  ✓  Drug discovery: all 24 gap workflows on AWS Batch — passing\n"
        "  ✓  IND §2.6.1 computational narrative — complete, validated\n"
        "  ✓  CRO compliance workspace — 10/10 E2E tests passing\n"
        "  ✓  Auto-loop QC — 96/96 tests passing (5 domains)\n"
        "  ✓  Cryo-EM SPA — 49/49 assertions passing\n\n"
        "PILOT PROGRAMS\n"
        "  ✓  Drug discovery pilot — active (ADMET, docking, PBPK, IND)\n"
        "  ✓  Structural biology pilot — active (cryo-EM processing)\n\n"
        "EVALUATION\n"
        "  ✓  BiomniEval1: 68–69% (top-tier for this class)\n"
        "  ✓  Workflow routing: 84% exact match (120-query benchmark)\n"
        "  ✓  Memory recall: 100% weighted score\n"
        "  ✓  Auto-loop convergence: 96.4% within 3 iterations"
    ),
    (
        "Market Opportunity: A large market. An open window.",
        "TAM    Global life science R&D + CRO + software: $250B+ annually\n\n"
        "SAM    AI-powered computational life science platforms\n"
        "         $15B bioinformatics software (20%+ CAGR)\n"
        "         $8B  analytical CRO services\n"
        "         $6B  computational drug discovery (35%+ CAGR)\n\n"
        "SOM    500,000+ computationally underserved professionals — no adequate solution\n\n"
        "TIMING SIGNALS\n"
        "  Sakana AI      $2.65B valuation   Nov 2025   AI for research\n"
        "  FutureHouse    $70M seed          Dec 2025   Eric Schmidt\n"
        "  Phylo/Biomni   $13.5M (A16Z)      Feb 2026   Direct category\n"
        "  NVIDIA + Lilly $1B joint lab      2026       AI infra is strategic\n\n"
        "The category is forming now. The leader is not yet determined."
    ),
    (
        "Competitive Position: Execution depth + regulatory-grade output quality.",
        "                    BioMate  Phylo   Edison  Seqera  BenchSci\n"
        "Validated workflows   2,000+    82     ~12    500+      N/A\n"
        "Drug dev coverage     6-stage  Partial  None   None    Discovery\n"
        "QC governance         Cited    None    None    Manual   None\n"
        "Regulatory output     IND/CRO  None    None    None    None\n"
        "Audit trail           Full     None    Partial  None    None\n"
        "No code required      Yes      Yes     Yes     No      Yes\n\n"
        "BioMate's moat: 2,000+ validated workflows, 32 QC profiles, 6-stage drug\n"
        "development coverage — built over years, cited in publications.\n"
        "Cannot be replicated by adding an AI interface to a shallow tool catalog."
    ),
    (
        "Business Model: Researcher → Institution → Enterprise.",
        "TIER         PRICE          TARGET\n"
        "Free         $0/mo          Academic researchers\n"
        "Premium      $29/mo         Individual researchers, PIs\n"
        "Team         $79/user/mo    Labs, core facilities, biotech\n"
        "Enterprise   $2K–$20K/mo    Pharma, large CROs, med centers\n\n"
        "+ Outcome-based (Year 2): pay per delivered result\n"
        "  RNA-seq $25 · ADMET $50 · PBPK $500 · CRO package $1,000\n\n"
        "THE VALUE ARGUMENT\n"
        "  Bioinformatics consultant:  $150–300/hr\n"
        "  Core facility RNA-seq:      $500–5,000/project\n"
        "  CRO ADMET engagement:       $5,000–50,000/project\n"
        "  BioMate Premium:            $29/month\n\n"
        "Break-even: 110 Premium users  OR  41 Team users\n"
        "Target gross margin: 89%+"
    ),
    (
        "Financial Projections: Conservative. Defensible. Enterprise-driven.",
        "YEAR 1 REVENUE PROJECTION\n"
        "  Premium (150 × $29/mo)                    $52,200\n"
        "  Team (90 users × $79/mo)                  $85,320\n"
        "  Enterprise (5 accounts avg $2,000/mo)    $120,000\n"
        "  AI Overage + Compute Markup               $30,000\n"
        "  TOTAL YEAR 1                             $299,520\n"
        "  Gross Margin                                  ~83%\n\n"
        "3-YEAR PROJECTION\n"
        "  Year 1:   10K users ·  5 enterprise  →   $300K ARR\n"
        "  Year 2:   50K users · 25 enterprise  →  $1.2M ARR\n"
        "  Year 3:  150K users · 60 enterprise  →  $4.2M ARR\n\n"
        "KEY UNIT ECONOMICS\n"
        "  LTV Premium (24mo)      $696\n"
        "  LTV Team (24mo)         $1,896\n"
        "  LTV Enterprise (24mo)   $48,000+\n"
        "  Gross margin (subscription) 89% · (outcome-based) 94%"
    ),
    (
        "Go-To-Market: Researcher by researcher. Lab by lab. Enterprise by enterprise.",
        "PHASE 1 — SEED (Months 1–6)\n"
        "  Target:  Academic researchers · individual scientists\n"
        "  Channel: Free tier · GitHub · r/bioinformatics · nf-core Slack · ISMB / ASHG\n"
        "  Goal:    1,000–5,000 active users · first Pro conversions\n\n"
        "PHASE 2 — GROW (Months 6–12)\n"
        "  Target:  Labs · core facilities · academic med centers · biotech\n"
        "  Channel: Institutional pilots · publications · word of mouth\n"
        "  Goal:    10,000 users · 5 enterprise accounts · Nature Methods preprint\n\n"
        "PHASE 3 — SCALE (Year 2)\n"
        "  Target:  Pharma R&D · CROs · CDMOs\n"
        "  Channel: Direct enterprise outreach · DIA/ISSX · CRO partner channel\n"
        "  Goal:    25 enterprise accounts · $1M+ ARR · SOC 2 Type II\n\n"
        "PHASE 4 — PLATFORM (Year 3+)\n"
        "  Goal:    $4M+ ARR · category standard · geographic expansion"
    ),
    (
        "The Team: Built by people who understand both the science and the system.",
        "FOUNDER / CEO\n"
        "  PhD · Natural Language Processing & ML-Based Question Answering Systems\n"
        "  12+ years in biomedical informatics · UTHealth · Alibaba DAMO Academy\n"
        "  yaoyun.zhang@biomate.ai\n\n"
        "CORE TEAM (5 people · every member 5+ years biomedical experience)\n"
        "  Software Engineer     Full-stack · UI · workflow viewer\n"
        "  Backend Engineer      API · pipeline orchestration\n"
        "  MLOps / DevOps        LLM deployment · AWS execution\n"
        "  Security Expert       HIPAA · audit trails · SSO\n\n"
        "HIRING PLAN\n"
        "  Enterprise Sales      Month 6–9 (post first 5 contracts)\n"
        "  Scientific Advisors   Month 3–6 (pharma/CRO domain experts)\n"
        "  Partnerships          Month 3–6 (conference + channel)"
    ),
    (
        "The Ask",
        "WHAT WE ARE SEEKING\n\n"
        "  Seed Capital         $1M–$2M\n"
        "  Use of funds:        Enterprise sales hire · Marketing\n"
        "                       SOC 2 compliance · Infrastructure scale\n"
        "                       Scientific publication\n"
        "                       6–18 months runway\n\n"
        "  Enterprise Pilots    Pharma R&D · CRO/CDMO · Academic med center\n"
        "  Strategic Partners   NVIDIA Inception · Cloud programs · CRO channel\n\n"
        "WHAT IS ALREADY BUILT\n"
        "  2,000+ validated workflows · 34 domains\n"
        "  Full drug development pipeline (6 stages, all 24 workflows passing)\n"
        "  IND §2.6.1 filing support · CRO submission packages\n"
        "  Evidence-graded QC governance (32 profiles) · Auto-loop QC 96.4%\n"
        "  Active pilots · Production AWS infrastructure\n\n"
        "  Website: biomate.ai  ·  Contact: contact@biomate.ai"
    ),
]


def main():
    prs = Presentation(SRC)
    n_src = len(prs.slides)  # 11 slides in v5

    # We need 13 slides; add 2 by duplicating slide index 3 (a content slide)
    print(f'Source: {n_src} slides')
    print('Adding 2 new slides (duplicate of content slide)...')
    for _ in range(13 - n_src):
        duplicate_slide(prs, 3)  # duplicate a generic content slide

    print(f'Now {len(prs.slides)} slides')

    # Reorder slides so they match the desired v7 sequence
    # v5 order: 0 Cover, 1 Problem, 2 Solution, 3 Market/Competitive, 4 How It Works,
    #           5 What BioMate Is, 6 Traction, 7 Business Model, 8 GTM, 9 Team, 10 Join Us,
    #           11 new-dupe1, 12 new-dupe2
    # v7 target: Cover, Problem, Solution, Product, QC, Traction, Market, Competitive,
    #            Business Model, Financial, GTM, Team, The Ask
    # Map: v5[0,1,2,5,11,6,3,12,7,12,8,9,10]
    # Instead of full reorder (complex), just update each slide's text:

    # Map each of the 13 desired v7 slides to a v5 slide index (for layout stealing)
    # and update its content.
    v5_to_v7_map = [0, 1, 2, 5, 11, 6, 3, 12, 7, 12, 8, 9, 10]

    # Actually, just update slides in order (don't reorder XML — too complex)
    # The visual design will follow whatever layout the slide already has
    for i, (title, body) in enumerate(SLIDES_V7):
        slide = prs.slides[i]
        print(f'  Slide {i+1}: {title[:60]}')
        update_slide(slide, title, body)

    prs.save(DEST)
    print(f'\nSaved: {DEST}')


if __name__ == '__main__':
    main()
