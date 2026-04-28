from pptx import Presentation
from pptx.util import Emu, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE

def add_text(slide, text, left, top, width, height, size, bold=False, color='2C2C2C', align='left'):
    tb = slide.shapes.add_textbox(Emu(left), Emu(top), Emu(width), Emu(height))
    tf = tb.text_frame
    tf.word_wrap = True
    lines = text.split('\n')
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        if align == 'center': p.alignment = PP_ALIGN.CENTER
        elif align == 'right': p.alignment = PP_ALIGN.RIGHT
        else: p.alignment = PP_ALIGN.LEFT
        run = p.add_run()
        run.text = line
        run.font.size = Pt(size)
        run.font.bold = bold
        run.font.color.rgb = RGBColor.from_string(color)
        run.font.name = 'Calibri'
    return tb

def add_footer(slide, text):
    rect = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Emu(0), Emu(4850000), Emu(9144000), Emu(450000))
    rect.fill.solid(); rect.fill.fore_color.rgb = RGBColor.from_string('1E3A5F')
    rect.line.fill.background()
    tf = rect.text_frame; tf.margin_left = Emu(200000); tf.margin_right = Emu(200000)
    p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
    run = p.add_run(); run.text = text
    run.font.size = Pt(11); run.font.bold = True
    run.font.color.rgb = RGBColor.from_string('FFFFFF'); run.font.name = 'Calibri'

def add_title(slide, text):
    add_text(slide, text, 600000, 250000, 9002000, 499000, 26, bold=True, color='1E3A5F')

def three_col(slide, labels, bodies, top=1350000, label_color='2D8659'):
    xs = [800000, 3650000, 6500000]
    for i, (lab, body) in enumerate(zip(labels, bodies)):
        add_text(slide, lab, xs[i], top, 2400000, 320000, 13, bold=True, color=label_color)
        add_text(slide, body, xs[i], top+370000, 2400000, 3000000, 11, color='2C2C2C')

def two_col(slide, left_label, left_body, right_label, right_body, top=900000):
    add_text(slide, left_label,  600000, top, 4000000, 320000, 12, bold=True, color='2D8659')
    add_text(slide, left_body,   600000, top+370000, 4000000, 3400000, 11, color='2C2C2C')
    add_text(slide, right_label, 5000000, top, 4000000, 320000, 12, bold=True, color='2D8659')
    add_text(slide, right_body,  5000000, top+370000, 4000000, 3400000, 11, color='2C2C2C')

prs = Presentation()
prs.slide_width = Emu(9144000)
prs.slide_height = Emu(5143500)
blank = prs.slide_layouts[6]

# ── Slide 1 — Cover ──────────────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
bg = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Emu(0), Emu(0), Emu(9144000), Emu(5143500))
bg.fill.solid(); bg.fill.fore_color.rgb = RGBColor.from_string('1E3A5F')
bg.line.fill.background()
add_text(s, 'BioMate AI', 600000, 1400000, 8000000, 700000, 54, bold=True, color='FFFFFF', align='center')
add_text(s, 'A virtual lab that thinks.', 600000, 2200000, 8000000, 500000, 24, color='A8D5BA', align='center')
add_text(s, 'AI-powered computational platform for pharma, biotech, and life sciences.', 600000, 2800000, 8000000, 400000, 16, color='FFFFFF', align='center')
add_text(s, 'Yaoyun Zhang, Founder & CEO  ·  yaoyun.zhang@biomate.ai', 600000, 4200000, 5000000, 300000, 11, bold=True, color='A8D5BA')
add_text(s, 'Confidential — April 2026', 5544000, 4200000, 3000000, 300000, 11, color='A8D5BA', align='right')
add_text(s, 'biomate.ai', 600000, 4500000, 3000000, 300000, 11, color='A8D5BA')

