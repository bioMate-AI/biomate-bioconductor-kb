/** Pure boundary contracts for scientific chat tools. No scoring or synthesis here. */
type RecordValue = Record<string, any>;
const object = (v: unknown): v is RecordValue => !!v && typeof v === 'object' && !Array.isArray(v);

export function scientificToolRequest(input: unknown, kind: 'targets' | 'review'): RecordValue {
  if (!object(input) || typeof input.query !== 'string' || !input.query.trim()) {
    throw new Error('query must be a non-empty string');
  }
  const query = input.query.trim();
  if (kind === 'review') return {
    query, context: { information_need: 'literature_review' },
    include_citations: true, include_benchmark_evidence: true,
  };
  let topK = input.top_k ?? 25;
  if (typeof topK !== 'number' || !Number.isInteger(topK) || topK < 1) {
    throw new Error('top_k must be a positive integer');
  }
  topK = Math.min(topK, 100);
  if (input.disease_id != null && (typeof input.disease_id !== 'string' || !/^(?:EFO|MONDO)_\d+$/.test(input.disease_id.trim()))) {
    throw new Error('disease_id must be an EFO/MONDO identifier; omit it if unknown');
  }
  if (input.disease != null && (typeof input.disease !== 'string' || !input.disease.trim() || input.disease.trim().length > 300)) {
    throw new Error('disease must be a non-empty name of at most 300 characters');
  }
  if (input.candidate_targets != null && (!Array.isArray(input.candidate_targets) || input.candidate_targets.some((v: unknown) => typeof v !== 'string' || !v.trim()))) {
    throw new Error('candidate_targets must contain non-empty gene symbols');
  }
  const candidates = input.candidate_targets == null ? null : [...new Set(input.candidate_targets.map((v: string) => v.trim().toUpperCase()))];
  if (input.ranking_mode != null && !['auto', 'integrated'].includes(input.ranking_mode)) {
    throw new Error("ranking_mode must be 'auto' or 'integrated'");
  }
  for (const flag of ['validate', 'suggest_modality'] as const) {
    if (input[flag] != null && typeof input[flag] !== 'boolean') throw new Error(`${flag} must be a boolean`);
  }
  return {
    query, disease_id: input.disease_id?.trim() || null, candidate_targets: candidates?.length ? candidates : null, top_k: topK,
    ...(input.disease ? { disease: input.disease.trim() } : {}),
    ...(input.ranking_mode ? {ranking_mode: input.ranking_mode} : {}),
    ...(input.validate === true ? {validate: true} : {}),
    ...(input.suggest_modality === true ? {suggest_modality: true} : {}),
  };
}

