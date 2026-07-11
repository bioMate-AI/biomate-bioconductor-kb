"""
Convert 20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md → .docx
Run: python3 docs/build_autoimmune_strategy_docx.py
Output: docs/20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.docx
"""

import re, os
from docx import Document
from docx.shared import Inches, Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

SRC = os.path.join(os.path.dirname(__file__), "20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md")
OUT = os.path.join(os.path.dirname(__file__), "20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.docx")

# ── Colours ───────────────────────────────────────────────────────────────────
BLUE     = RGBColor(0x1a, 0x56, 0xdb)
DARK     = RGBColor(0x11, 0x18, 0x27)
GRAY     = RGBColor(0x6b, 0x72, 0x80)
LIGHT    = RGBColor(0xf3, 0xf4, 0xf6)
ACCENT   = RGBColor(0x05, 0x96, 0x69)   # green for positive numbers
RED      = RGBColor(0xdc, 0x26, 0x26)
TH_BG    = RGBColor(0x1e, 0x40, 0xaf)   # table header navy

doc = Document()

# ── Page setup ────────────────────────────────────────────────────────────────
section = doc.sections[0]
section.page_width   = Cm(21)
section.page_height  = Cm(29.7)
section.left_margin  = section.right_margin  = Cm(2.54)
section.top_margin   = section.bottom_margin = Cm(2.54)

# ── Default body font ─────────────────────────────────────────────────────────
style = doc.styles["Normal"]
style.font.name = "Calibri"
style.font.size = Pt(10.5)
style.font.color.rgb = DARK

# ── Heading styles ────────────────────────────────────────────────────────────
for lvl, sz, colour in [(1, 22, BLUE), (2, 15, BLUE), (3, 12, DARK), (4, 11, GRAY)]:
    hs = doc.styles[f"Heading {lvl}"]
    hs.font.name = "Calibri"
    hs.font.size = Pt(sz)
    hs.font.color.rgb = colour
    hs.font.bold = True
    hs.paragraph_format.space_before = Pt(14 if lvl == 1 else 10)
    hs.paragraph_format.space_after  = Pt(4)

# ── XML helpers ───────────────────────────────────────────────────────────────
def set_cell_bg(cell, rgb: RGBColor):
    tc   = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd  = OxmlElement("w:shd")
    # RGBColor stores as (r, g, b) tuple accessible by index
    hex_val = f"{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}"
    shd.set(qn("w:val"),   "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"),  hex_val)
    tcPr.append(shd)

def set_cell_borders(table):
    """Thin grey borders on every cell."""
    for row in table.rows:
        for cell in row.cells:
            tc   = cell._tc
            tcPr = tc.get_or_add_tcPr()
            tcBorders = OxmlElement("w:tcBorders")
            for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
                border = OxmlElement(f"w:{side}")
                border.set(qn("w:val"),   "single")
                border.set(qn("w:sz"),    "4")
                border.set(qn("w:space"), "0")
                border.set(qn("w:color"), "CCCCCC")
                tcBorders.append(border)
            tcPr.append(tcBorders)

def add_hr(doc):
    p = doc.add_paragraph()
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"),   "single")
    bottom.set(qn("w:sz"),    "6")
    bottom.set(qn("w:space"), "1")
    bottom.set(qn("w:color"), "CCDDEE")
    pBdr.append(bottom)
    pPr.append(pBdr)
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after  = Pt(2)

# ── Inline markdown → runs ────────────────────────────────────────────────────
INLINE_RE = re.compile(
    r"(\*\*\*(.+?)\*\*\*)"   # bold+italic
    r"|(\*\*(.+?)\*\*)"      # bold
    r"|(\*(.+?)\*)"          # italic
    r"|(`(.+?)`)"            # code
)

def add_inline(para, text, base_size=Pt(10.5), base_bold=False, base_italic=False,
               base_colour=None):
    pos = 0
    for m in INLINE_RE.finditer(text):
        # plain text before match
        if m.start() > pos:
            r = para.add_run(text[pos:m.start()])
            r.font.size   = base_size
            r.font.bold   = base_bold
            r.font.italic = base_italic
            if base_colour:
                r.font.color.rgb = base_colour
        # matched segment
        if m.group(1):   # bold+italic
            r = para.add_run(m.group(2))
            r.bold = True; r.italic = True
        elif m.group(3): # bold
            r = para.add_run(m.group(4))
            r.bold = True
        elif m.group(5): # italic
            r = para.add_run(m.group(6))
            r.italic = True
        elif m.group(7): # inline code
            r = para.add_run(m.group(8))
            r.font.name = "Courier New"
            r.font.size = Pt(9.5)
            r.font.color.rgb = RGBColor(0xc7, 0x25, 0x4e)
        r.font.size = base_size
        if base_colour and not (m.group(3) or m.group(7)):
            r.font.color.rgb = base_colour
        pos = m.end()
    # trailing plain text
    if pos < len(text):
        r = para.add_run(text[pos:])
        r.font.size   = base_size
        r.font.bold   = base_bold
        r.font.italic = base_italic
        if base_colour:
            r.font.color.rgb = base_colour

