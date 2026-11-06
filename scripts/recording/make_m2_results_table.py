import csv, html, pathlib
rows=[]
with open('reference/claude_design/tutorials/assets/live/_raw/deseq_results_top200.csv') as f:
    r=csv.reader(f); next(r)
    for i,row in enumerate(r):
        if i>=14: break
        gid=row[0]; base=float(row[1]); lfc=float(row[2]); padj=float(row[6])
        rows.append((gid, base, lfc, padj))
def fmt_padj(p):
    return f"{p:.1e}".replace("e-0","e-").replace("e+0","e+")
trs=""
for gid,base,lfc,padj in rows:
    up = lfc>=0
    col = "#1c6b3a" if up else "#9c1a2e"
    sign = "+" if up else ""
    trs+=f'<tr><td class="g">{html.escape(gid)}</td><td class="num">{base:,.0f}</td><td class="num" style="color:{col};font-weight:600">{sign}{lfc:.2f}</td><td class="num">{fmt_padj(padj)}</td></tr>\n'
doc=f"""<!doctype html><html><head><meta charset="utf-8"/>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet"/>
<style>
*{{box-sizing:border-box}}
body{{margin:0;padding:0;background:#fff;font-family:"IBM Plex Sans",system-ui,sans-serif;color:#20293a}}
#card{{width:1040px;padding:26px 30px 30px}}
.hd{{font-family:"IBM Plex Mono",monospace;font-size:12px;letter-spacing:.09em;text-transform:uppercase;color:#1a4a9c;margin:0 0 4px}}
.sub{{font-size:13px;color:#5a6474;margin:0 0 16px}}
table{{width:100%;border-collapse:collapse;font-size:15px}}
thead th{{text-align:left;font-family:"IBM Plex Mono",monospace;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#5a6474;font-weight:500;padding:0 14px 9px 0;border-bottom:2px solid #d5dae2}}
thead th.num{{text-align:right}}
tbody td{{padding:9px 14px 9px 0;border-bottom:1px solid #eef1f5}}
td.g{{font-family:"IBM Plex Mono",monospace;font-size:13.5px;color:#101828}}
td.num{{text-align:right;font-family:"IBM Plex Mono",monospace;font-size:13.5px}}
tbody tr:last-child td{{border-bottom:none}}
.ft{{font-family:"IBM Plex Mono",monospace;font-size:11px;color:#5a6474;margin-top:14px}}
</style></head><body>
<div id="card">
  <p class="hd">dex_vs_untreated · DESeq2 differential expression</p>
  <p class="sub">34,371 genes tested · 1,242 significant (padj &lt; 0.05, |FC| ≥ 2) · ranked by significance</p>
  <table>
    <thead><tr><th>Gene (Ensembl)</th><th class="num">Base mean</th><th class="num">log2 fold-change</th><th class="num">Adjusted p</th></tr></thead>
    <tbody>
{trs}    </tbody>
  </table>
  <p class="ft">Top 14 of 1,242 significant genes · green = up in dexamethasone, red = down · real BioMate run output</p>
</div></body></html>"""
pathlib.Path('/private/tmp/claude-501/-Users-kky-biomate-review/d5685fc4-f03c-4506-a590-c216050e0a4f/scratchpad/results_table.html').write_text(doc)
print("html written; rows:",len(rows))