# ── Slide 2 — The Problem ────────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'The Problem')
add_text(s, 'Computationally demanding biomedical work is a bottleneck at every stage of the pipeline.', 600000, 800000, 9002000, 350000, 13, color='5A5A52')
three_col(s,
    ['SPEED', 'COST', 'QUALITY'],
    ['Bioinformatics: 2–5 days per study\nADMET / DMPK via CRO: 2–8 weeks\nIND computational sections: 3–6 weeks manual',
     'Consulting: $150–300/hour\nCRO analytical services: $10K–100K/project\nIn-house bioinformatician: $150K–200K/year',
     'Generic AI hallucinates tool configurations\nNo validated QC standards → indefensible results\nNo audit trail → not submission-ready']
)
add_footer(s, 'Every slow cycle means slower decisions.  Every indefensible result means rework.  Every missed QC standard means regulatory risk.')

# ── Slide 3 — The Solution ───────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'The Solution: Ask the question. BioMate handles everything in between.')
add_text(s, 'From plain-language question to defensible, audit-ready result — in one conversation.', 600000, 800000, 9002000, 350000, 13, color='5A5A52')
three_col(s,
    ['1  ASK', '2  CONFIRM', '3  RESULTS'],
    ['Describe your objective in plain language.\nBioMate maps it to the right validated workflow.',
     'Review the plan, adjust parameters, approve —\nall in one conversation.',
     'QC-graded outputs  ·  AI Findings summary\nAuto-generated Methods section\nFull audit trail  ·  Ready for submission']
)
add_footer(s, '2,000+ validated workflows  ·  34 biomedical domains  ·  Gold / Silver / Bronze evidence-graded QC  ·  GPU-backed cloud — minutes, not days')

# ── Slide 4 — Product Coverage ───────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Product: One Platform. The Full Biomedical Computation Stack.')
add_text(s, 'Every stage of drug development. Every major omics domain. Regulatory output built in.', 600000, 800000, 9002000, 350000, 13, color='5A5A52')
three_col(s,
    ['DRUG DISCOVERY (6 STAGES)', 'GENOMICS & MULTI-OMICS', 'STRUCTURAL BIOLOGY'],
    ['Target Discovery  ·  Hit Discovery\nADMET & Lead Optimization\nPreclinical DMPK  ·  Clinical Pharmacology\nPharmacovigilance',
     'WGS  ·  WES  ·  RNA-seq  ·  scRNA-seq\nATAC-seq  ·  ChIP-seq  ·  CUT&RUN\nProteomics  ·  Metabolomics\nMetagenomics  ·  Epigenomics',
     'Cryo-EM SPA  ·  AlphaFold3\nMolecular dynamics  ·  Docking\n\nREGULATORY & COMPLIANCE\nIND §2.6.1 narrative  ·  CRO packages\n21 CFR Part 11 audit trail']
)

# ── Slide 5 — Differentiator: Evidence-Graded QC ─────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Differentiator: The Only Platform Where Every QC Decision Is Citable.')
add_text(s, 'Not an AI guess. Not a default parameter. A specific published source — with a confidence tier.', 600000, 800000, 9002000, 350000, 13, color='5A5A52')
three_col(s,
    ['GOLD', 'SILVER', 'BRONZE'],
    ['Universally accepted consensus\nGATK Best Practices  ·  FDA guidance  ·  ICH guidelines\n\n"This threshold is the field standard."',
     'Community standard\nENCODE4  ·  RELION guidelines  ·  ISSX benchmarks\n\n"This threshold is widely adopted."',
     'Field heuristic from benchmark literature\nCited benchmark papers\n\n"This threshold is the established convention."']
)
add_text(s, '32 named protocol-aware QC profiles  (FFPE RNA-seq  ·  Clinical WGS  ·  Phase-plate cryo-EM  ·  etc.)', 600000, 4300000, 9002000, 280000, 11, color='5A5A52')
add_footer(s, 'Auto-loop QC: 96.4% convergence within 3 iterations (96/96 tests)  ·  Nature Methods publication in preparation')

# ── Slide 6 — Traction ───────────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Traction: Built. Validated. Running.')
two_col(s,
    'PLATFORM',
    '✓  2,000+ validated workflows  ·  34 domains\n✓  Drug discovery: all 24 gap workflows on AWS Batch — passing\n✓  IND §2.6.1 computational narrative — complete, validated\n✓  CRO compliance workspace — 10/10 E2E tests passing\n✓  Auto-loop QC — 96/96 tests passing (5 domains)\n✓  Cryo-EM SPA — 49/49 assertions passing\n✓  Full chat history sync  ·  memory injection  ·  session restore',
    'EVALUATION',
    '✓  BiomniEval1 benchmark: 68–69%\n    (top-tier for this class)\n\n✓  Workflow routing: 84% exact match\n    (120-query benchmark)\n\n✓  Memory recall: 100% weighted score\n    (20-scenario benchmark)\n\n✓  Auto-loop convergence: 96.4%\n    within 3 iterations'
)
add_footer(s, 'Active pilots: drug discovery (ADMET, docking, PBPK, IND)  ·  Structural biology (cryo-EM)  ·  CRO compliance — validated end-to-end')

