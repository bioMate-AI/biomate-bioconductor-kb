import pathlib
CSS = """<style>
*{box-sizing:border-box} body{margin:0;background:#fff;font-family:'IBM Plex Sans',system-ui,sans-serif;color:#20293a}
#card{width:1120px;padding:26px 30px 30px}
.hd{font-family:'IBM Plex Mono',monospace;font-size:12px;letter-spacing:.09em;text-transform:uppercase;color:#1a4a9c;margin:0 0 4px}
.sub{font-size:13px;color:#5a6474;margin:0 0 16px}
table{width:100%;border-collapse:collapse;font-size:15px}
thead th{text-align:left;font-family:'IBM Plex Mono',monospace;font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:#5a6474;font-weight:500;padding:0 16px 9px 0;border-bottom:2px solid #d5dae2}
tbody td{padding:11px 16px 11px 0;border-bottom:1px solid #eef1f5;vertical-align:top}
tbody tr:last-child td{border-bottom:none}
.mono{font-family:'IBM Plex Mono',monospace;font-size:13.5px;color:#101828}
.wf{font-weight:600;color:#1a4a9c}
.pill{display:inline-block;font-family:'IBM Plex Mono',monospace;font-size:12px;padding:2px 8px;border-radius:4px;background:#eaf6ee;color:#1c6b3a}
.ft{font-family:'IBM Plex Mono',monospace;font-size:11px;color:#5a6474;margin-top:14px}
</style>"""
FONTS = '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet"/>'

t1 = f"""<!doctype html><html><head><meta charset="utf-8"/>{FONTS}{CSS}</head><body><div id="card">
<p class="hd">resolve_accession · stage 1 — identify the ID, pick the fetcher</p>
<p class="sub">Pure ID-type recognition. Paste an accession; BioMate names the archive and the fetch workflow — ready to run.</p>
<table><thead><tr><th>Accession</th><th>Recognized as</th><th>Fetch workflow</th></tr></thead><tbody>
<tr><td class="mono">GSE52778</td><td>GEO series</td><td class="wf">Geo Data Connector <span style="color:#5a6474">#10672</span></td></tr>
<tr><td class="mono">GSE2034</td><td>GEO series</td><td class="wf">Geo Data Connector <span style="color:#5a6474">#10672</span></td></tr>
<tr><td class="mono">GSE132044</td><td>GEO series</td><td class="wf">Geo Data Connector <span style="color:#5a6474">#10672</span></td></tr>
<tr><td class="mono">SRR1039508</td><td>SRA run</td><td class="wf">nf-core/fetchngs <span style="color:#5a6474">#12704</span></td></tr>
<tr><td class="mono">SRP033351</td><td>SRA project</td><td class="wf">nf-core/fetchngs <span style="color:#5a6474">#12704</span></td></tr>
</tbody></table>
<p class="ft">Live resolve_accession output · GEO → GEOquery connector · SRA/ENA/DDBJ → fetchngs (raw FASTQ)</p>
</div></body></html>"""

t2 = f"""<!doctype html><html><head><meta charset="utf-8"/>{FONTS}{CSS}</head><body><div id="card">
<p class="hd">stage 2 — same archive, your goal picks the pipeline</p>
<p class="sub">BioMate reads the study's own metadata for modality, then routes your stated goal — filling the modality parameters automatically.</p>
<table><thead><tr><th>Your goal</th><th>Routed workflow</th><th>Auto-filled</th></tr></thead><tbody>
<tr><td class="mono">GSE2034 · microarray breast cancer,<br/>DE good vs poor prognosis</td><td class="wf">Affymetrix microarray DE<br/><span style="color:#5a6474;font-weight:400">peca_microarray_affy</span></td><td><span class="pill">study_type = affy</span></td></tr>
<tr><td class="mono">GSE52778 · bulk RNA-seq DE,<br/>dexamethasone vs untreated</td><td class="wf">Chain: nf-core/rnaseq →<br/>differentialabundance (DESeq2) → GSEA</td><td><span class="pill">genome = GRCh38</span></td></tr>
<tr><td class="mono">GSE52778 · pathway enrichment /<br/>gene-set enrichment (GSEA)</td><td class="wf">Gene Set Enrichment Analysis<br/><span style="color:#5a6474;font-weight:400">fgsea + clusterProfiler · GO/KEGG/Reactome</span></td><td><span class="pill">species = Homo sapiens</span> <span class="pill">organism = hsa</span></td></tr>
</tbody></table>
<p class="ft">Live routing output · one GEO ID, three intents, three correctly-parameterized pipelines</p>
</div></body></html>"""
pathlib.Path(f"{__import__('sys').argv[1]}/acc_t1.html").write_text(t1)
pathlib.Path(f"{__import__('sys').argv[1]}/acc_t2.html").write_text(t2)
print("wrote acc_t1.html, acc_t2.html")
