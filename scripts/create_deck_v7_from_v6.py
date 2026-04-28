#!/usr/bin/env python3
"""
Create v7 PPTX by opening v6.pptx and updating only the text in each shape.
All visual design (colors, positions, backgrounds, decorative shapes) is preserved from v6.
"""
import copy, shutil
from pptx import Presentation
from pptx.util import Pt
from lxml import etree

SRC  = 'business/BioMate_Intro_Deck_v6.pptx'
DEST = 'business/BioMate_Intro_Deck_v7.pptx'

# Copy v6 → v7 as starting point
shutil.copy2(SRC, DEST)
prs = Presentation(DEST)

NS = 'http://schemas.openxmlformats.org/drawingml/2006/main'

def set_run_text(run, text):
    """Replace run text, preserving all font formatting."""
    run.text = text

def clear_tf(tf):
    """Clear all text in a text frame (set all runs to empty string)."""
    for para in tf.paragraphs:
        for run in para.runs:
            run.text = ''

def set_tf(tf, text, preserve_paras=False):
    """
    Set text frame content. If text has newlines, set each paragraph separately.
    Preserves font formatting of first run in each paragraph.
    """
    lines = text.split('\n')
    paras = list(tf.paragraphs)

    for i, line in enumerate(lines):
        if i < len(paras):
            para = paras[i]
            runs = para.runs
            if runs:
                runs[0].text = line
                for r in runs[1:]:
                    r.text = ''
            else:
                run = para.add_run()
                run.text = line
        # Don't add extra paragraphs — if more lines than paragraphs, put remainder in last
        elif paras:
            last_para = paras[-1]
            runs = last_para.runs
            if runs:
                runs[0].text = (runs[0].text + ' ' + line).strip()

    # Clear extra paragraphs
    if not preserve_paras:
        for j in range(len(lines), len(paras)):
            for run in paras[j].runs:
                run.text = ''

def shapes_by_top(slide):
    """Return list of (top_emu, shape) tuples sorted by vertical position."""
    return sorted(
        [(s.top, s) for s in slide.shapes if hasattr(s, 'top') and s.has_text_frame],
        key=lambda x: x[0]
    )

def update_text_at(slide, target_idx, new_text):
    """Update the text of the nth text shape (sorted by top position)."""
    shapes = shapes_by_top(slide)
    if target_idx < len(shapes):
        tf = shapes[target_idx][1].text_frame
        set_tf(tf, new_text)

def print_slide(idx, slide):
    """Debug: print all text shapes on a slide."""
    print(f'\n  Slide {idx+1}:')
    for top, s in shapes_by_top(slide):
        print(f'    top={top//914:4d} "{s.text_frame.text[:60].replace(chr(10)," ")}"')

# ── Print current v6 structure for reference ─────────────────────────────────
print('V6 slide structure:')
for i, slide in enumerate(prs.slides):
    print_slide(i, slide)

print('\n\nApplying v7 content...')

# ── SLIDE 1 — Cover ───────────────────────────────────────────────────────────
# v6 has: tagline, subtitle, 3 feature pills, name, email, confidential
s = prs.slides[0]
sbs = shapes_by_top(s)
# Just update the date
for top, shape in sbs:
    if 'February' in shape.text_frame.text or 'Confidential' in shape.text_frame.text:
        set_tf(shape.text_frame, 'Confidential — April 2026')

# ── SLIDE 2 — The Problem ─────────────────────────────────────────────────────
s = prs.slides[1]
sbs = shapes_by_top(s)
# Title
set_tf(sbs[0][1].text_frame, 'The Problem')
# Subtitle quote → problem statement
for top, shape in sbs:
    txt = shape.text_frame.text
    if 'sister' in txt or 'wet lab' in txt or 'My sister' in txt:
        set_tf(shape.text_frame, 'Computationally demanding biomedical work is a bottleneck at every stage of the pipeline.')
# Section labels: KNOWLEDGE GAP → SPEED, COST & ACCESS → COST, SLOW CYCLES → QUALITY
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if txt == 'KNOWLEDGE GAP': set_tf(shape.text_frame, 'SPEED')
    elif txt == 'COST & ACCESS': set_tf(shape.text_frame, 'COST')
    elif txt == 'SLOW CYCLES': set_tf(shape.text_frame, 'QUALITY')