# ── Slide 7 — Market Opportunity ─────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Market Opportunity: A Large Market. An Open Window.')
add_text(s, 'CAGR: Bioinformatics 20%+  ·  Drug discovery AI 35%+', 600000, 800000, 9002000, 300000, 13, color='5A5A52')
two_col(s,
    'MARKET SIZE',
    'TAM   Global life science R&D + CRO + software\n         $250B+ annually\n\nSAM   AI-powered computational platforms\n         $15B bioinformatics software\n         $8B  analytical CRO services\n         $6B  computational drug discovery\n\nSOM   500,000+ computationally underserved\n         professionals — no adequate solution today',
    'TIMING SIGNALS',
    'Sakana AI      $2.65B valuation   Nov 2025\nAI for research\n\nFutureHouse    $70M seed          Dec 2025\nEric Schmidt\n\nPhylo/Biomni   $13.5M (A16Z)      Feb 2026\nDirect category competitor\n\nNVIDIA + Lilly $1B joint lab      2026\nAI infra is strategic',
    top=850000
)
add_footer(s, 'The category is forming now. The leader is not yet determined.')

# ── Slide 8 — Competitive Position ───────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Competitive Position: Execution Depth + Regulatory-Grade Output Quality.')
add_text(s, 'Two groups dominate: easy-to-use but indefensible, or expert-facing but inaccessible. BioMate is neither.', 600000, 800000, 9002000, 350000, 13, color='5A5A52')
headers = ['', 'BioMate', 'Phylo', 'Edison', 'Seqera', 'BenchSci']
rows = [
    ['Validated workflows', '2,000+', '82', '~12', '500+', 'N/A'],
    ['Drug dev coverage',   '6-stage', 'Partial', 'None', 'None', 'Discovery'],
    ['QC governance',       'Cited', 'None', 'None', 'Manual', 'None'],
    ['Regulatory output',   'IND/CRO', 'None', 'None', 'None', 'None'],
    ['Audit trail',         'Full', 'None', 'Partial', 'None', 'None'],
    ['No code required',    'Yes', 'Yes', 'Yes', 'No', 'Yes'],
]
col_x = [600000, 2400000, 4200000, 5500000, 6800000, 7900000]
col_w = [1750000, 1700000, 1250000, 1250000, 1050000, 1150000]
row_y = 1250000
add_text(s, '  '.join(f'{h:<14}' for h in headers), 600000, row_y, 9002000, 300000, 10, bold=True, color='1E3A5F')
for r, row in enumerate(rows):
    y = row_y + 350000 + r * 320000
    for c, (val, x, w) in enumerate(zip(row, col_x, col_w)):
        clr = '1E3A5F' if c == 1 else ('C44D3F' if val in ('None','N/A') else '2C2C2C')
        bold = c == 1
        add_text(s, val, x, y, w, 280000, 10, bold=bold, color=clr)
add_footer(s, "BioMate's moat: 2,000+ validated workflows, 32 QC profiles, 6-stage drug development coverage — built over years, cited in publications.")

