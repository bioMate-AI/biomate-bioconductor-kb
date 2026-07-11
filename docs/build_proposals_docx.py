"""
Build DOCX files for collaboration proposals.
Run: python3 docs/build_proposals_docx.py
"""
import re, os
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

DOCS = os.path.dirname(__file__)

BLUE  = RGBColor(0x1a, 0x56, 0xdb)
DARK  = RGBColor(0x11, 0x18, 0x27)
GRAY  = RGBColor(0x6b, 0x72, 0x80)
TH_BG = RGBColor(0x1e, 0x40, 0xaf)
GREEN = RGBColor(0x05, 0x96, 0x69)

def make_doc():
    doc = Document()
    section = doc.sections[0]
    section.page_width  = Cm(21)
    section.page_height = Cm(29.7)
    section.left_margin = section.right_margin  = Cm(2.54)
    section.top_margin  = section.bottom_margin = Cm(2.54)
    doc.styles["Normal"].font.name = "Calibri"
    doc.styles["Normal"].font.size = Pt(10.5)
    doc.styles["Normal"].font.color.rgb = DARK
    for lvl, sz, col in [(1,22,BLUE),(2,15,BLUE),(3,12,DARK),(4,11,GRAY)]:
        hs = doc.styles[f"Heading {lvl}"]
        hs.font.name = "Calibri"; hs.font.size = Pt(sz)
        hs.font.color.rgb = col; hs.font.bold = True
        hs.paragraph_format.space_before = Pt(14 if lvl==1 else 8)
        hs.paragraph_format.space_after  = Pt(4)
    return doc

def set_cell_bg(cell, rgb):
    tc = cell._tc; tcPr = tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), f"{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}")
    tcPr.append(shd)

def set_borders(table):
    for row in table.rows:
        for cell in row.cells:
            tc = cell._tc; tcPr = tc.get_or_add_tcPr()
            tcB = OxmlElement("w:tcBorders")
            for side in ("top","left","bottom","right","insideH","insideV"):
                b = OxmlElement(f"w:{side}")
                b.set(qn("w:val"),"single"); b.set(qn("w:sz"),"4")
                b.set(qn("w:space"),"0"); b.set(qn("w:color"),"CCCCCC")
                tcB.append(b)
            tcPr.append(tcB)

def add_hr(doc):
    p = doc.add_paragraph()
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    bot = OxmlElement("w:bottom")
    bot.set(qn("w:val"),"single"); bot.set(qn("w:sz"),"6")
    bot.set(qn("w:space"),"1"); bot.set(qn("w:color"),"CCDDEE")
    pBdr.append(bot); pPr.append(pBdr)
    p.paragraph_format.space_before = Pt(2); p.paragraph_format.space_after = Pt(2)

INLINE_RE = re.compile(
    r"(\*\*\*(.+?)\*\*\*)|(\*\*(.+?)\*\*)|(\*(.+?)\*)|(`(.+?)`)"
)

def add_inline(para, text, base_size=Pt(10.5), base_bold=False,
               base_italic=False, base_colour=None):
    pos = 0
    for m in INLINE_RE.finditer(text):
        if m.start() > pos:
            r = para.add_run(text[pos:m.start()])
            r.font.size=base_size; r.font.bold=base_bold; r.font.italic=base_italic
            if base_colour: r.font.color.rgb=base_colour
        if m.group(1):
            r=para.add_run(m.group(2)); r.bold=True; r.italic=True
        elif m.group(3):
            r=para.add_run(m.group(4)); r.bold=True
        elif m.group(5):
            r=para.add_run(m.group(6)); r.italic=True
        elif m.group(7):
            r=para.add_run(m.group(8))
            r.font.name="Courier New"; r.font.size=Pt(9.5)
            r.font.color.rgb=RGBColor(0xc7,0x25,0x4e)
        r.font.size=base_size
        if base_colour and not (m.group(3) or m.group(7)):
            r.font.color.rgb=base_colour
        pos=m.end()
    if pos<len(text):
        r=para.add_run(text[pos:])
        r.font.size=base_size; r.font.bold=base_bold; r.font.italic=base_italic
        if base_colour: r.font.color.rgb=base_colour

def flush_table(doc, rows):
    if not rows: return
    data=[r for r in rows if not re.match(r"^\|[-| :]+\|$",r.strip())]
    if not data: return
    cols=[c.strip() for c in data[0].strip().strip("|").split("|")]
    ncols=len(cols)
    table=doc.add_table(rows=len(data),cols=ncols)
    table.style="Table Grid"
    for ri,row_txt in enumerate(data):
        cells=[c.strip() for c in row_txt.strip().strip("|").split("|")]
        for ci in range(ncols):
            cell_text=cells[ci] if ci<len(cells) else ""
            cell=table.cell(ri,ci)
            cell.paragraphs[0].clear()
            p=cell.paragraphs[0]
            p.paragraph_format.space_before=Pt(3); p.paragraph_format.space_after=Pt(3)
            if ri==0:
                set_cell_bg(cell,TH_BG)
                r=p.add_run(re.sub(r"\*\*(.+?)\*\*",r"\1",cell_text))
                r.font.bold=True; r.font.color.rgb=RGBColor(0xFF,0xFF,0xFF)
                r.font.size=Pt(9.5)
            else:
                add_inline(p,cell_text,base_size=Pt(9.5))
    set_borders(table); doc.add_paragraph()

