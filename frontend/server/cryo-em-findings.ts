/**
 * Deterministic findings for cryo-EM / CryoSPARC SPA runs.
 *
 * Score cards live across many step reports (motion → pick → extract → FSC →
 * workflow_summary). The LLM path narrates pipeline bookkeeping and often
 * omits FSC / particle counts that Outputs already list. Rule-first: assemble
 * Key Results from those JSONs; return null only when nothing quantitative
 * is present.
 */
export interface EvidenceFile { name: string; content: string }

export interface CryoEmFindings {
  summary: string;
  key_results: Array<{
    metric: string;
    value: string;
    interpretation: string;
    source_file: string;
  }>;
  next_steps: string[];
  caveats: string[];
  evidence_version: 'cryo-em-metrics-v1';
}

function parseJson(file: EvidenceFile | undefined): Record<string, any> | null {
  if (!file) return null;
  try {
    const j = JSON.parse(file.content);
    return j && typeof j === 'object' ? j : null;
  } catch { return null; }
}

function findByName(files: EvidenceFile[], re: RegExp): EvidenceFile | undefined {
  return files.find(f => re.test(f.name));
}

function fmt(n: number): string {
  if (!Number.isFinite(n)) return String(n);
  if (Number.isInteger(n) || Math.abs(n) >= 100) return String(Math.round(n));
  return (Math.round(n * 1000) / 1000).toString();
}

function num(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Prefer a positive particle count; skip zeros that mean "not captured". */
function positiveCount(v: unknown): number | null {
  const n = num(v);
  return n != null && n > 0 ? n : null;
}

/**
 * Build cryo-EM findings from sampled report JSONs.
 * Returns null when no quantitative scores can be read (caller falls through to LLM).
 */
export function parseCryoEmFindings(
  files: EvidenceFile[],
  workflowName = 'cryo-EM',
): CryoEmFindings | null {
  const rows: CryoEmFindings['key_results'] = [];
  const push = (metric: string, value: string, interpretation: string, source_file: string) => {
    rows.push({ metric, value, interpretation, source_file });
  };

  const fscFile = findByName(files, /fsc_validation\.json$/i);
  const fsc = parseJson(fscFile);
  const fscRes = num(fsc?.fsc_0143_resolution ?? fsc?.resolution_A ?? fsc?.fsc_resolution);
  if (fscFile && fscRes != null && fscRes > 0) {
    push('FSC 0.143 resolution', `${fmt(fscRes)} Å`, 'Gold-standard FSC resolution (0.143 criterion)', fscFile.name);
  }

  const summaryFile = findByName(files, /workflow_summary\.json$/i);
  const summary = parseJson(summaryFile);
  if (summaryFile && summary) {
    const px = num(summary.pixel_size_angstroms ?? summary.pixel_size);
    const kv = num(summary.voltage_kv ?? summary.voltage);
    const steps = num(summary.steps_completed);
    if (px != null) push('pixel size', `${fmt(px)} Å/px`, 'Acquisition pixel size', summaryFile.name);
    if (kv != null) push('voltage', `${fmt(kv)} kV`, 'Microscope voltage', summaryFile.name);
    if (summary.symmetry) push('symmetry', String(summary.symmetry), 'Imposed symmetry', summaryFile.name);
    if (steps != null) push('steps completed', fmt(steps), 'Pipeline steps finished', summaryFile.name);
  }

  const motionFile = findByName(files, /motion_report/i);
  const motion = parseJson(motionFile);
  const nMics = positiveCount(motion?.num_micrographs);
  if (motionFile && nMics != null) {
    push('micrographs', fmt(nMics), 'Motion-corrected micrographs', motionFile.name);
  }

  const pickFile = findByName(files, /picking_report|template_pick_report/i);
  const pick = parseJson(pickFile);
  const nPick = positiveCount(pick?.num_particles);
  if (pickFile && nPick != null) {
    push('particles picked', fmt(nPick), 'Particles from picker', pickFile.name);
  }

  const extractR2 = findByName(files, /(^|\/)extract_report\.json$/i)
    || findByName(files, /extract_report(?!_batch)/i);
  const extract = parseJson(extractR2);
  const nExt = positiveCount(extract?.num_particles);
  if (extractR2 && nExt != null) {
    push('particles extracted (R2)', fmt(nExt), 'Particles after round-2 extraction', extractR2.name);
    const box = num(extract?.box_size_pix);
    if (box != null) push('box size', `${fmt(box)} px`, 'Extraction box size', extractR2.name);
  }

  const nuFile = findByName(files, /nu_refinement_report/i);
  const nu = parseJson(nuFile);
  const nNu = positiveCount(nu?.num_particles);
  if (nuFile && nNu != null) {
    push('particles in NU refinement', fmt(nNu), 'Particles in non-uniform refinement', nuFile.name);
  }

  // Nothing quantitative → let LLM / other paths try.
  if (rows.length === 0) return null;

  const fscRow = rows.find(r => /fsc/i.test(r.metric));
  const pickRow = rows.find(r => /picked/i.test(r.metric));
  const extRow = rows.find(r => /extracted/i.test(r.metric));
  const bits = [
    fscRow ? `FSC 0.143=${fscRow.value}` : null,
    pickRow ? `picked=${pickRow.value}` : null,
    extRow ? `extracted=${extRow.value}` : null,
    nMics != null ? `micrographs=${fmt(nMics)}` : null,
  ].filter(Boolean);

  const next: string[] = [];
  if (fscRow) {
    next.push('Open the sharpened map and local-resolution volume in Outputs; inspect FSC curve before deposition.');
  } else {
    next.push('FSC resolution was not in sampled reports — open fsc_validation.json / NU refinement outputs when available.');
  }
  if (extRow || pickRow) {
    next.push('If resolution is limited, increase particles (Topaz / more micrographs) or try local refinement.');
  }

  return {
    summary: `${workflowName || 'cryo-EM'} finished. Key scores: ${bits.join('; ') || rows.slice(0, 3).map(r => `${r.metric}=${r.value}`).join('; ')}. Read the Key Results table below; full step reports remain in Outputs.`,
    key_results: rows,
    next_steps: next,
    caveats: [
      'Particle counts of 0 in some step reports mean "not captured", not zero yield — prefer positive counts from upstream steps.',
      'FSC 0.143 is gold-standard resolution when present; confirm on the FSC curve in Outputs before claiming Å resolution.',
    ],
    evidence_version: 'cryo-em-metrics-v1',
  };
}