# Body texts
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'literature' in txt or 'fragmented' in txt:
        set_tf(shape.text_frame, 'Bioinformatics analysis: 2–5 days per study\nADMET / DMPK via CRO: 2–8 weeks\nIND computational sections: 3–6 weeks manual')
    elif 'Bioinformatics consulting' in txt and 'Core facilities' in txt:
        set_tf(shape.text_frame, 'Consulting: $150–300/hour\nCRO analytical services: $10K–100K/project\nIn-house bioinformatician: $150K–200K/year')
    elif 'queues' in txt or 'months' in txt:
        set_tf(shape.text_frame, 'Generic AI hallucinates tool configurations\nNo validated QC standards → indefensible results\nNo audit trail → not submission-ready')
    elif '$250B' in txt or 'bottleneck' in txt:
        set_tf(shape.text_frame, 'Every slow cycle means slower decisions. Every indefensible result means rework. Every missed QC standard means regulatory risk.')

# ── SLIDE 3 — The Solution ────────────────────────────────────────────────────
s = prs.slides[2]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Solution' in txt and len(txt) > 10:
        set_tf(shape.text_frame, 'The Solution: Ask the question. BioMate handles everything in between.')
    elif 'question to validated' in txt or 'From question' in txt:
        set_tf(shape.text_frame, '2,000+ validated workflows · 34 domains · Gold/Silver/Bronze QC · GPU-backed cloud — minutes, not days')
    elif txt == 'THINK': set_tf(shape.text_frame, 'ASK')
    elif txt == 'EXECUTE': set_tf(shape.text_frame, 'CONFIRM')
    elif txt == 'COLLABORATE': set_tf(shape.text_frame, 'RESULTS')
    elif 'Literature' in txt or 'PubMed' in txt:
        set_tf(shape.text_frame, 'Describe your objective in plain language.\nBioMate maps it to the right validated workflow.')
    elif '8,354' in txt or 'workflow templates' in txt:
        set_tf(shape.text_frame, 'Review the plan, adjust parameters, approve —\nall in one conversation.')
    elif 'Shared workspaces' in txt or 'audit trails' in txt:
        set_tf(shape.text_frame, 'QC-graded outputs · AI Findings summary\nAuto-generated Methods section\nFull audit trail · Ready for submission')
    elif 'You stay in control' in txt:
        set_tf(shape.text_frame, 'From plain-language question to defensible, audit-ready result — in minutes, not days.')

# ── SLIDE 4 — Product Coverage (was: Market Pain Points) ─────────────────────
s = prs.slides[3]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Market Pain' in txt or 'Competitive' in txt:
        set_tf(shape.text_frame, 'Product: One Platform. The Full Biomedical Computation Stack.')
    elif txt == 'WHY THE MARKET IS BROKEN':
        set_tf(shape.text_frame, 'DRUG DISCOVERY (6 STAGES)')
    elif '92%' in txt:
        set_tf(shape.text_frame, 'Target Discovery · Hit Discovery · ADMET & Lead Optimization')
    elif '78%' in txt:
        set_tf(shape.text_frame, 'Preclinical DMPK · Clinical Pharmacology · Pharmacovigilance')
    elif '61%' in txt:
        set_tf(shape.text_frame, 'GENOMICS & MULTI-OMICS')
    elif 'queues' in txt and '2–8 weeks' in txt:
        set_tf(shape.text_frame, 'WGS · WES · RNA-seq · scRNA-seq · ATAC-seq · ChIP-seq · Proteomics · Metabolomics')
    elif txt == 'THREE DOMINANT PLAYERS & THEIR GAPS':
        set_tf(shape.text_frame, 'STRUCTURAL BIOLOGY & REGULATORY')
    elif 'Benchling' == txt:
        set_tf(shape.text_frame, 'Cryo-EM SPA · AlphaFold3 · Molecular dynamics · Docking')
    elif 'Dotmatics' in txt:
        set_tf(shape.text_frame, 'IND §2.6.1 computational narrative')
    elif 'DNAnexus' == txt:
        set_tf(shape.text_frame, 'CRO submission packages · 21 CFR Part 11 audit trail')
    elif '$6.1B' in txt: set_tf(shape.text_frame, '')
    elif 'Acquired for' in txt: set_tf(shape.text_frame, '')
    elif '$690M' in txt: set_tf(shape.text_frame, '')
    elif 'Dominates' in txt: set_tf(shape.text_frame, 'Structure prediction · pocket druggability')
    elif '15 acquisitions' in txt: set_tf(shape.text_frame, '')
    elif 'Scalable genomics' in txt: set_tf(shape.text_frame, 'Gold/Silver/Bronze QC · Full audit trail')
    elif 'No AI' in txt: set_tf(shape.text_frame, '')
    elif 'Drug discovery only' in txt: set_tf(shape.text_frame, '')
    elif 'Genomics-only' in txt: set_tf(shape.text_frame, '')
    elif 'MARKET TIMING' in txt or 'HOW BIOMATE' in txt:
        set_tf(shape.text_frame, '')
    elif txt in ('AI-Native','Universal','Accessible','Affordable'):
        set_tf(shape.text_frame, '')
    elif 'LLM-powered' in txt or '20 domains' in txt or 'Natural language interface' in txt or '$29/mo vs' in txt:
        set_tf(shape.text_frame, '')
    elif 'MARKET SIZE' in txt:
        set_tf(shape.text_frame, '')

