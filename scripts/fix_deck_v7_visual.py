from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dgm.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.oxml.ns import qn
from lxml import etree
import os

# ---- Colors (matching v6) ----
NAVY = RGBColor(0x1F, 0x3A, 0x5F)        # primary headings / dark bands
GREEN = RGBColor(0x2E, 0x7D, 0x4F)       # accent green
GOLD = RGBColor(0xC9, 0xA2, 0x27)        # accent gold/yellow
RED = RGBColor(0xC0, 0x39, 0x2B)         # alert red
CREAM = RGBColor(0xF5, 0xF0, 0xE6)       # background
CARD = RGBColor(0xFB, 0xF7, 0xEC)        # card background
TEXT_DARK = RGBColor(0x2B, 0x2B, 0x2B)
TEXT_GRAY = RGBColor(0x55, 0x55, 0x55)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)

# ---- Presentation: 16:9 ----
prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
SW, SH = prs.slide_width, prs.slide_height

blank_layout = prs.slide_layouts[6]


def add_bg(slide, color=CREAM):
    bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, SW, SH)
    bg.line.fill.background()
    bg.fill.solid()
    bg.fill.fore_color.rgb = color
    bg.shadow.inherit = False
    return bg


def add_top_bar(slide, color=GREEN, height=Inches(0.08)):
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, SW, height)
    bar.line.fill.background()
    bar.fill.solid()
    bar.fill.fore_color.rgb = color
    return bar


def add_text(slide, left, top, width, height, text, *,
             font_size=14, bold=False, color=TEXT_DARK,
             align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP,
             font_name="Calibri", italic=False):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    tf.margin_top = Inches(0.02)
    tf.margin_bottom = Inches(0.02)
    tf.vertical_anchor = anchor
    lines = text.split("\n") if isinstance(text, str) else text
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        run = p.add_run()
        run.text = line
        run.font.size = Pt(font_size)
        run.font.bold = bold
        run.font.italic = italic
        run.font.name = font_name
        run.font.color.rgb = color
    return tb