export function scientificToolResult(data: unknown, kind: 'targets' | 'review', query: string): RecordValue {
  if (!object(data)) return {error: 'Scientific backend returned an invalid response', query};
  if (data.success === false || data.error) return {error: data.error || 'Scientific backend reported failure', query};
  if (kind === 'targets') {
    if (/disease .* did not resolve/i.test(String(data.channel_errors?.genetics_ot || ''))) {
      return { error: 'The disease identifier did not resolve in Open Targets. Retry identify_targets with the full disease name in disease; do not guess another identifier.', query };
    }
    if (!Array.isArray(data.targets) || data.targets.some((t: unknown) => !object(t) || typeof t.target !== 'string' || !t.target.trim() || !Number.isFinite(t.score) || !Number.isInteger(t.rank) || t.rank < 1 || typeof t.tier !== 'string')) {
      return {error: 'Target backend returned an invalid ranked-target list', query};
    }
    const ranking = object(data.ranking) ? data.ranking : null;
    const primary = ranking?.mode === 'primary_channel' && ranking?.primary_channel === 'genetics_ot';
    const provenance = object(data.channel_provenance) ? {...data.channel_provenance} : data.channel_provenance;
    if (object(provenance?.genetics_ot)) {
      const {n, ...source} = provenance.genetics_ot;
      provenance.genetics_ot = {...source, ...(n == null ? {} : {n_targets_retrieved:n})};
    }
    return {
      query, status: data.targets.length ? 'ok' : 'no_evidence',
      arbiter: data.arbiter, ranking, channels_run: data.channels_run,
      ...(data.disease_resolution ? { disease_resolution: data.disease_resolution } : {}),
      channel_errors: data.channel_errors, channel_provenance: provenance,
      n_targets_total: data.n_targets_total ?? data.targets.length,
      targets: data.targets,
      ...(data.validation_plan ? {validation_plan: data.validation_plan} : {}),
      ...(data.modality_suggestions ? {
        modality_suggestions: data.modality_suggestions,
        modality_note: 'Drug-type suggestions are guidance only and NOT validated: on approved-drug precedent the rule barely beats always answering small molecule, and misses most biologics. State this when presenting them.',
      } : {}),
      note: (primary
        ? 'Order follows OpenTargets association scores; other channels provide corroboration/conflict, not improved ranking. '
        : 'OpenTargets-primary ordering was NOT established for this result. Report the returned ranking mode and available channels; do not imply OpenTargets evidence when unavailable. ') +
        'No superiority over OpenTargets is established. Scores are not clinical probabilities. ' +
        'Report tiers, failed channels and conflicts faithfully. Legacy per_channel_z values are normalized scores for harmonic_sum, not z-scores. ' +
        'genetics_ot is a legacy name for aggregated OpenTargets disease-association evidence, not genetics-only evidence. ' +
        'n_targets_retrieved counts target records, NOT patients or cohort size. ' +
        'LLM-reasoned output is neither a retrieved publication nor independent experimental/literature corroboration; the corroborated tier means channel agreement only. ' +
        'Do not add biological prevalence, mechanistic explanations or clinical claims unless separately supported by retrieved sources. Use literature retrieval if that support is needed.',
    };
  }
  if (data.success !== true || typeof data.answer !== 'string' || !data.answer.trim() || !Array.isArray(data.citations) || data.citations.some((c: unknown) => !object(c) || typeof c.title !== 'string' || !c.title.trim())) {
    return {error: 'Research backend did not return a valid answer and citation list', query};
  }
  const missing = [...data.answer.matchAll(/\[(\d+)\]/g)].some(m => Number(m[1]) < 1 || Number(m[1]) > data.citations.length);
  if (missing) return {error: 'Research answer contains a citation marker without a returned reference', query};
  return {
    query, status: data.citations.length ? 'ok' : 'uncited', answer: data.answer,
    // Never slice/reorder citations: [N] references the backend's exact list.
    citations: data.citations, confidence: data.confidence ?? null,
    follow_up_questions: data.follow_up_questions, source: data.source,
    retrieval: data.retrieval, conflicts: data.conflicts, methods_used: data.methods_used,
    benchmark_evidence: data.benchmark_evidence,
    // The synthesis model's verdict on whether the retrieved papers answer the question; the chat
    // guard keeps an uncited answer instead of a "literature does not contain" reply when false.
    evidence_answers_question: data.evidence_answers_question ?? null,
    note: data.citations.length
      ? 'Preserve the answer/reference numbering and source disagreements. Cite only returned references; do not invent DOI/PMID. Low confidence and retrieval limitations must be stated.'
      : 'No literature citations were returned. This is not a literature-backed review; disclose the source/fallback and do not invent references.',
  };
}
/** A completed ranking is authoritative; a prefetched survey cannot deny its execution. */
export function targetEvidenceReply(result: any): string {
  if (result?.status !== 'ok' || !Array.isArray(result.targets) || !result.targets.length) {
    throw new Error('No successful target evidence to present');
  }
  const text = (v: unknown) => String(v ?? '').replace(/[|\r\n]/g, ' ');
  const rows = result.targets.map((t: any) => `| ${text(t.rank)} | ${text(t.target)} | ${text(t.score)} | ${text(t.tier)} | ${t.conflict ? 'Yes' : 'No'} |`);
  const primary = result.ranking?.mode === 'primary_channel' ? result.ranking.primary_channel : null;
  const errors = Object.keys(result.channel_errors || {});
  const channels = Array.isArray(result.channels_run) ? result.channels_run : [];
  const available = channels.filter((name: string) => !errors.includes(name));
  const reasoningOnly = available.length > 0 && available.every((name: string) => name === 'llm_reasoned');
  const headline = reasoningOnly
    ? 'Target hypotheses generated from AI reasoning only. External evidence was not verified.'
    : !available.length
      ? 'Target ranking returned without verified channel provenance.'
      : errors.length
        ? 'Target ranking completed with incomplete evidence.'
        : 'Target identification completed successfully.';
  const channel = (value: string) => ({genetics_ot:'Open Targets disease-association evidence',llm_reasoned:'AI-generated reasoning'}[value] || text(value));
  // SHOW the evidence, don't just score it: for each target, surface which channels contributed
  // (per_channel_z) and the per-target note. Without this the reply hid the Open Targets
  // disease-association evidence behind a bare score — the whole point of an "evidence" question.
  const evLines = result.targets.map((t: any) => {
    const pc = (t.per_channel_z && typeof t.per_channel_z === 'object') ? t.per_channel_z as Record<string, unknown> : {};
    const chans = Object.entries(pc)
      .filter(([, v]) => v != null && v !== '')
      .map(([k, v]) => `${channel(k)} ${text(v)}`);
    const links = (t.evidence_links && typeof t.evidence_links === 'object')
      ? Object.values(t.evidence_links as Record<string, any>).map((l: any) => text(l?.label)).filter(Boolean)
      : [];
    const parts = [chans.length ? chans.join(' · ') : null, t.note ? text(t.note) : null, links.length ? `sources: ${links.join('; ')}` : null].filter(Boolean);
    return parts.length ? `- **${text(t.target)}**: ${parts.join(' — ')}` : null;
  }).filter(Boolean);
  const evidenceSection = evLines.length ? `\n\n**Evidence by target** (what drives each association):\n${evLines.join('\n')}` : '';
  return `${headline}\n\n| Rank | Target | Score | Evidence tier | Channel conflict |\n| --- | --- | --- | --- | --- |\n${rows.join('\n')}${evidenceSection}\n\nRanking: ${primary && available.includes(primary) ? `ordered by ${channel(primary)}` : 'combined available channels; Open Targets-primary ordering was not established'}. Successful channels: ${available.map(channel).join(', ') || 'none reported'}. Failed channels: ${errors.map(channel).join(', ') || 'none reported'}.\n\nScores are associations, not clinical probabilities. Evidence tiers describe channel agreement, not independent experimental validation; AI-generated reasoning is not a retrieved publication. A conflict means the channels disagree. No improvement over Open Targets alone has been established.${errors.length || !available.length || reasoningOnly ? '\n\nRetrieve or retry the missing source evidence before using this ranking as evidence-backed prioritization.' : ''}`;
}