# ── SLIDE 5 — Differentiator QC (was: How It Works) ──────────────────────────
s = prs.slides[4]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'How It Works' in txt or 'One Conversation' in txt:
        set_tf(shape.text_frame, 'Differentiator: The Only Platform Where Every QC Decision Is Citable.')
    elif 'evidence-driven' in txt or 'Every step' in txt:
        set_tf(shape.text_frame, '32 named protocol-aware QC profiles · Auto-loop QC: 96.4% convergence within 3 iterations · Nature Methods publication in preparation')
    elif txt == 'ASK': set_tf(shape.text_frame, 'GOLD')
    elif txt == 'PLAN': set_tf(shape.text_frame, 'SILVER')
    elif txt == 'EXECUTE': set_tf(shape.text_frame, 'BRONZE')
    elif txt == 'ITERATE': set_tf(shape.text_frame, '')
    elif txt == 'SHARE': set_tf(shape.text_frame, '')
    elif 'Describe your problem' in txt:
        set_tf(shape.text_frame, 'Universally accepted consensus\nGATK Best Practices · FDA guidance · ICH guidelines\n"This threshold is the field standard."')
    elif 'literature' in txt and 'PubMed' in txt:
        set_tf(shape.text_frame, 'Community standard\nENCODE4 · RELION guidelines · ISSX benchmarks\n"This threshold is widely adopted."')
    elif 'Pipeline runs' in txt:
        set_tf(shape.text_frame, 'Field heuristic from benchmark literature\nCited benchmark papers\n"This threshold is the established convention."')
    elif 'Results return' in txt:
        set_tf(shape.text_frame, '')
    elif 'Results, workflows' in txt:
        set_tf(shape.text_frame, '')
    # numbered circles
    elif txt in ('1','2','3','4','5'):
        set_tf(shape.text_frame, '')

# ── SLIDE 6 — Traction (was: What BioMate Is) ────────────────────────────────
s = prs.slides[5]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Intelligent Life Science' in txt or 'What BioMate Is' in txt:
        set_tf(shape.text_frame, 'Traction: Built. Validated. Running.')
    elif 'Evidence-driven AI' in txt:
        set_tf(shape.text_frame, 'Active pilots: drug discovery (ADMET, docking, PBPK, IND) · Structural biology (cryo-EM) · CRO compliance — validated end-to-end')
    elif txt == 'Intelligent': set_tf(shape.text_frame, 'PLATFORM')
    elif txt == 'Automated': set_tf(shape.text_frame, 'EVALUATION')
    elif txt == 'Platform-Scale': set_tf(shape.text_frame, '')
    elif txt == 'Accessible': set_tf(shape.text_frame, '')
    elif 'Understands intent' in txt:
        set_tf(shape.text_frame, '✓  2,000+ validated workflows · 34 domains\n✓  Drug discovery: all 24 gap workflows on AWS Batch — passing\n✓  IND §2.6.1 computational narrative — complete, validated\n✓  CRO compliance workspace — 10/10 E2E tests passing\n✓  Auto-loop QC — 96/96 tests passing (5 domains)\n✓  Cryo-EM SPA — 49/49 assertions passing')
    elif 'Tool selection' in txt:
        set_tf(shape.text_frame, '✓  BiomniEval1 benchmark: 68–69% (top-tier for this class)\n✓  Workflow routing: 84% exact match (120-query benchmark)\n✓  Memory recall: 100% weighted score (20-scenario benchmark)\n✓  Auto-loop convergence: 96.4% within 3 iterations')
    elif '8,354 tools' in txt: set_tf(shape.text_frame, '')
    elif 'Natural language in' in txt: set_tf(shape.text_frame, '')