def flush_code(doc, buf):
    if not buf: return
    p=doc.add_paragraph(); p.paragraph_format.left_indent=Cm(0.8)
    p.paragraph_format.space_before=Pt(4); p.paragraph_format.space_after=Pt(4)
    r=p.add_run("".join(buf).rstrip())
    r.font.name="Courier New"; r.font.size=Pt(9); r.font.color.rgb=RGBColor(0x1f,0x29,0x37)
    pPr=p._p.get_or_add_pPr(); shd=OxmlElement("w:shd")
    shd.set(qn("w:val"),"clear"); shd.set(qn("w:color"),"auto"); shd.set(qn("w:fill"),"F3F4F6")
    pPr.append(shd)

def convert(src, out):
    doc = make_doc()
    with open(src, encoding="utf-8") as f:
        lines = f.readlines()
    in_code=False; code_buf=[]; table_buf=[]; i=0
    while i<len(lines):
        raw=lines[i]; line=raw.rstrip("\n")
        if line.strip().startswith("```"):
            if in_code: flush_code(doc,code_buf); code_buf=[]; in_code=False
            else:
                if table_buf: flush_table(doc,table_buf); table_buf=[]
                in_code=True
            i+=1; continue
        if in_code: code_buf.append(raw); i+=1; continue
        if line.strip().startswith("|"):
            table_buf.append(line); i+=1; continue
        else:
            if table_buf: flush_table(doc,table_buf); table_buf=[]
        if re.match(r"^---+\s*$",line): add_hr(doc); i+=1; continue
        if line.strip()=="": i+=1; continue
        hm=re.match(r"^(#{1,4})\s+(.*)",line)
        if hm:
            text=re.sub(r"\*+(.+?)\*+",r"\1",hm.group(2).strip())
            text=re.sub(r"`(.+?)`",r"\1",text)
            doc.add_heading(text,level=len(hm.group(1))); i+=1; continue
        bm=re.match(r"^(\s*)[-*]\s+(.*)",line)
        if bm:
            p=doc.add_paragraph(style="List Bullet")
            p.paragraph_format.left_indent=Cm(0.4+len(bm.group(1))*0.3)
            p.paragraph_format.space_before=Pt(2); p.paragraph_format.space_after=Pt(2)
            add_inline(p,bm.group(2)); i+=1; continue
        nm=re.match(r"^(\s*)\d+\.\s+(.*)",line)
        if nm:
            p=doc.add_paragraph(style="List Number")
            p.paragraph_format.left_indent=Cm(0.4+len(nm.group(1))*0.3)
            p.paragraph_format.space_before=Pt(2); p.paragraph_format.space_after=Pt(2)
            add_inline(p,nm.group(2)); i+=1; continue
        if line.strip().startswith("*Source:") or line.strip().startswith("*Note:"):
            p=doc.add_paragraph(); p.paragraph_format.left_indent=Cm(0.6)
            p.paragraph_format.space_before=Pt(1); p.paragraph_format.space_after=Pt(4)
            add_inline(p,line.strip(),base_size=Pt(9),base_italic=True,base_colour=GRAY)
            i+=1; continue
        p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(3)
        p.paragraph_format.space_after=Pt(3); add_inline(p,line.strip()); i+=1
    if table_buf: flush_table(doc,table_buf)
    if in_code and code_buf: flush_code(doc,code_buf)
    doc.save(out); print(f"Saved → {out}")

convert(
    os.path.join(DOCS,"20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md"),
    os.path.join(DOCS,"20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.docx")
)
convert(
    os.path.join(DOCS,"20260701_FACULTY_SURVEY_AND_COLLABORATION_STRATEGY.md"),
    os.path.join(DOCS,"20260701_FACULTY_SURVEY_AND_COLLABORATION_STRATEGY.docx")
)
convert(
    os.path.join(DOCS,"20260701_PROPOSAL_ZHAO_COLLABORATION.md"),
    os.path.join(DOCS,"20260701_PROPOSAL_ZHAO_COLLABORATION.docx")
)
convert(
    os.path.join(DOCS,"20260701_PROPOSAL_ZHI_COLLABORATION.md"),
    os.path.join(DOCS,"20260701_PROPOSAL_ZHI_COLLABORATION.docx")
)
convert(
    os.path.join(DOCS,"20260701_TARGET_MODALITY_VALIDATION_AND_LLM_TRAINING_PLAN.md"),
    os.path.join(DOCS,"20260701_TARGET_MODALITY_VALIDATION_AND_LLM_TRAINING_PLAN.docx")
)
convert(
    os.path.join(DOCS,"20260701_BIOMATE_SYSTEM_VALIDATION_PLAN.md"),
    os.path.join(DOCS,"20260701_BIOMATE_SYSTEM_VALIDATION_PLAN.docx")
)
convert(
    os.path.join(DOCS,"20260701_BIOMATE_VALUE_AND_GOLD_STANDARDS.md"),
    os.path.join(DOCS,"20260701_BIOMATE_VALUE_AND_GOLD_STANDARDS.docx")
)
