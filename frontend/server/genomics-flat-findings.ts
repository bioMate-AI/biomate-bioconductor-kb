/**
 * Deterministic flat findings for DESeq2 / enrichGO / rare-disease tables.
 *
 * Descriptor → documentToLegacy already covers the happy path. These parsers
 * are the belt when matchDescriptor misses (filename / delimiter quirks) so
 * we never hand a parseable score table to the LLM as "context only".
 */

export interface EvidenceFile { name: string; content: string }

export type FlatParseResult = {
  context: string;
  numbers: Set<string>;
  findings: Record<string, any>;
};

export function parseDeseq2Findings(outputSamples: EvidenceFile[]): FlatParseResult | null {
  const f = outputSamples.find(s =>
    /deseq2|de_results|differential/i.test(s.name) ||
    (s.name.endsWith('.csv') && s.content.includes('log2FoldChange'))
  );
  if (!f) return null;
  const lines = f.content.split('\n').filter(l => l.trim());
  if (lines.length < 2) return null;
  // autodelim (audit S3#2): BioMate's own de_results.tsv is TAB; nf-core *_DESeq2_results.csv is
  // comma. The comma-only split returned null on a parseable TSV → EMPTY findings on a successful
  // DE run. Detect the delimiter from the header.
  const delim = lines[0].includes('\t') ? '\t' : ',';
  const header = lines[0].split(delim).map(h => h.replace(/"/g, '').trim());
  let geneIdx = header.findIndex(h => /^(gene|gene_id|geneid|gene\.name|name|symbol)$/i.test(h));
  const lfcIdx = header.findIndex(h => /log2fold/i.test(h) && !/se$/i.test(h));
  const padjIdx = header.findIndex(h => /^(padj|p\.adj|fdr|bh|q\.value)$/i.test(h));
  if (lfcIdx === -1 || padjIdx === -1) return null;
  // (audit S3#3) nf-core write.csv(row.names=TRUE) puts gene IDs in the UNLABELED first column
  // (header ""). Fall back to column 0 ONLY in that true row-name case — committee Opus-3: a blind
  // `geneIdx=0` mislabels genes with a numeric value when col 0 is numeric or IS the LFC/padj
  // column. When no gene column matches and col 0 isn't the row-name column, keep geneIdx=-1 and
  // emit honest synthetic gene_N rather than a number.
  if (geneIdx === -1 && header[0] === '' && lfcIdx !== 0 && padjIdx !== 0) geneIdx = 0;
  type Gene = {gene: string; lfc: number; padj: number};
  const genes: Gene[] = [];
  for (const line of lines.slice(1)) {
    const cols = line.split(delim).map(c => c.replace(/"/g, '').trim());
    const lfc = parseFloat(cols[lfcIdx]);
    const padj = parseFloat(cols[padjIdx]);
    if (isNaN(lfc) || isNaN(padj)) continue;
    genes.push({ gene: (geneIdx >= 0 && cols[geneIdx]) ? cols[geneIdx] : `gene_${genes.length + 1}`, lfc, padj });
  }
  const sig = genes.filter(g => g.padj < 0.05);
  const nUp = sig.filter(g => g.lfc > 0).length;
  const nDown = sig.filter(g => g.lfc < 0).length;
  const topUp = [...sig].sort((a, b) => b.lfc - a.lfc).slice(0, 8);
  const topDown = [...sig].sort((a, b) => a.lfc - b.lfc).slice(0, 8);
  const fmt = (n: number) => n.toFixed(2);
  const fmtP = (n: number) => n < 0.001 ? n.toExponential(1) : n.toFixed(3);
  const contextLines = [
    `### DESeq2 Differential Expression Results`,
    `Total genes tested: ${genes.length}`,
    `Significant at padj < 0.05: ${sig.length} (${nUp} up, ${nDown} down)`,
    ``, `Top upregulated genes:`,
    ...topUp.map(g => `  ${g.gene}: LFC=${fmt(g.lfc)}, padj=${fmtP(g.padj)}`),
    ``, `Top downregulated genes:`,
    ...topDown.map(g => `  ${g.gene}: LFC=${fmt(g.lfc)}, padj=${fmtP(g.padj)}`),
    ``, `Source file: ${f.name}`,
  ];
  const numbers = new Set<string>([String(sig.length), String(genes.length)]);
  for (const g of [...topUp, ...topDown]) { numbers.add(fmt(g.lfc)); numbers.add(fmtP(g.padj)); }
  // Flat findings even when matchDescriptor misses — same class as cryo/MultiQC:
  // never hand a parseable DE table to the LLM just because the descriptor didn't fire.
  const topHits = [...sig].sort((a, b) => a.padj - b.padj).slice(0, 8);
  const key_results: Array<{ metric: string; value: string; interpretation: string; source_file?: string; entity?: string }> = [
    { metric: 'Significant genes (padj<0.05)', value: String(sig.length), interpretation: `${nUp} up / ${nDown} down of ${genes.length} tested`, source_file: f.name },
    ...topHits.map(g => ({
      metric: 'log2FoldChange',
      value: fmt(g.lfc),
      interpretation: `padj=${fmtP(g.padj)}`,
      source_file: f.name,
      entity: g.gene,
    })),
  ];
  const summary = `DESeq2: ${sig.length} genes at padj<0.05 (${nUp} up, ${nDown} down). Top hits: ${
    topHits.slice(0, 5).map(g => `${g.gene.slice(0, 24)} (LFC=${fmt(g.lfc)}, padj=${fmtP(g.padj)})`).join('; ') || 'none'
  }. Read the Key Results table (from ${f.name}); full tables remain in Outputs.`;
  return {
    context: contextLines.join('\n'),
    numbers,
    findings: {
      summary,
      key_results,
      next_steps: sig.length
        ? ['Run pathway enrichment (enrichGO / GSEA) on the significant gene set.', 'Open the full DE table in Outputs for genome-wide results.']
        : ['No genes passed padj<0.05 — check design contrasts and sample QC in Outputs.'],
      caveats: ['Significance thresholds (padj<0.05) are conventional — confirm with your study design before publication.'],
      evidence_version: 'deseq2-flat-v1',
    },
  };
}

export function parseEnrichGoFindings(outputSamples: EvidenceFile[]): FlatParseResult | null {
  const f = outputSamples.find(s =>
    /enrichgo|enrich_go|go_enrich|clusterprofiler|gsea|pathway/i.test(s.name) ||
    (/\.(csv|tsv|txt)$/i.test(s.name) && (s.content.includes('p.adjust') || s.content.includes('GeneRatio')))
  );
  if (!f) return null;
  const lines = f.content.split('\n').filter(l => l.trim());
  if (lines.length < 2) return null;
  // Same autodelim as DESeq2 — clusterProfiler often writes TSV; comma-only
  // split returned null on parseable enrichment tables → LLM fluff.
  const delim = lines[0].includes('\t') ? '\t' : ',';
  const header = lines[0].split(delim).map(h => h.replace(/"/g, '').trim());
  const descIdx = header.findIndex(h => /^(description|term|pathway|name)$/i.test(h));
  const padjIdx = header.findIndex(h => /^(p\.adjust|padj|fdr|qvalue)$/i.test(h));
  const ratioIdx = header.findIndex(h => /^(generatio|gene_ratio|ratio)$/i.test(h));
  const countIdx = header.findIndex(h => /^(count|gene_count)$/i.test(h));
  if (descIdx === -1 || padjIdx === -1) return null;
  type Term = {desc: string; padj: number; ratio: string; count: string};
  const terms: Term[] = [];
  for (const line of lines.slice(1)) {
    const cols = line.split(delim).map(c => c.replace(/"/g, '').trim());
    const padj = parseFloat(cols[padjIdx]);
    if (isNaN(padj)) continue;
    terms.push({ desc: cols[descIdx] || '', padj, ratio: ratioIdx >= 0 ? cols[ratioIdx] : '', count: countIdx >= 0 ? cols[countIdx] : '' });
  }
  terms.sort((a, b) => a.padj - b.padj);
  const sig = terms.filter(t => t.padj < 0.05);
  const top12 = terms.slice(0, 12);
  const fmtP = (n: number) => n < 0.001 ? n.toExponential(2) : n.toFixed(4);
  const contextLines = [
    `### Gene Ontology / Pathway Enrichment Results`,
    `Significantly enriched terms (p.adjust < 0.05): ${sig.length}`,
    ``, `Top enriched terms:`,
    ...top12.map(t => {
      const extras = [t.ratio && `GeneRatio=${t.ratio}`, t.count && `Count=${t.count}`].filter(Boolean);
      return `  ${t.desc}: p.adj=${fmtP(t.padj)}${extras.length ? `, ${extras.join(', ')}` : ''}`;
    }),
    ``, `Source file: ${f.name}`,
  ];
  const numbers = new Set<string>([String(sig.length)]);
  for (const t of top12) numbers.add(fmtP(t.padj));
  const key_results = [
    { metric: 'Enriched terms (p.adjust<0.05)', value: String(sig.length), interpretation: `${terms.length} terms in sampled table`, source_file: f.name },
    ...top12.slice(0, 8).map(t => ({
      metric: 'p.adjust',
      value: fmtP(t.padj),
      interpretation: [t.ratio && `GeneRatio=${t.ratio}`, t.count && `Count=${t.count}`].filter(Boolean).join(', ') || 'enriched term',
      source_file: f.name,
      entity: t.desc.slice(0, 64),
    })),
  ];
  const summary = `Pathway enrichment: ${sig.length} significant term(s) at p.adjust<0.05. Top: ${
    top12.slice(0, 5).map(t => `${t.desc.slice(0, 48)} (padj=${fmtP(t.padj)})`).join('; ') || 'none'
  }. Key Results table sourced from ${f.name}.`;
  return {
    context: contextLines.join('\n'),
    numbers,
    findings: {
      summary,
      key_results,
      next_steps: ['Cross-check top terms against the DE gene list; export pathway plots from Outputs.'],
      caveats: ['Significance thresholds (padj<0.05) are conventional — confirm with your study design before publication.'],
      evidence_version: 'enrichgo-flat-v1',
    },
  };
}

export function parseRarediseaseFindings(outputSamples: EvidenceFile[]): FlatParseResult | null {
  const f = outputSamples.find(s =>
    /variant|annotated|vep|snpeff|filtered/i.test(s.name) && /\.(tsv|txt|csv|vcf)$/i.test(s.name)
  );
  if (!f) return null;
  const lines = f.content.split('\n').filter(l => l.trim() && !l.startsWith('##'));
  if (lines.length < 2) return null;
  // autodelim: annotated VEP/SnpEff tables are usually TSV; some exporters write CSV.
  // Filename alone is unreliable (.txt/.vcf/.tsv mix).
  const sep = lines[0].includes('\t') ? '\t' : ',';
  const header = lines[0].split(sep).map(h => h.replace(/^#/, '').trim());
  const geneIdx = header.findIndex(h => /gene|gene\.refgene|symbol/i.test(h));
  const impactIdx = header.findIndex(h => /^(impact|severity)$/i.test(h));
  const funcIdx = header.findIndex(h => /func|consequence|exonicfunc/i.test(h));
  if (geneIdx === -1 && impactIdx === -1) return null;
  type Variant = {gene: string; impact: string; func: string};
  // (audit S3#5) Parse ALL rows and count by impact over the full set. The old
  // `slice(1,201)` with no impact-sort hid HIGH-impact (candidate causal) variants beyond
  // row 200 and undercounted — in a position-sorted table the diagnostic variant can be lost.
  const variants: Variant[] = lines.slice(1).map(line => {
    const cols = line.split(sep);
    return { gene: geneIdx >= 0 ? cols[geneIdx] : '', impact: impactIdx >= 0 ? cols[impactIdx] : '', func: funcIdx >= 0 ? cols[funcIdx] : '' };
  });
  // (audit S3#4) MODIFIER must NOT be counted as MODERATE — `/mod/` is a substring of
  // "MODIFIER" (usually the majority of variants). Match each category exactly.
  const high = variants.filter(v => /^high$/i.test(v.impact.trim()));
  const mod = variants.filter(v => /^moderate$/i.test(v.impact.trim()));
  const low = variants.filter(v => /^low$/i.test(v.impact.trim()));
  const modifier = variants.filter(v => /^modifier$/i.test(v.impact.trim()));
  const contextLines = [
    `### Rare Disease Variant Analysis`,
    // committee Opus-1: counts are over the SAMPLED output (parser now reads up to ~1MB — most
    // annotated tables fit, but a very large table is still sampled), so label them "sampled" and
    // do NOT whitelist the total as an authoritative "variants analyzed" count for the LLM narrative.
    `Variants in sampled output: ${variants.length}`,
    `HIGH impact (sampled): ${high.length}`,
    `MODERATE impact (sampled): ${mod.length}`,
    `LOW impact (sampled): ${low.length}`,
    `MODIFIER (sampled): ${modifier.length}`,
    ...(high.length > 0 ? [``, `HIGH impact (sampled):`, ...high.slice(0, 5).map(v => `  ${v.gene}: ${v.func || 'unknown'}`)] : []),
    ...(mod.length > 0 ? [``, `MODERATE impact (sampled, top 5):`, ...mod.slice(0, 5).map(v => `  ${v.gene}: ${v.func || 'unknown'}`)] : []),
    ``, `Source file: ${f.name}`,
  ];
  const numbers = new Set<string>([String(high.length), String(mod.length), String(low.length), String(modifier.length)]);
  const highGenes = [...new Set(high.map(v => v.gene).filter(Boolean))].slice(0, 5);
  const key_results = [
    { metric: 'HIGH impact (sampled)', value: String(high.length), interpretation: high.length ? 'prioritize for clinical interpretation' : 'none in sample', source_file: f.name },
    { metric: 'MODERATE impact (sampled)', value: String(mod.length), interpretation: 'review after HIGH', source_file: f.name },
    { metric: 'Variants in sampled output', value: String(variants.length), interpretation: `LOW=${low.length}, MODIFIER=${modifier.length}`, source_file: f.name },
    ...high.slice(0, 5).map(v => ({
      metric: 'IMPACT',
      value: 'HIGH',
      interpretation: v.func || 'high-impact variant',
      source_file: f.name,
      entity: v.gene || undefined,
    })),
  ];
  const summary = `Variant annotation: ${variants.length} variants in sample (${high.length} HIGH, ${mod.length} MODERATE).${
    highGenes.length ? ` HIGH-impact genes: ${highGenes.join(', ')}.` : ''
  } Key Results from ${f.name}.`;
  return {
    context: contextLines.join('\n'),
    numbers,
    findings: {
      summary,
      key_results,
      next_steps: high.length
        ? ['Prioritize HIGH-impact variants for clinical interpretation; open the full VCF/TSV in Outputs.']
        : ['No HIGH-impact variants in the sampled table — broaden filters or inspect MODERATE calls in Outputs.'],
      caveats: ['Counts are over the sampled output table (≤~1MB), not a guaranteed genome-wide total.'],
      evidence_version: 'raredisease-flat-v1',
    },
  };
}