# ── SLIDE 7 — Traction (was: Traction & Milestones) → now Market Opportunity ─
s = prs.slides[6]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Traction' in txt and 'Milestones' in txt:
        set_tf(shape.text_frame, 'Market Opportunity: A Large Market. An Open Window.')
    elif txt == 'COMPLETED':
        set_tf(shape.text_frame, 'MARKET SIZE')
    elif txt == 'NEXT MILESTONES':
        set_tf(shape.text_frame, 'TIMING SIGNALS')
    elif '8,354 validated' in txt:
        set_tf(shape.text_frame, 'TAM   Global life science R&D + CRO + software: $250B+ annually')
    elif '967 workflow' in txt:
        set_tf(shape.text_frame, 'SAM   $15B bioinformatics software  ·  $8B analytical CRO  ·  $6B computational drug discovery')
    elif 'AI workflow generation' in txt:
        set_tf(shape.text_frame, 'SOM   500,000+ computationally underserved professionals — no adequate solution today')
    elif 'cloud-native' in txt or 'Cloud-native' in txt:
        set_tf(shape.text_frame, 'CAGR: Bioinformatics 20%+  ·  Drug discovery AI 35%+')
    elif 'Cryo-EM SPA' in txt:
        set_tf(shape.text_frame, 'Sakana AI  $2.65B valuation  ·  Nov 2025  ·  AI for research')
    elif 'Multi-LLM' in txt:
        set_tf(shape.text_frame, 'FutureHouse  $70M seed  ·  Dec 2025  ·  Eric Schmidt')
    elif 'collaboration layer' in txt or 'history sharing' in txt:
        set_tf(shape.text_frame, 'Phylo/Biomni  $13.5M (A16Z)  ·  Feb 2026  ·  Direct category competitor')
    elif 'billing' in txt or 'compute cost' in txt:
        set_tf(shape.text_frame, 'NVIDIA + Lilly  $1B joint lab  ·  2026  ·  AI infra is strategic')
    elif '10,000 users' in txt:
        set_tf(shape.text_frame, 'The category is forming now. The leader is not yet determined.')
    elif 'institutional partnerships' in txt:
        set_tf(shape.text_frame, '')
    elif 'Benchmark publication' in txt:
        set_tf(shape.text_frame, '')

# ── SLIDE 8 — Business Model (was: Business Model) ───────────────────────────
s = prs.slides[7]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Business Model' in txt:
        set_tf(shape.text_frame, 'Business Model: Researcher → Institution → Enterprise.')
    elif txt == 'Pro': set_tf(shape.text_frame, 'Premium')
    elif '$29/mo' == txt: pass  # keep
    elif '1,000 queries' in txt:
        set_tf(shape.text_frame, 'Individual researchers, PIs')
    elif '$79/user/mo' == txt: pass  # keep
    elif '5,000 queries' in txt:
        set_tf(shape.text_frame, 'Labs, core facilities, biotech')
    elif txt == 'Enterprise': pass
    elif 'Unlimited · On-premise' in txt:
        set_tf(shape.text_frame, 'Pharma, large CROs, med centers')
    elif txt == 'COST OF THE STATUS QUO':
        set_tf(shape.text_frame, 'THE VALUE ARGUMENT')
    elif txt == 'KEY UNIT ECONOMICS': pass
    elif 'Core facility / lab' in txt:
        set_tf(shape.text_frame, 'Core facility RNA-seq:')
    elif 'CRO analytical' in txt:
        set_tf(shape.text_frame, 'CRO ADMET engagement:')
    elif 'Enterprise lab software' in txt:
        set_tf(shape.text_frame, 'BioMate Premium:')
    elif '$500–5,000/project' == txt:
        set_tf(shape.text_frame, '$500–5,000/project')
    elif '$10K–50K' == txt:
        set_tf(shape.text_frame, '$5,000–50,000/project')
    elif '$50K–500K/yr' == txt:
        set_tf(shape.text_frame, '$29/month')
    elif '78 Pro' in txt or '30 Team' in txt:
        set_tf(shape.text_frame, 'Break-even: 110 Premium users  OR  41 Team users')
    elif 'AI cost per query' in txt:
        set_tf(shape.text_frame, 'Target gross margin: 89%+')
    elif '$0.008' in txt:
        set_tf(shape.text_frame, '')
    elif 'BioMate Pro annual' in txt:
        set_tf(shape.text_frame, '')
    elif '$348/year' in txt:
        set_tf(shape.text_frame, '')
    elif 'Flywheel' in txt:
        set_tf(shape.text_frame, '+ Outcome-based (Year 2): RNA-seq $25 · ADMET $50 · PBPK $500 · CRO package $1,000')

