import os
import pptx
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

def create_biomate_deck_v7():
    """
    Generates the BioMate v7 investor deck using python-pptx,
    matching the visual style of v6 with the content of v7.
    """

    # ==========================================================================
    # 1. SETUP
    # ==========================================================================

    prs = pptx.Presentation()
    prs.slide_width = Inches(10)
    prs.slide_height = Inches(5.625)

    # Define color palette
    NAVY = RGBColor(0x14, 0x28, 0x3A)
    GREEN = RGBColor(0x2D, 0x86, 0x59)
    DARK_GRAY = RGBColor(0x3A, 0x3A, 0x3A)
    WHITE = RGBColor(0xFF, 0xFF, 0xFF)
    CREAM = RGBColor(0xFB, 0xFB, 0xF6)
    
    # Define slide layout
    blank_slide_layout = prs.slide_layouts[6]

    def set_slide_background(slide):
        background = slide.background
        fill = background.fill
        fill.solid()
        fill.fore_color.rgb = CREAM

    # ==========================================================================
    # 2. HELPER FUNCTIONS
    # ==========================================================================

    def add_title(slide, text):
        """Adds a standard title to the slide."""
        txBox = slide.shapes.add_textbox(Inches(0.5), Inches(0.25), Inches(9), Inches(0.75))
        tf = txBox.text_frame
        p = tf.paragraphs[0]
        p.text = text
        p.font.name = 'Calibri'
        p.font.size = Pt(26)
        p.font.bold = True
        p.font.color.rgb = NAVY
        tf.margin_bottom = tf.margin_top = tf.margin_left = tf.margin_right = 0
        return txBox

    def add_text(slide, text, left, top, width, height, font_size=11, color=DARK_GRAY, bold=False, align=PP_ALIGN.LEFT, font_name='Calibri', line_spacing=1.15):
        """Adds a formatted text box to the slide."""
        txBox = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
        tf = txBox.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = text
        p.font.name = font_name
        p.font.size = Pt(font_size)
        p.font.color.rgb = color
        p.font.bold = bold
        p.alignment = align
        p.line_spacing = line_spacing
        tf.margin_bottom = tf.margin_top = tf.margin_left = tf.margin_right = 0
        return txBox

    def add_footer(slide, text):
        """Adds a navy footer bar with white text."""
        footer_shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, Inches(5.0), prs.slide_width, Inches(0.625))
        footer_shape.fill.solid()
        footer_shape.fill.fore_color.rgb = NAVY
        footer_shape.line.fill.background()
        
        txBox = slide.shapes.add_textbox(Inches(0.5), Inches(5.125), Inches(9), Inches(0.4))
        tf = txBox.text_frame
        tf.vertical_anchor = MSO_ANCHOR.MIDDLE
        p = tf.paragraphs[0]
        p.text = text
        p.font.name = 'Calibri'
        p.font.size = Pt(11)
        p.font.bold = True
        p.font.color.rgb = WHITE
        p.alignment = PP_ALIGN.CENTER
        return footer_shape

    def three_col(slide, col1_data, col2_data, col3_data, top_y=1.5, height=3.0):
        """Adds a three-column layout to the slide."""
        col_width = 2.8
        gutter = 0.4
        start_x = (10 - (3 * col_width + 2 * gutter)) / 2

        # Column 1
        add_text(slide, col1_data[0], start_x, top_y, col_width, 0.4, font_size=14, color=GREEN, bold=True)
        add_text(slide, col1_data[1], start_x, top_y + 0.4, col_width, height - 0.4, font_size=11, color=DARK_GRAY, line_spacing=1.3)

        # Column 2
        col2_x = start_x + col_width + gutter
        add_text(slide, col2_data[0], col2_x, top_y, col_width, 0.4, font_size=14, color=GREEN, bold=True)
        add_text(slide, col2_data[1], col2_x, top_y + 0.4, col_width, height - 0.4, font_size=11, color=DARK_GRAY, line_spacing=1.3)

        # Column 3
        col3_x = col2_x + col_width + gutter
        add_text(slide, col3_data[0], col3_x, top_y, col_width, 0.4, font_size=14, color=GREEN, bold=True)
        add_text(slide, col3_data[1], col3_x, top_y + 0.4, col_width, height - 0.4, font_size=11, color=DARK_GRAY, line_spacing=1.3)


    # ==========================================================================
    # SLIDE 1: Cover
    # ==========================================================================
    slide = prs.slides.add_slide(blank_slide_layout)
    set_slide_background(slide)
    
    add_text(slide, "BioMate AI", 0.5, 1.5, 9, 1.0, font_size=54, color=NAVY, bold=True)
    add_text(slide, "A virtual lab that thinks.", 0.5, 2.5, 9, 0.5, font_size=24, color=DARK_GRAY)
    add_text(slide, "AI-powered computational platform for pharma, biotech, and life sciences.", 0.5, 3.5, 9, 0.5, font_size=14, color=DARK_GRAY)

    add_text(slide, "[biomate.ai]", 0.5, 5.2, 3, 0.25, font_size=11, color=DARK_GRAY)
    add_text(slide, "[Confidential — April 2026]", 0.5, 5.2, 9, 0.25, font_size=11, color=DARK_GRAY, align=PP_ALIGN.RIGHT)
    
    # ==========================================================================
    # SLIDE 2: The Problem
    # ==========================================================================
    slide = prs.slides.add_slide(blank_slide_layout)
    set_slide_background(slide)
    add_title(slide, "Computationally demanding biomedical work is a bottleneck")
    add_text(slide, "at every stage of the pipeline.", 0.5, 0.65, 9, 0.5, font_size=16, color=DARK_GRAY)

    add_text(slide, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0.5, 1.2, 9, 0.2, font_size=12, color=NAVY)

    col1_data = ("SPEED", "Bioinformatics analysis:    2–5 days per study\nADMET / DMPK profiling:     2–8 weeks via CRO\nIND computational sections: 3–6 weeks manual")
    col2_data = ("COST", "Consulting:                 $150–300/hour\nCRO analytical services:    $10,000–100,000/project\nIn-house bioinformatician:  $150,000–200,000/year")
    col3_data = ("QUALITY", "Generic AI hallucinates tool configurations\nNo validated QC standards → indefensible results\nNo audit trail → not submission-ready")
    three_col(slide, col1_data, col2_data, col3_data, top_y=1.6, height=2.2)

    add_text(slide, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0.5, 4.0, 9, 0.2, font_size=12, color=NAVY)
    
    footer_text = "Every slow cycle means slower decisions.\nEvery indefensible result means rework.\nEvery missed QC standard means regulatory risk."
    add_text(slide, footer_text, 0.5, 4.3, 9, 0.8, font_size=12, color=DARK_GRAY, align=PP_ALIGN.CENTER, line_spacing=1.3, bold=True)
    
    # ==========================================================================
    # SLIDE 3: The Solution
    # ==========================================================================
    slide = prs.slides.add_slide(blank_slide_layout)
    set_slide_background(slide)
    add_title(slide, "Ask the question. BioMate handles everything in between.")
    
    # Create the box
    box = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.5), Inches(1.1), Inches(9), Inches(2.9))
    box.fill.solid()
    box.fill.fore_color.rgb = RGBColor(0xF5, 0xF5, 0xF2)
    box.line.color.rgb = RGBColor(0xCC, 0xCC, 0xCC)
    box.line.width = Pt(1)

    solution_text = (
        ("1  ASK", "Describe your objective in plain language\nBioMate maps it to the right workflow"),
        ("2  CONFIRM", "Review the plan, adjust parameters,\napprove — all in one conversation"),
        ("3  RESULTS", "QC-graded outputs · Findings summary\nAuto-generated Methods section\nFull audit trail · Ready for submission")
    )
    current_y = 1.3
    for heading, body in solution_text:
        add_text(slide, heading, 0.8, current_y, 8.4, 0.3, font_size=12, color=NAVY, bold=True)
        add_text(slide, body, 1.8, current_y, 7.4, 0.8, font_size=11, color=DARK_GRAY, line_spacing=1.2)
        current_y += 0.9

    footer_text_s3 = "2,000+ validated workflows  ·  20+ biomedical domains  ·  Gold / Silver / Bronze evidence-graded QC  ·  GPU-backed cloud execution — minutes, not days"
    add_footer(slide, footer_text_s3)
    
    # ==========================================================================
    # SLIDE 4: Product: What BioMate Covers
    # ==========================================================================
    slide = prs.slides.add_slide(blank_slide_layout)
    set_slide_background(slide)
    add_title(slide, "One platform. The full biomedical computation stack.")
    
    content = [
        ("DRUG DISCOVERY ─────────────────────────────────────────", "Target Discovery    Structure prediction · pocket druggability\n                      CRISPR essentiality · functional genomics\nHit Discovery       Virtual screening · molecular docking\n                      Pharmacophore filtering · ADMET triage\nADMET & Lead Opt    Full ADMET panel · CYP450 DDI\n                      GROMACS MD · REINVENT4 generative design\nPreclinical         PBPK simulation · allometric scaling\n                      Toxicity prediction · CRO package assembly\nClinical Pharm      PopPK · dose-escalation simulation\n                      Pharmacogenomics · DDI\nPharmacovigilance   Post-market signal detection"),
        ("GENOMICS & MULTI-OMICS ─────────────────────────────────", "WGS · WES · RNA-seq · scRNA-seq · ATAC-seq · ChIP-seq\nProteomics · Metabolomics · Metagenomics · Epigenomics"),
        ("STRUCTURAL BIOLOGY ─────────────────────────────────────", "Cryo-EM SPA · Protein structure (AlphaFold3)\nMolecular dynamics · Protein-ligand docking"),
        ("REGULATORY & COMPLIANCE ────────────────────────────────", "IND §2.6.1 computational narrative (AI-drafted, cited)\nCRO submission packages · 21 CFR Part 11 audit trail\nEvidence-graded QC export (Gold / Silver / Bronze)")
    ]
    
    current_y = 1.0
    for header, body in content:
        add_text(slide, header, 0.5, current_y, 9.0, 0.3, font_size=12, color=GREEN, bold=True, font_name='Consolas')
        current_y += 0.3
        body_box = add_text(slide, body, 0.7, current_y, 8.6, 2.0, font_size=10, color=DARK_GRAY, line_spacing=1.3, font_name='Consolas')
        current_y += body_box.height.inches/Inches(1) + 0.1

    # ==========================================================================
    # SLIDE 5: Differentiator: Evidence-Graded QC
    # ==========================================================================
    slide = prs.slides.add_slide(blank_slide_layout)
    set_slide_background(slide)
    add_title(slide, "The only platform where every QC decision is citable.")

    add_text(slide, "───────────────────────────────────────────────────────────────", 0.5, 1.0, 9, 0.2, font_size=12, color=NAVY)
    
    qc_content = [
        ("🥇 GOLD", "Universally accepted consensus", "GATK Best Practices · FDA guidance · ICH guidelines", '"This threshold is the field standard."'),
        ("🥈 SILVER", "Community standard", "ENCODE4 · RELION guidelines · ISSX benchmarks", '"This threshold is widely adopted."'),
        ("🥉 BRONZE", "Field heuristic from benchmark literature", "Cited benchmark papers", '"This threshold is the established convention."')
    ]
    current_y = 1.4
    for medal, title, examples, quote in qc_content:
        add_text(slide, f"{medal}