const DB_ENTITY_TYPES = ['gene', 'protein', 'compound', 'variant', 'pathway', 'structure', 'disease', 'literature'];
/** Named databases = the connector manifest enum (backend/lib/mcp/tools_manifest.py) plus the two federated-only sources. */
export const DB_NAMES = ['uniprot', 'pdb', 'pdbe', 'alphafold', 'interpro', 'string', 'ncbi_gene', 'ensembl', 'dbsnp', 'clinvar', 'gnomad',
  'kegg', 'reactome', 'go', 'hpo', 'chebi', 'chembl', 'pubchem', 'bindingdb', 'pharos', 'clinicaltrials', 'biorxiv'];
/** Search modes the backend implements per database (ai_assistant._query_*): similarity over ALL of ChEMBL / PubChem (SMILES) and the whole PDB (sequence). */
const SIMILARITY_DBS = ['chembl', 'pubchem', 'pdb'];

/** Chat `query_database` -> POST /api/databases/query, the same intent-driven route the connector uses.
 *  `operation` is chosen by the model from the user's intent, never inferred from the query text. Pure validation, no network. */
export function databaseQueryRequest(input: unknown): RecordValue {
  if (!object(input) || typeof input.query !== 'string' || !input.query.trim()) {
    throw new Error('query must be a non-empty string');
  }
  const query = input.query.trim();
  const database = input.database == null ? 'federated' : String(input.database).trim().toLowerCase();
  const operation = input.operation == null ? 'lookup' : String(input.operation).trim().toLowerCase();
  if (database !== 'federated' && !DB_NAMES.includes(database)) {
    throw new Error(`database must be 'federated' or one of: ${DB_NAMES.join(', ')}`);
  }
  if (!['lookup', 'similarity', 'text'].includes(operation)) throw new Error("operation must be 'lookup', 'similarity' or 'text'");
  if (operation === 'similarity') {
    if (!SIMILARITY_DBS.includes(database)) {
      throw new Error(`similarity search is implemented for ${SIMILARITY_DBS.join(', ')} only (chembl and pubchem take a SMILES, pdb takes a protein sequence); name one of them as database`);
    }
  } else if (query.length > 300) {
    throw new Error('query must be at most 300 characters for lookup or text search');
  }
  if (operation !== 'lookup' && database === 'federated') {
    throw new Error("operation 'text' or 'similarity' needs a named database; the federated fan-out only does lookups");
  }
  if (query.length > 5000) throw new Error('query must be at most 5000 characters');
  if (input.entity_type != null && !DB_ENTITY_TYPES.includes(input.entity_type)) {
    throw new Error(`entity_type must be one of: ${DB_ENTITY_TYPES.join(', ')}`);
  }
  let sources: string[] | null = null;
  if (input.sources != null) {
    if (database !== 'federated') throw new Error('sources only applies to the federated fan-out (omit it when naming a database)');
    if (!Array.isArray(input.sources) || input.sources.length === 0 || input.sources.length > 8 ||
        input.sources.some((v: unknown) => typeof v !== 'string' || !/^[a-z0-9_]{2,32}$/.test(v))) {
      throw new Error('sources must be 1 to 8 source ids (lowercase letters, digits, underscore)');
    }
    sources = [...new Set<string>(input.sources)];
  }
  return {database, query, operation,
    ...(database === 'federated' && input.entity_type ? {entity_type: input.entity_type} : {}), ...(sources ? {sources} : {})};
}