# ── SLIDE 9 — Financial Projections (was: Go-To-Market) ──────────────────────
s = prs.slides[8]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Go-To-Market' in txt or 'Production Floors' in txt:
        set_tf(shape.text_frame, 'Financial Projections: Conservative. Defensible. Enterprise-Driven.')
    elif txt == 'PHASE 1': set_tf(shape.text_frame, 'YEAR 1 REVENUE')
    elif txt == 'PROVE': set_tf(shape.text_frame, 'PROJECTION')
    elif 'Months 1–3' in txt: set_tf(shape.text_frame, '')
    elif 'Academic researchers' in txt and 'Channel: Free' in txt:
        set_tf(shape.text_frame, 'Premium (150 × $29/mo):  $52,200\nTeam (90 users × $79/mo): $85,320\nEnterprise (5 × avg $2K/mo): $120,000\nOverage + Compute: $30,000\nTOTAL YEAR 1: $299,520  (Gross: ~83%)')
    elif txt == 'PHASE 2': set_tf(shape.text_frame, '3-YEAR PROJECTION')
    elif txt == 'CONVERT': set_tf(shape.text_frame, '')
    elif 'Months 4–9' in txt: set_tf(shape.text_frame, '')
    elif 'Research teams' in txt and 'CROs' in txt:
        set_tf(shape.text_frame, 'Year 1:   10K users ·  5 enterprise → $300K ARR\nYear 2:   50K users · 25 enterprise → $1.2M ARR\nYear 3:  150K users · 60 enterprise → $4.2M ARR')
    elif txt == 'PHASE 3': set_tf(shape.text_frame, 'KEY UNIT ECONOMICS')
    elif txt == 'SCALE': set_tf(shape.text_frame, '')
    elif 'Months 10–18' in txt: set_tf(shape.text_frame, '')
    elif 'Pharma QC' in txt:
        set_tf(shape.text_frame, 'LTV Premium (24mo): $696\nLTV Team (24mo): $1,896\nLTV Enterprise (24mo): $48,000+\nGross margin: 89% subscription / 94% outcome-based')
    elif txt == 'PHASE 4': set_tf(shape.text_frame, '')
    elif txt == 'EXPAND': set_tf(shape.text_frame, '')
    elif 'Year 2+' in txt: set_tf(shape.text_frame, '')
    elif 'Hospitals' in txt: set_tf(shape.text_frame, '')
    elif 'Start with research' in txt:
        set_tf(shape.text_frame, '')

# ── SLIDE 10 — Competitive Position (was: The Team) ──────────────────────────
s = prs.slides[9]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'The Team' == txt:
        set_tf(shape.text_frame, 'Competitive Position: Execution Depth + Regulatory-Grade Output Quality.')
    elif 'Five engineers' in txt:
        set_tf(shape.text_frame, 'Not generic AI. Not a CRO. Not a tool. The only platform combining validated workflows, evidence-graded QC, and regulatory output quality.')
    elif 'Photo' == txt: set_tf(shape.text_frame, '')
    elif 'Yaoyun Zhang' == txt: set_tf(shape.text_frame, '')
    elif 'Founder & CEO' == txt: set_tf(shape.text_frame, 'BioMate vs. Competitors')
    elif 'PhD in NLP' in txt:
        set_tf(shape.text_frame, '')
    elif 'UTHealth' in txt: set_tf(shape.text_frame, '')
    elif 'yaoyun.zhang@biomate.ai' == txt: set_tf(shape.text_frame, '')
    elif '[Full-Stack Engineer]' == txt: set_tf(shape.text_frame, 'Validated workflows')
    elif 'Full-Stack Development' == txt: set_tf(shape.text_frame, '2,000+ vs 82 (Phylo) vs ~12 (Edison)')
    elif 'End-to-end platform' in txt: set_tf(shape.text_frame, '')
    elif 'Multiple years' in txt: set_tf(shape.text_frame, '')
    elif '[Back-End Engineer]' == txt: set_tf(shape.text_frame, 'QC governance')
    elif 'Back-End & Data' == txt: set_tf(shape.text_frame, 'Cited sources vs None vs None')
    elif 'Scalable pipeline' in txt: set_tf(shape.text_frame, '')
    elif '[MLOps' in txt: set_tf(shape.text_frame, 'Regulatory output')
    elif 'MLOps & DevOps' == txt: set_tf(shape.text_frame, 'IND/CRO packages vs None vs None')
    elif 'Model deployment' in txt: set_tf(shape.text_frame, '')
    elif '[Security' in txt: set_tf(shape.text_frame, 'Drug dev coverage')
    elif 'Security & Compliance' == txt: set_tf(shape.text_frame, '6-stage vs Partial vs None')
    elif 'HIPAA, 21 CFR' in txt: set_tf(shape.text_frame, "BioMate's moat: 2,000+ validated workflows, 32 QC profiles, 6-stage drug development coverage — built over years, cited in publications.")