# ── Table parser ──────────────────────────────────────────────────────────────
def flush_table(rows):
    if not rows:
        return
    # filter out separator rows (|---|---|)
    data = [r for r in rows if not re.match(r"^\|[-| :]+\|$", r.strip())]
    if not data:
        return
    cols = [c.strip() for c in data[0].strip().strip("|").split("|")]
    ncols = len(cols)
    table = doc.add_table(rows=len(data), cols=ncols)
    table.style = "Table Grid"
    table.alignment = WD_ALIGN_PARAGRAPH.LEFT
    for ri, row_txt in enumerate(data):
        cells = [c.strip() for c in row_txt.strip().strip("|").split("|")]
        for ci in range(ncols):
            cell_text = cells[ci] if ci < len(cells) else ""
            cell = table.cell(ri, ci)
            cell.paragraphs[0].clear()
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(3)
            p.paragraph_format.space_after  = Pt(3)
            if ri == 0:
                set_cell_bg(cell, TH_BG)
                r = p.add_run(re.sub(r"\*\*(.+?)\*\*", r"\1", cell_text))
                r.font.bold  = True
                r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                r.font.size  = Pt(9.5)
            else:
                add_inline(p, cell_text, base_size=Pt(9.5))
    set_cell_borders(table)
    doc.add_paragraph()   # breathing room after table

# ── Main parser ───────────────────────────────────────────────────────────────
with open(SRC, encoding="utf-8") as f:
    lines = f.readlines()

in_code   = False
code_buf  = []
table_buf = []
i = 0

def flush_code(buf):
    if not buf:
        return
    joined = "".join(buf).rstrip()
    p = doc.add_paragraph()
    p.paragraph_format.left_indent  = Cm(0.8)
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after  = Pt(4)
    r = p.add_run(joined)
    r.font.name  = "Courier New"
    r.font.size  = Pt(9)
    r.font.color.rgb = RGBColor(0x1f, 0x29, 0x37)
    # light grey shading on paragraph
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"),   "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"),  "F3F4F6")
    pPr.append(shd)

while i < len(lines):
    raw  = lines[i]
    line = raw.rstrip("\n")

    # ── code fence ──────────────────────────────────────────────────────────
    if line.strip().startswith("```"):
        if in_code:
            flush_code(code_buf)
            code_buf = []
            in_code  = False
        else:
            if table_buf:
                flush_table(table_buf); table_buf = []
            in_code = True
        i += 1; continue

    if in_code:
        code_buf.append(raw)
        i += 1; continue

    # ── table rows ──────────────────────────────────────────────────────────
    if line.strip().startswith("|"):
        table_buf.append(line)
        i += 1; continue
    else:
        if table_buf:
            flush_table(table_buf); table_buf = []

    # ── horizontal rule ─────────────────────────────────────────────────────
    if re.match(r"^---+\s*$", line):
        add_hr(doc)
        i += 1; continue

    # ── blank line ───────────────────────────────────────────────────────────
    if line.strip() == "":
        i += 1; continue

    # ── headings ─────────────────────────────────────────────────────────────
    hm = re.match(r"^(#{1,4})\s+(.*)", line)
    if hm:
        lvl  = len(hm.group(1))
        text = hm.group(2).strip()
        # strip inline markdown from heading text
        text = re.sub(r"\*+(.+?)\*+", r"\1", text)
        text = re.sub(r"`(.+?)`",     r"\1", text)
        doc.add_heading(text, level=lvl)
        i += 1; continue

    # ── bullet list ──────────────────────────────────────────────────────────
    bm = re.match(r"^(\s*)[-*]\s+(.*)", line)
    if bm:
        indent = len(bm.group(1))
        text   = bm.group(2)
        p = doc.add_paragraph(style="List Bullet")
        p.paragraph_format.left_indent  = Cm(0.4 + indent * 0.3)
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after  = Pt(2)
        add_inline(p, text)
        i += 1; continue

    # ── numbered list ────────────────────────────────────────────────────────
    nm = re.match(r"^(\s*)\d+\.\s+(.*)", line)
    if nm:
        indent = len(nm.group(1))
        text   = nm.group(2)
        p = doc.add_paragraph(style="List Number")
        p.paragraph_format.left_indent  = Cm(0.4 + indent * 0.3)
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after  = Pt(2)
        add_inline(p, text)
        i += 1; continue

    # ── blockquote / source line (italic grey) ────────────────────────────────
    if line.startswith(">"):
        p = doc.add_paragraph()
        p.paragraph_format.left_indent  = Cm(0.8)
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after  = Pt(2)
        text = line.lstrip("> ").strip()
        add_inline(p, text, base_italic=True, base_colour=GRAY)
        i += 1; continue

    # ── *Source:* lines (italic, indented) ──────────────────────────────────
    if line.strip().startswith("*Source:") or line.strip().startswith("*Note:"):
        p = doc.add_paragraph()
        p.paragraph_format.left_indent  = Cm(0.6)
        p.paragraph_format.space_before = Pt(1)
        p.paragraph_format.space_after  = Pt(4)
        add_inline(p, line.strip(), base_size=Pt(9), base_italic=True, base_colour=GRAY)
        i += 1; continue

    # ── normal paragraph ─────────────────────────────────────────────────────
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after  = Pt(3)
    add_inline(p, line.strip())
    i += 1

# flush any remaining buffers
if table_buf:
    flush_table(table_buf)
if in_code and code_buf:
    flush_code(code_buf)

doc.save(OUT)
print(f"Saved → {OUT}")