const TRIM = 25;
const DB_NOTE = 'Records are returned as the public source gave them: cite the record id and the source. A source with status error, disabled or offline was NOT searched, so zero results from it is not evidence of absence. ' +
  'ClinicalTrials.gov rows are registry records (status, phase, sponsor, stated stop reason), not trial results or outcomes. bioRxiv/medRxiv rows are preprints that have not been peer reviewed (peer_reviewed=false). ' +
  'Similarity scores are structural/sequence similarity, not activity or function.';

/** Compact either shape: the federated fan-out ({results: per source, merged}) or a single-source answer ({source, search, ...}). Failures stay visible. */
export function databaseQueryResult(data: unknown, query: string): RecordValue {
  if (!object(data)) return {error: 'Database backend returned an invalid response', query};
  if (data.success === false || data.error) return {error: data.error || 'Database backend reported failure', query};
  if (Array.isArray(data.merged) || (object(data.results) && !Array.isArray(data.results))) {
    const bySource = object(data.results) ? data.results : {};
    const per_source = Object.entries(bySource).map(([name, r]: [string, any]) => ({
      source: name,
      n_results: Array.isArray(r?.results) ? r.results.length : 0,
      status: r?.error ? 'error' : (r?.status ?? 'ok'),
      ...(r?.error || r?.detail ? {detail: String(r.error || r.detail).slice(0, 200)} : {}),
    }));
    const merged = Array.isArray(data.merged) ? data.merged : [];
    return {query, mode: 'federated', entity_type: data.entity_type, sources_queried: data.sources_queried, per_source,
      n_records: merged.length, records: merged.slice(0, TRIM), note: DB_NOTE};
  }
  // single named database: keep its tags (source, search) and trim any long list
  const out: RecordValue = {query, mode: 'single_source'};
  for (const [k, v] of Object.entries(data)) {
    if (k === 'traceback') continue;
    out[k] = Array.isArray(v) && v.length > TRIM ? [...v.slice(0, TRIM), {truncated: v.length - TRIM}] : v;
  }
  out.note = DB_NOTE;
  return out;
}
