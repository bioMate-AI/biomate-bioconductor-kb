#!/usr/bin/env python3
"""Build an elegant, self-contained Nature-style HTML from a manuscript .md.
pandoc -> bs4 post-processing (title/abstract, figures w/ inline hero SVG,
color-coded tables). No LaTeX. Usage: build.py <config-key>."""
import base64, re, subprocess, sys, os
from pathlib import Path
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[2]          # repo root
BUILD = Path(__file__).resolve().parent
CSS = (BUILD / "nature.css").read_text()

CONFIGS = {
  "flagship": dict(
    md = ROOT/"research_repos/flagship_paper/manuscript/MANUSCRIPT_DRAFT.md",
    imgdir = ROOT/"docs/figures/c1",   # relative image base (../../../docs/figures/c1)
    hero = {"Figure 1": BUILD/"figures/fig1_architecture.svg"},
    kicker = "BioMate · Systems paper",
    out = BUILD/"out/flagship.html"),
  "realbio": dict(
    md = ROOT/"docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md",
    imgdir = ROOT/"docs",              # relative image base (figures/realbio/..)
    hero = {"Figure 1": BUILD/"figures/fig_realbio_design.svg"},
    kicker = "RealBio · Open benchmark",
    out = BUILD/"out/realbio.html"),
}

PILL = [("GOLD","g-gold"),("SILVER","g-silver"),("BRONZE","g-bronze"),
        ("PASS","o-pass"),("ADVISORY","o-adv"),("HALT","o-halt")]

def md_to_html(md):
    r = subprocess.run(["pandoc","-f","gfm","-t","html","--no-highlight"],
                       input=md, capture_output=True, text=True)
    if r.returncode: sys.exit("pandoc failed: "+r.stderr)
    return r.stdout

def embed_img(src, imgdir):
    """Return a data: URI for a local image path, or None."""
    p = (imgdir / re.sub(r'^(\.\./)+','',src)).resolve()
    if not p.exists():
        # try resolving as given, relative to imgdir directly
        p = (imgdir / src).resolve()
    if not p.exists(): return None
    mime = "image/png" if p.suffix.lower()==".png" else "image/jpeg"
    return f"data:{mime};base64,"+base64.b64encode(p.read_bytes()).decode()

def colorize_cell(td):
    # wrap standalone grade/outcome tokens in pills; right-align numeric cells
    html = td.decode_contents()
    for tok,cls in PILL:
        html = re.sub(rf'(?<![A-Za-z])({tok})(?![A-Za-z])',
                      rf'<span class="pill {cls}">\1</span>', html)
    td.clear(); td.append(BeautifulSoup(html,"html.parser"))
    txt = td.get_text().strip()
    if re.fullmatch(r'[\d.,%×\[\]\s±–\-−<>=~≈]+', txt) and any(c.isdigit() for c in txt):
        td["class"] = td.get("class",[]) + ["num"]

def build(key):
    cfg = CONFIGS[key]
    md = cfg["md"].read_text()
    # --- split front matter (title + authors) from body ---
    lines = md.splitlines()
    title = next((l[2:].strip() for l in lines if l.startswith("# ")), key)
    # body = everything from the first "## " onward
    bstart = next(i for i,l in enumerate(lines) if l.startswith("## "))
    front = "\n".join(lines[1:bstart])            # authors / affil block (skip title)
    body_md = "\n".join(lines[bstart:])
    front_html = md_to_html(re.sub(r'^##\s+Authors\s*$','',front,flags=re.M))
    soup = BeautifulSoup(md_to_html(body_md), "html.parser")

    # --- ABSTRACT: wrap the Abstract h2 + siblings until next h2 ---
    for h2 in soup.find_all("h2"):
        if h2.get_text().strip().lower().startswith("abstract"):
            box = soup.new_tag("div"); box["class"]="abstract"
            sib = h2.next_sibling; h2.extract()
            nodes=[]
            while sib and not (getattr(sib,"name",None)=="h2"):
                nxt = sib.next_sibling; nodes.append(sib.extract() if hasattr(sib,'extract') else sib); sib=nxt
            for n in nodes: box.append(n)
            soup.insert(0, box)
            break

    # --- FIGURES: wrap imgs, embed/replace, attach captions ---
    for img in soup.find_all("img"):
        p = img.find_parent("p") or img.parent
        alt = img.get("alt","")
        fignum = re.match(r'(Figure\s+\d+)', alt)
        fig = soup.new_tag("figure")
        # hero SVG replacement?
        replaced=False
        for label,svgpath in cfg["hero"].items():
            if (fignum and fignum.group(1)==label) or alt.startswith(label):
                svg = BeautifulSoup(Path(svgpath).read_text(),"html.parser").find("svg")
                svg["style"]="width:100%;height:auto"
                fig.append(svg); replaced=True; break
        if not replaced:
            uri = embed_img(img.get("src",""), cfg["imgdir"])
            newimg = soup.new_tag("img")
            if uri: newimg["src"]=uri
            else:   newimg["src"]=img.get("src","")   # leave path if missing
            fig.append(newimg)
        p.replace_with(fig)
        # caption: next <p> beginning with bold "Figure N |", else the alt text
        cap = soup.new_tag("figcaption")
        nxt = fig.find_next_sibling()
        if nxt and nxt.name=="p" and nxt.find("strong") and nxt.get_text().strip().startswith("Figure"):
            lab = nxt.find("strong")
            labspan = soup.new_tag("span"); labspan["class"]="lab"; labspan.string=lab.get_text()
            lab.replace_with(labspan)
            cap.append(BeautifulSoup(nxt.decode_contents(),"html.parser")); nxt.extract()
        elif alt:
            m=re.match(r'(Figure\s+\d+[.:])\s*(.*)',alt,re.S)
            if m:
                labspan=soup.new_tag("span"); labspan["class"]="lab"; labspan.string=m.group(1)
                cap.append(labspan); cap.append(" "+m.group(2))
            else: cap.append(alt)
        fig.append(cap)

    # --- TABLES: wrap + colorize ---
    for tbl in soup.find_all("table"):
        for td in tbl.find_all("td"): colorize_cell(td)
        wrap = soup.new_tag("div"); wrap["class"]="tbl-wrap"
        tbl.replace_with(wrap); wrap.append(tbl)

    # --- number-superscript refs already unicode; leave as-is ---
    out = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>{CSS}</style></head>
<body><div class="topbar"></div><div class="paper">
<div class="kicker">{cfg['kicker']}</div>
<h1 class="title">{title}</h1>
<div class="frontmatter">{front_html}</div>
{str(soup)}
<div class="foot">Typeset from Markdown · BioMate manuscript build · figures are vector SVG · self-contained HTML.</div>
</div></body></html>"""
    cfg["out"].parent.mkdir(parents=True, exist_ok=True)
    cfg["out"].write_text(out)
    print(f"wrote {cfg['out']}  ({len(out)//1024} KB)")

if __name__=="__main__":
    build(sys.argv[1] if len(sys.argv)>1 else "flagship")