def add_rich_text(slide, left, top, width, height, runs_per_line, *,
                  align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    """runs_per_line: list of lines; each line is list of (text, dict-of-attrs)."""
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    for i, line in enumerate(runs_per_line):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        for txt, attrs in line:
            run = p.add_run()
            run.text = txt
            run.font.size = Pt(attrs.get("size", 14))
            run.font.bold = attrs.get("bold", False)
            run.font.italic = attrs.get("italic", False)
            run.font.name = attrs.get("name", "Calibri")
            run.font.color.rgb = attrs.get("color", TEXT_DARK)
    return tb


def add_card(slide, left, top, width, height, fill=CARD, line_color=None):
    card = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    card.line.fill.background() if line_color is None else None
    if line_color is not None:
        card.line.color.rgb = line_color
        card.line.width = Pt(0.75)
    else:
        card.line.fill.background()
    card.fill.solid()
    card.fill.fore_color.rgb = fill
    card.shadow.inherit = False
    return card


def add_title(slide, text, top=Inches(0.3), size=36, color=NAVY, bold=True,
              left=Inches(0.5), width=None):
    if width is None:
        width = SW - Inches(1.0)
    return add_text(slide, left, top, width, Inches(1.0), text,
                    font_size=size, bold=bold, color=color,
                    font_name="Calibri")


def add_subtitle(slide, text, top, size=16, color=TEXT_GRAY, italic=True,
                 left=Inches(0.5), width=None, align=PP_ALIGN.LEFT):
    if width is None:
        width = SW - Inches(1.0)
    return add_text(slide, left, top, width, Inches(0.5), text,
                    font_size=size, italic=italic, color=color,
                    align=align)


def add_dark_band(slide, left, top, width, height, text, *, fill=NAVY,
                  font_size=14, color=WHITE, bold=True, align=PP_ALIGN.LEFT,
                  italic=False):
    band = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    band.line.fill.background()
    band.fill.solid()
    band.fill.fore_color.rgb = fill
    band.shadow.inherit = False
    tf = band.text_frame
    tf.margin_left = Inches(0.2)
    tf.margin_right = Inches(0.2)
    tf.margin_top = Inches(0.08)
    tf.margin_bottom = Inches(0.08)
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    lines = text.split("\n")
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        run = p.add_run()
        run.text = line
        run.font.size = Pt(font_size)
        run.font.bold = bold
        run.font.italic = italic
        run.font.color.rgb = color
        run.font.name = "Calibri"
    return band


def add_circle_number(slide, left, top, diameter, num, fill=GREEN, color=WHITE):
    c = slide.shapes.add_shape(MSO_SHAPE.OVAL, left, top, diameter, diameter)
    c.line.fill.background()
    c.fill.solid()
    c.fill.fore_color.rgb = fill
    c.shadow.inherit = False
    tf = c.text_frame
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    run = p.add_run()
    run.text = str(num)
    run.font.size = Pt(20)
    run.font.bold = True
    run.font.color.rgb = color
    run.font.name = "Calibri"
    return c


# =====================================================
# SLIDE 1 — Cover
# =====================================================
s1 = prs.slides.add_slide(blank_layout)
add_bg(s1, CREAM)
add_top_bar(s1, GREEN)

# Logo placeholder area (cream card)
logo_card = add_card(s1, Inches(4.16), Inches(0.7), Inches(5.0), Inches(2.6),
                     fill=RGBColor(0xEF, 0xE9, 0xD8))
add_text(s1, Inches(4.16), Inches(0.7), Inches(5.0), Inches(2.6),
         "BioMate AI", font_size=54, bold=True, color=NAVY,
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)

# Tagline
add_text(s1, Inches(0.5), Inches(3.6), Inches(12.33), Inches(0.7),
         "A virtual lab that thinks.",
         font_size=32, bold=False, color=NAVY, align=PP_ALIGN.CENTER)

# Subtitle
add_text(s1, Inches(0.5), Inches(4.4), Inches(12.33), Inches(0.5),
         "AI-powered computational platform for pharma, biotech, and life sciences.",
         font_size=16, color=TEXT_GRAY, align=PP_ALIGN.CENTER)

# Three feature buttons
btn_y = Inches(5.3)
btn_h = Inches(0.55)
btn_w = Inches(3.7)
gap = Inches(0.3)
total_w = btn_w * 3 + gap * 2
btn_x_start = (SW - total_w) // 2

for i, label in enumerate(["Human-AI Collaboration", "Automated Workflows", "Evidence-Backed Results"]):
    x = btn_x_start + i * (btn_w + gap)
    add_dark_band(s1, x, btn_y, btn_w, btn_h, label,
                  fill=NAVY, font_size=14, color=WHITE,
                  bold=True, align=PP_ALIGN.CENTER)

# Footer
add_text(s1, Inches(0.5), Inches(6.7), Inches(6), Inches(0.4),
         "biomate.ai", font_size=14, color=GREEN, bold=True)
add_text(s1, Inches(7), Inches(6.7), Inches(5.83), Inches(0.4),
         "Confidential — April 2026", font_size=12,
         color=TEXT_GRAY, italic=True, align=PP_ALIGN.RIGHT)


# =====================================================
# SLIDE 2 — The Problem
# =====================================================
s2 = prs.slides.add_slide(blank_layout)
add_bg(s2)
add_top_bar(s2)

add_title(s2, "The Problem: A Bottleneck at Every Stage")
add_subtitle(s2, "Computationally demanding biomedical work slows every program in the pipeline.",
             Inches(0.95), size=15)

# Three problem cards
card_top = Inches(1.7)
card_h = Inches(1.5)
card_w = Inches(12.33)
card_left = Inches(0.5)

problems = [
    ("SPEED", GOLD,
     [("Bioinformatics analysis:", "2–5 days per study"),
      ("ADMET / DMPK profiling:", "2–8 weeks via CRO"),
      ("IND computational sections:", "3–6 weeks manual")]),
    ("COST", RED,
     [("Consulting:", "$150–300/hour"),
      ("CRO analytical services:", "$10,000–100,000/project"),
      ("In-house bioinformatician:", "$150,000–200,000/year")]),
    ("QUALITY", NAVY,
     [("", "Generic AI hallucinates tool configurations"),
      ("", "No validated QC standards → indefensible results"),
      ("", "No audit trail → not submission-ready")]),
]

ch = Inches(1.5)
gap = Inches(0.1)
y = Inches(1.65)
for i, (label, color, items) in enumerate(problems):
    top = y + i * (ch + gap)
    add_card(s2, card_left, top, card_w, ch, fill=CARD)
    # left tag
    add_dark_band(s2, card_left, top, Inches(1.5), ch, label,
                  fill=color, font_size=18, color=WHITE,
                  bold=True, align=PP_ALIGN.CENTER)
    # items
    item_lines = []
    for k, v in items:
        if k:
            item_lines.append([(k + "  ", {"size": 13, "bold": True, "color": NAVY}),
                               (v, {"size": 13, "color": TEXT_DARK})])
        else:
            item_lines.append([(v, {"size": 13, "color": TEXT_DARK})])
    add_rich_text(s2, card_left + Inches(1.7), top, Inches(10.5), ch,
                  item_lines, anchor=MSO_ANCHOR.MIDDLE)

# Footer dark band
add_dark_band(s2, Inches(0.5), Inches(6.55), Inches(12.33), Inches(0.7),
              "Every slow cycle means slower decisions. Every indefensible result means rework. Every missed QC standard means regulatory risk.",
              fill=NAVY, font_size=14, color=WHITE, bold=True,
              align=PP_ALIGN.CENTER)


# =====================================================
# SLIDE 3 — The Solution
# =====================================================
s3 = prs.slides.add_slide(blank_layout)
add_bg(s3)
add_top_bar(s3)

add_title(s3, "The Solution: One Conversation, End-to-End")
add_subtitle(s3, "Ask the question. BioMate handles everything in between.",
             Inches(0.95), size=15)

# Three step cards across
step_top = Inches(1.7)
step_h = Inches(3.5)
step_w = Inches(3.95)
gap = Inches(0.18)
left0 = Inches(0.55)

steps = [
    ("1", "ASK",
     "Describe your objective in plain language. BioMate maps it to the right validated workflow."),
    ("2", "CONFIRM",
     "Review the plan, adjust parameters, approve — all in one conversation."),
    ("3", "RESULTS",
     "QC-graded outputs · Findings summary · Auto-generated Methods section · Full audit trail · Ready for submission."),
]

for i, (num, title, body) in enumerate(steps):
    x = left0 + i * (step_w + gap)
    add_card(s3, x, step_top, step_w, step_h, fill=CARD)
    # green top accent
    accent = s3.shapes.add_shape(MSO_SHAPE.RECTANGLE, x, step_top, step_w, Inches(0.06))
    accent.line.fill.background()
    accent.fill.solid()
    accent.fill.fore_color.rgb = GREEN
    accent.shadow.inherit = False
    # number circle
    add_circle_number(s3, x + Inches(0.3), step_top + Inches(0.25),
                      Inches(0.7), num)
    # title
    add_text(s3, x + Inches(1.1), step_top + Inches(0.3),
             step_w - Inches(1.2), Inches(0.6), title,
             font_size=22, bold=True, color=NAVY)
    # body
    add_text(s3, x + Inches(0.3), step_top + Inches(1.3),
             step_w - Inches(0.6), step_h - Inches(1.4), body,
             font_size=14, color=TEXT_DARK)

# Stats footer band
stats_top = Inches(5.5)
add_card(s3, Inches(0.5), stats_top, Inches(12.33), Inches(1.05), fill=CARD)
stats_lines = [
    [("2,000+ ", {"size": 16, "bold": True, "color": GREEN}),
     ("validated workflows", {"size": 14, "color": TEXT_DARK}),
     ("    ·    ", {"size": 14, "color": TEXT_GRAY}),
     ("20+ ", {"size": 16, "bold": True, "color": GREEN}),
     ("biomedical domains", {"size": 14, "color": TEXT_DARK})],
    [("Gold / Silver / Bronze evidence-graded QC", {"size": 14, "color": TEXT_DARK, "bold": True}),
     ("    ·    ", {"size": 14, "color": TEXT_GRAY}),
     ("GPU-backed cloud execution — minutes, not days", {"size": 14, "color": TEXT_DARK, "bold": True})],
]
add_rich_text(s3, Inches(0.5), stats_top, Inches(12.33), Inches(1.05),
              stats_lines, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)

# Bottom dark band
add_dark_band(s3, Inches(0.5), Inches(6.7), Inches(12.33), Inches(0.55),
              "You stay in control of the science. BioMate runs the computation — every result graded, traceable, and defensible.",
              fill=NAVY, font_size=13, color=WHITE, bold=True,
              align=PP_ALIGN.CENTER, italic=True)


# =====================================================
# SLIDE 4 — How It Works (numbered process)
# =====================================================
s4 = prs.slides.add_slide(blank_layout)
add_bg(s4)
add_top_bar(s4)

add_title(s4, "How It Works: From Question to Defensible Result")
add_subtitle(s4, "Every step is evidence-graded. Every output is audit-ready.", Inches(0.95), size=15)

steps2 = [
    ("ASK", "Describe your objective in plain language — research, ADMET, variant analysis, IND computational section, or QC review."),
    ("PLAN", "BioMate maps the question to validated workflows, checks domain best practices, and proposes an evidence-backed plan."),
    ("CONFIRM", "Review tools, parameters, and QC thresholds. Adjust in conversation. Approve and execute."),
    ("EXECUTE", "GPU-backed cloud compute runs the pipeline in parallel. Minutes, not weeks. No code, no queue."),
    ("DELIVER", "QC-graded outputs (Gold / Silver / Bronze), AI-authored findings, draft Methods section, full audit trail — submission-ready."),
]

start_y = Inches(1.55)
row_h = Inches(0.95)
for i, (label, desc) in enumerate(steps2):
    y = start_y + i * row_h
    add_circle_number(s4, Inches(0.7), y + Inches(0.05), Inches(0.65), i + 1, fill=GREEN)
    # connector line (except last)
    if i < len(steps2) - 1:
        line = s4.shapes.add_shape(MSO_SHAPE.RECTANGLE,
                                   Inches(1.0), y + Inches(0.7),
                                   Inches(0.04), Inches(0.3))
        line.line.fill.background()
        line.fill.solid()
        line.fill.fore_color.rgb = GOLD
        line.shadow.inherit = False
    add_text(s4, Inches(1.6), y, Inches(2.5), Inches(0.4), label,
             font_size=18, bold=True, color=NAVY)
    add_text(s4, Inches(1.6), y + Inches(0.4), Inches(11.2), Inches(0.55),
             desc, font_size=13, color=TEXT_DARK)

add_text(s4, Inches(0.5), Inches(6.85), Inches(12.33), Inches(0.4),
         "What used to take weeks now takes minutes — with citations, QC grades, and a complete audit trail.",
         font_size=13, italic=True, color=GREEN, align=PP_ALIGN.CENTER, bold=True)


# =====================================================
# SLIDE 5 — What BioMate Is (4-quad)
# =====================================================
s5 = prs.slides.add_slide(blank_layout)
add_bg(s5)
add_top_bar(s5)

add_title(s5, "What BioMate Is: An Intelligent Computational Platform")

quads = [
    ("Intelligent",
     "Maps natural-language objectives to validated workflows. Every recommendation grounded in peer-reviewed literature, curated databases (PubMed, GNPS, HMDB, UniProt), and domain protocols — not generic AI guesswork."),
    ("Automated",
     "Tool selection, parameterization, execution, and QC scoring run without manual intervention. From discovery research to submission-grade pipelines."),
    ("Defensible",
     "Gold / Silver / Bronze evidence grading. Auto-generated Methods sections. Full audit trail of tool versions, parameters, and citations. Ready for IND, peer review, and regulatory submission."),
    ("Accessible",
     "Natural language in. Reproducible, audit-ready results out. No coding. No infrastructure expertise. Built for scientists, analysts, and regulatory teams alike."),
]

q_w = Inches(6.0)
q_h = Inches(2.4)
q_gap = Inches(0.25)
q_left = Inches(0.55)
q_top = Inches(1.55)

for i, (h, body) in enumerate(quads):
    r = i // 2
    c = i % 2
    x = q_left + c * (q_w + q_gap)
    y = q_top + r * (q_h + q_gap)
    add_card(s5, x, y, q_w, q_h, fill=CARD)
    add_text(s5, x + Inches(0.3), y + Inches(0.2), q_w - Inches(0.6), Inches(0.5),
             h, font_size=22, bold=True, color=GREEN)
    add_text(s5, x + Inches(0.3), y + Inches(0.85), q_w - Inches(0.6), q_h - Inches(1.0),
             body, font_size=13, color=TEXT_DARK)

add_dark_band(s5, Inches(0.55), Inches(6.55), Inches(12.23), Inches(0.7),
              "Evidence-graded AI:  minutes instead of weeks · citations instead of guesses · defensible results instead of black-box output",
              fill=NAVY, font_size=13, color=WHITE, bold=True,
              align=PP_ALIGN.CENTER)


# =====================================================
# SLIDE 6 — Market Pain & Competitors
# =====================================================
s6 = prs.slides.add_slide(blank_layout)
add_bg(s6)
add_top_bar(s6)

add_title(s6, "Market Pain Points & Competitive Landscape")

# Left: market pain
add_text(s6, Inches(0.5), Inches(1.3), Inches(6), Inches(0.4),
         "WHY THE MARKET IS BROKEN", font_size=14, bold=True, color=GREEN)

pains = [
    "92% of labs still export to Excel for final analysis",
    "78% of labs c