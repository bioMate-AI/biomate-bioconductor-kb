/** Extract integration scores by COLUMN identity, never by numeric membership.
 * Metadata rows, missing cells and the aggregate Total are not interchangeable.
 */
import type { LegacyKeyResult } from '../shared/findings';
export interface EvidenceFile { name: string; content: string; }
export function integrationFindings(files: EvidenceFile[]) {
  const results: LegacyKeyResult[] = [];
  const caveats: string[] = [];
  const methods = new Set<string>();
  for (const file of files.filter(f => /^sizes\.tsv$/i.test(f.name))) {
    const lines = file.content.trimEnd().split(/\r?\n/);
    const header = lines[0]?.split('\t') || [];
    const total = header.indexOf('total');
    if (total < 1) continue;
    for (const line of lines.slice(1)) {
      const cells = line.split('\t');
      if (cells.length !== header.length || !cells[0] || cells.slice(1).some(v => !v.trim() || !/^\d+$/.test(v))) continue;
      if (Number(cells[total]) !== cells.slice(1).filter((_, index) => index + 1 !== total).reduce((sum, v) => sum + Number(v), 0)) continue;
      results.push({ metric: `${cells[0]} cells · total`, value: cells[total], source_file: file.name,
        interpretation: `Read from row “${cells[0]}”, column “total”.` });
    }
  }
  for (const file of files) {
    const lines = file.content.trimEnd().split(/\r?\n/);
    const header = lines[0]?.replace(/^\uFEFF/, '').split('\t');
    if (!header || new Set(header).size !== header.length || header[0] !== 'Embedding' || !header.includes('Bio conservation') || !header.includes('Batch correction') || !header.includes('Total')) {
      if (/_metrics\.tsv$/i.test(file.name)) return null;
      continue;
    }
    const firstResult = results.length;
    const method = file.name.replace(/_metrics\.tsv$/i, '');
    for (const line of lines.slice(1)) {
      const cells = line.split('\t');
      if (cells[0] === 'Metric Type') continue;
      if (!cells[0] || cells.length !== header.length) return null;
      const numeric = cells.slice(1).filter(v => v.trim() !== '');
      if (!numeric.length || numeric.some(v => !Number.isFinite(Number(v)))) return null;
      methods.add(method);
      for (let i = 1; i < header.length; i++) {
        const value = cells[i].trim();
        results.push({ metric: `${method} · ${cells[0]} · ${header[i]}`, value: value || 'Not reported',
          interpretation: `Read from column “${header[i]}”, embedding “${cells[0]}”.`, source_file: file.name, entity: method });
        if (!value) caveats.push(`${method} (${cells[0]}): ${header[i]} was not reported.`);
      }
    }
    if (results.length === firstResult) return null;
  }
  if (!methods.size) return null;
  // A deterministic extract replaces unverified cached narrative as a whole.
  // Merely changing a key-result value would leave wrong claims in its prose.
  const aggregates = results.filter(r => / · (Batch correction|Bio conservation|Total)$/.test(r.metric));
  const cells = results.find(r => r.metric === 'thresholded cells · total');
  return { status: 'ready', summary: (cells ? `The thresholded dataset contains ${cells.value} cells. ` : '') + `Saved integration metrics are available for ${methods.size} method${methods.size === 1 ? '' : 's'}: ${[...methods].join(', ')}. ` + aggregates.map(r => `${r.metric}: ${r.value}`).join('; ') + '.',
    key_results: results, caveats: [...caveats, 'Scores are reported from the saved tables; no quality verdict or biological interpretation has been inferred.'],
    next_steps: ['Review the source tables and biological annotations before choosing an integration method.'], evidence_version: 'integration-columns-v1' };
}
export function integrationFindingsMarkdown(data: NonNullable<ReturnType<typeof integrationFindings>>, workflow: string) {
  return [`# Findings — ${workflow}`, '', data.summary, '', '## Measurements', '',
    '| Metric | Value | Source |', '| --- | --- | --- |',
    ...data.key_results.map(r => `| ${r.metric.replace(/\|/g, '\\|')} | ${r.value} | ${r.source_file} |`),
    '', '## Caveats', '', ...data.caveats.map(c => `- ${c}`), ''].join('\n');
}
