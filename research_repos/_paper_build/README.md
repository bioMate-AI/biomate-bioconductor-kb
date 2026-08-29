# Paper typesetting — elegant Nature-publication style (no LaTeX)

Converts the flagship and RealBio manuscripts (Markdown) into self-contained,
high-end HTML + PDF with custom vector figures and richly styled tables.
Pandoc + a Nature-style stylesheet + BeautifulSoup post-processing — **no TeX**.

## Build

```bash
cd research_repos/_paper_build
python3 build.py flagship      # -> out/flagship.html
python3 build.py realbio       # -> out/realbio.html
# PDF (headless Chrome):
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --no-pdf-header-footer \
  --print-to-pdf=out/flagship.pdf "file://$PWD/out/flagship.html"
```

Requires: `pandoc`, `python3` + `beautifulsoup4`, and (for PDF) Google Chrome.
Figure SVGs are previewed to PNG with `cairosvg` during design; the HTML embeds
them as **inline SVG** (vector, crisp at any zoom).

## What it produces

| File | |
|---|---|
| `nature.css` | The stylesheet — serif body, colored section heads, gradient-bordered abstract, teal-gradient table headers with zebra rows, GOLD/SILVER/BRONZE + PASS/ADVISORY/HALT keyword pills, numeric right-alignment. |
| `build.py` | pandoc → HTML, then: title/abstract styling, figures wrapped with captions (hero SVGs substituted for Figure 1, other figures base64-embedded), tables wrapped + color-coded. |
| `figures/fig1_architecture.svg` | Flagship **Figure 1** — the governed loop over the curated catalog. |
| `figures/fig_realbio_design.svg` | RealBio **Figure 1** — fairness-by-construction study design. |
| `out/flagship.{html,pdf}` · `out/realbio.{html,pdf}` | The typeset manuscripts. |

## Design system

One coherent visual language across both papers: petrol-teal primary
(`#0F6E7E`), evidence-grade palette (GOLD `#C79A2E` / SILVER `#8A97A3` /
BRONZE `#A9673C`), outcome colours (PASS green / ADVISORY amber / HALT red).
Custom figures are authored by hand as SVG for full control of layout and colour
rather than generated as matplotlib charts.
