from pptx import Presentation
from pptx.util import Pt
from copy import deepcopy

path = "business/BioMate_Intro_Deck_v7.pptx"
prs = Presentation(path)


def set_text_preserve(shape, new_text):
    """Set text on a shape, preserving formatting of the first run."""
    if not shape.has_text_frame:
        return
    tf = shape.text_frame
    # Get first paragraph & first run formatting
    p0 = tf.paragraphs[0]
    if p0.runs:
        r0 = p0.runs[0]
        # Capture font properties
        font_name = r0.font.name
        font_size = r0.font.size
        font_bold = r0.font.bold
        font_italic = r0.font.italic
        try:
            font_color_rgb = r0.font.color.rgb
        except Exception:
            font_color_rgb = None
        para_align = p0.alignment
    else:
        font_name = font_size = font_bold = font_italic = font_color_rgb = None
        para_align = None

    # Clear all paragraphs
    tf.clear()
    lines = new_text.split("\n")
    for i, line in enumerate(lines):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        if para_align is not None:
            p.alignment = para_align
        run = p.add_run()
        run.text = line
        if font_name:
            run.font.name = font_name
        if font_size:
            run.font.size = font_size
        if font_bold is not None:
            run.font.bold = font_bold
        if font_italic is not None:
            run.font.italic = font_italic
        if font_color_rgb is not None:
            try:
                run.font.color.rgb = font_color_rgb
            except Exception:
                pass


# === Slide 1 (index 1): The Problem ===
slide1 = prs.slides[1]
# shape[1] title
set_text_preserve(slide1.shapes[1], "The Problem")
# shape[4] subtitle/intro
set_text_preserve(
    slide1.shapes[4],
    "Computationally demanding biomedical work is a bottleneck at every stage of the pipeline."
)
# shape[8] SPEED body
set_text_preserve(
    slide1.shapes[8],
    "Bioinformatics analysis: 2–5 days per study\nADMET / DMPK profiling: 2–8 weeks via CRO\nIND computational sections: 3–6 weeks manual"
)
# shape[12] COST body
set_text_preserve(
    slide1.shapes[12],
    "Consulting: $150–300/hour\nCRO analytical services: $10,000–100,000/project\nIn-house bioinformatician: $150,000–200,000/year"
)
# shape[16] QUALITY body
set_text_preserve(
    slide1.shapes[16],
    "Generic AI hallucinates tool configurations\nNo validated QC standards → indefensible results\nNo audit trail → not submission-ready"
)
# shape[18] bottom message
set_text_preserve(
    slide1.shapes[18],
    "Every slow cycle means slower decisions. Every indefensible result means rework. Every missed QC standard means regulatory risk."
)

# === Slide 4 (index 4): QC body text with proper newlines ===
slide4 = prs.slides[4]
# shape[5] GOLD body
set_text_preserve(
    slide4.shapes[5],
    "Universally accepted consensus\nGATK Best Practices · FDA guidance · ICH guidelines\n\"This threshold follows GATK Best Practices for germline variant calling\""
)
# shape[10] SILVER body
set_text_preserve(
    slide4.shapes[10],
    "Community standard\nENCODE4 · RELION guidelines · ISSX benchmarks\n\"This threshold follows ENCODE4 ATAC-seq guidelines\""
)
# shape[15] BRONZE body
set_text_preserve(
    slide4.shapes[15],
    "Field heuristic from benchmark literature\nCited benchmark papers\n\"This threshold is a common field heuristic; see [citation]\""
)

# === Slide 9 (index 9): GTM title ===
slide9 = prs.slides[9]
set_text_preserve(slide9.shapes[1], "Go-To-Market: We Grow the Way Science Grows.")

prs.save(path)
print(f"Saved fixes to {path}")
print("Fixed slides: 1 (The Problem), 4 (QC tiers), 9 (GTM title)")