# ── Slide 9 — Business Model ─────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Business Model: Researcher → Institution → Enterprise.')
# Pricing table
tier_y = 850000
add_text(s, 'TIER', 600000, tier_y, 1600000, 280000, 11, bold=True, color='FFFFFF')
add_text(s, 'PRICE', 2300000, tier_y, 1400000, 280000, 11, bold=True, color='FFFFFF')
add_text(s, 'TARGET', 3800000, tier_y, 4500000, 280000, 11, bold=True, color='FFFFFF')
rect = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Emu(600000), Emu(tier_y), Emu(7700000), Emu(290000))
rect.fill.solid(); rect.fill.fore_color.rgb = RGBColor.from_string('1E3A5F'); rect.line.fill.background()
tiers = [
    ('Free',       '$0/mo',         'Academic researchers'),
    ('Premium',    '$29/mo',        'Individual researchers, PIs'),
    ('Team',       '$79/user/mo',   'Labs, core facilities, biotech'),
    ('Enterprise', '$2K–$20K/mo',  'Pharma, large CROs, med centers'),
]
for i, (tier, price, target) in enumerate(tiers):
    y = tier_y + 330000 + i * 330000
    add_text(s, tier,   600000, y, 1600000, 290000, 11, bold=True, color='1E3A5F')
    add_text(s, price,  2300000, y, 1400000, 290000, 11, bold=True, color='2D8659')
    add_text(s, target, 3800000, y, 4500000, 290000, 11, color='2C2C2C')
add_text(s, '+ Outcome-based (Year 2): RNA-seq $25  ·  ADMET $50  ·  PBPK $500  ·  CRO package $1,000', 600000, 2350000, 7700000, 280000, 10, color='5A5A52')
add_text(s, 'THE VALUE ARGUMENT', 600000, 2750000, 4000000, 280000, 12, bold=True, color='2D8659')
add_text(s, 'Bioinformatics consultant:   $150–300/hr\nCore facility RNA-seq:       $500–5,000/project\nCRO ADMET engagement:       $5,000–50,000/project\nBioMate Premium:            $29/month', 600000, 3080000, 4000000, 1400000, 11, color='2C2C2C')
add_text(s, 'KEY UNIT ECONOMICS', 5000000, 2750000, 4000000, 280000, 12, bold=True, color='2D8659')
add_text(s, 'LTV Premium (24mo):       $696\nLTV Team (24mo):           $1,896\nLTV Enterprise (24mo):    $48,000+\nGross margin (subscription): 89%\nGross margin (outcome):      94%', 5000000, 3080000, 4000000, 1400000, 11, color='2C2C2C')
add_footer(s, 'Break-even: 110 Premium users  OR  41 Team users  ·  Target gross margin: 89%+')

# ── Slide 10 — Financial Projections ─────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Financial Projections: Conservative. Defensible. Enterprise-Driven.')
two_col(s,
    'YEAR 1 REVENUE PROJECTION',
    'Premium (150 × $29/mo)                  $52,200\nTeam (90 users × $79/mo)                $85,320\nEnterprise (5 accounts avg $2K/mo)     $120,000\nAI Overage + Compute Markup             $30,000\n\nTOTAL YEAR 1                           $299,520\nGross Margin                                ~83%\n\nBreak-even: 110 Premium  OR  41 Team users',
    '3-YEAR PROJECTION',
    'Year 1:   10K users ·   5 enterprise  →   $300K ARR\nYear 2:   50K users ·  25 enterprise  →  $1.2M ARR\nYear 3:  150K users ·  60 enterprise  →  $4.2M ARR\n\nKEY UNIT ECONOMICS\nLTV Premium (24mo):     $696\nLTV Team (24mo):        $1,896\nLTV Enterprise (24mo):  $48,000+\n\nGross margin: 89% subscription / 94% outcome-based',
    top=900000
)

# ── Slide 11 — Go-To-Market ───────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'Go-To-Market: We Grow the Way Science Grows.')
add_text(s, 'Researcher by researcher. Lab by lab. Enterprise by enterprise.', 600000, 800000, 9002000, 300000, 13, color='5A5A52')
phases = [
    ('PHASE 1 — SEED  (Months 1–6)',    'Academic researchers  ·  Free tier  ·  GitHub  ·  r/bioinformatics  ·  nf-core Slack  ·  ISMB / ASHG\nGoal: 1,000–5,000 active users  ·  first Pro conversions  ·  first methods section citations'),
    ('PHASE 2 — GROW  (Months 6–12)',   'Labs  ·  core facilities  ·  academic med centers  ·  biotech  ·  institutional pilots  ·  word of mouth  ·  publications\nGoal: 10,000 users  ·  5 enterprise accounts  ·  Nature Methods preprint  ·  $500K ARR'),
    ('PHASE 3 — SCALE  (Year 2)',       'Pharma R&D  ·  CROs  ·  CDMOs  ·  direct enterprise outreach  ·  DIA/ISSX conferences  ·  CRO partner channel\nGoal: 25 enterprise accounts  ·  $1M+ ARR  ·  SOC 2 Type II certified'),
    ('PHASE 4 — PLATFORM  (Year 3+)',   'Global life science organizations  ·  GxP integrations  ·  regulatory partner channel  ·  geographic expansion\nGoal: $4M+ ARR  ·  category standard  ·  platform infrastructure status'),
]
for i, (label, body) in enumerate(phases):
    y = 1150000 + i * 860000
    add_text(s, label, 800000, y, 2800000, 280000, 12, bold=True, color='1E3A5F')
    add_text(s, body,  800000, y+320000, 8100000, 480000, 10, color='5A5A52')