# ── SLIDE 11 — Go-To-Market (was: Join Us) ───────────────────────────────────
s = prs.slides[10]
sbs = shapes_by_top(s)
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if 'Join Us' == txt or 'BioMate is seeking partners' in txt:
        if len(txt) < 20:
            set_tf(shape.text_frame, 'Go-To-Market: We Grow the Way Science Grows.')
        else:
            set_tf(shape.text_frame, 'Researcher by researcher. Lab by lab. Enterprise by enterprise. The same flywheel that built Galaxy to 50,000 users.')
    elif '8,354 tools' in txt:
        set_tf(shape.text_frame, 'Phase 1 — Seed (Months 1–6): Academic researchers · Free tier · GitHub · nf-core · ISMB/ASHG · Goal: 1,000–5,000 users')
    elif 'For every scientist' in txt:
        set_tf(shape.text_frame, 'Phase 2 — Grow (Months 6–12): Labs · core facilities · institutional pilots · publications · Goal: 10K users · 5 enterprise · $500K ARR')
    elif 'Yaoyun Zhang' in txt and 'biomate.ai' in txt:
        set_tf(shape.text_frame, 'Phase 3 — Scale (Year 2): Pharma R&D · CROs · CDMOs · DIA/ISSX · Goal: 25 enterprise · $1M+ ARR · SOC 2 Type II\n\nPhase 4 — Platform (Year 3+): Global expansion · GxP integrations · Goal: $4M+ ARR · category standard')

# ── SLIDE 12 — The Team (new slide, duplicate slide 11's shell) ──────────────
# Use slide 10 (which we just turned into GTM) and slide 11 for team
# Actually slides[10] = GTM, slides[11] = The Ask, slides[12] = empty
# Let's use slides[11] for Team and slides[12] for The Ask
s = prs.slides[11]
sbs = shapes_by_top(s)
# Slide 11 in v6 was the closing "Join Us" card with big text — reuse for Team
for top, shape in sbs:
    txt = shape.text_frame.text.strip()
    if txt == 'Join Us':
        set_tf(shape.text_frame, 'The Team')
    elif 'BioMate is seeking' in txt:
        set_tf(shape.text_frame, 'Built by people who understand both the science and the system.\n\nFounder / CEO: Yaoyun Zhang\nPhD · Natural Language Processing & ML-Based Question Answering Systems\n12+ years in biomedical informatics · UTHealth · Alibaba DAMO Academy\nyaoyun.zhang@biomate.ai')
    elif '8,354 tools' in txt:
        set_tf(shape.text_frame, 'Core Team (5 people · every member 5+ years biomedical experience):\nSoftware Engineer — Full-stack · UI · workflow viewer\nBackend Engineer — API · pipeline orchestration\nMLOps / DevOps — LLM deployment · AWS execution\nSecurity Expert — HIPAA · audit trails · SSO')
    elif 'For every scientist' in txt:
        set_tf(shape.text_frame, 'Hiring: Enterprise Sales (Month 6–9) · Scientific Advisors (Month 3–6) · Partnerships (Month 3–6)')
    elif 'yaoyun.zhang' in txt:
        set_tf(shape.text_frame, 'biomate.ai  ·  contact@biomate.ai')

# ── SLIDE 13 — The Ask (was: empty) ──────────────────────────────────────────
s = prs.slides[12]
sbs = shapes_by_top(s)
# This slide may be empty in v6 — add text using any available shapes
if sbs:
    for i, (top, shape) in enumerate(sbs):
        if i == 0:
            set_tf(shape.text_frame, 'The Ask')
        elif i == 1:
            set_tf(shape.text_frame, 'The product is built. Capital unlocks distribution — not development.')
else:
    # No text shapes — this slide is truly blank. Leave it.
    print('  Slide 13 has no text shapes — leaving blank')

prs.save(DEST)
print(f'\nSaved: {DEST}')
import os
print(f'Size: {os.path.getsize(DEST)//1024} KB')