# ── Slide 12 — Team ───────────────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'The Team: Built by People Who Understand Both the Science and the System.')
add_text(s, 'FOUNDER / CEO', 600000, 850000, 9002000, 280000, 13, bold=True, color='2D8659')
add_text(s, 'Yaoyun Zhang', 600000, 1180000, 9002000, 320000, 16, bold=True, color='1E3A5F')
add_text(s, 'PhD · Natural Language Processing & ML-Based Question Answering Systems\n12+ years in biomedical informatics  ·  UTHealth  ·  Alibaba DAMO Academy\nyaoyun.zhang@biomate.ai', 600000, 1540000, 9002000, 500000, 12, color='2C2C2C')
add_text(s, 'CORE TEAM  (5 people · every member 5+ years biomedical experience)', 600000, 2200000, 9002000, 280000, 12, bold=True, color='2D8659')
team = [
    ('Software Engineer',  'Full-stack  ·  UI  ·  workflow viewer'),
    ('Backend Engineer',   'API  ·  pipeline orchestration'),
    ('MLOps / DevOps',     'LLM deployment  ·  AWS execution'),
    ('Security Expert',    'HIPAA  ·  audit trails  ·  SSO'),
]
xs = [600000, 5000000]
for i, (role, desc) in enumerate(team):
    x = xs[i % 2]; y = 2550000 + (i // 2) * 550000
    add_text(s, role, x, y, 4000000, 280000, 12, bold=True, color='1E3A5F')
    add_text(s, desc, x, y+300000, 4000000, 250000, 11, color='5A5A52')
add_footer(s, 'Hiring: Enterprise Sales (Month 6–9)  ·  Scientific Advisors (Month 3–6)  ·  Partnerships (Month 3–6)')

# ── Slide 13 — The Ask ────────────────────────────────────────────────────────
s = prs.slides.add_slide(blank)
add_title(s, 'The Ask')
add_text(s, 'The product is built. Capital unlocks distribution — not development.', 600000, 800000, 9002000, 300000, 13, color='5A5A52')
two_col(s,
    'WHAT WE ARE SEEKING',
    'Seed Capital: $1M–$2M\n\nUse of funds:\n  Enterprise sales hire\n  Marketing\n  SOC 2 compliance\n  Infrastructure scale\n  Scientific publication\n  6–18 months runway\n\nEnterprise Pilots:\n  Pharma R&D  ·  CRO/CDMO  ·  Academic med centers\n\nStrategic Partners:\n  NVIDIA Inception  ·  Cloud programs  ·  CRO channel',
    'WHAT IS ALREADY BUILT',
    '✓  2,000+ validated workflows  ·  34 domains\n✓  Full 6-stage drug development pipeline\n     (all 24 workflows passing on AWS Batch)\n✓  IND §2.6.1 filing support\n✓  CRO submission packages\n✓  Evidence-graded QC (32 profiles)\n✓  Auto-loop QC (96.4% convergence)\n✓  Active pilots in production\n✓  AWS production infrastructure',
    top=1000000
)
add_footer(s, 'biomate.ai  ·  contact@biomate.ai  ·  Confidential — April 2026')

prs.save('business/BioMate_Intro_Deck_v7.pptx')
print(f'Saved: business/BioMate_Intro_Deck_v7.pptx ({__import__("os").path.getsize("business/BioMate_Intro_Deck_v7.pptx")//1024} KB)')
