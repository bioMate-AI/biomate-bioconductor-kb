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
  if (input.candidate_targets != null && (!Array.isArray(input.candidate_targets) || input.candidate_targets.some((v: unknown) => typeof v !== 'string' || !v.trim()))) {
    throw new Error('candidate_targets must contain non-empty gene symbols');
  }
  const candidates = input.candidate_targets == null ? null : [...new Set(input.candidate_targets.map((v: string) => v.trim().toUpperCase()))];
  return {query, disease_id: input.disease_id?.trim() || null, candidate_targets: candidates?.length ? candidates : null, top_k: topK};
}

export function scientificToolResult(data: unknown, kind: 'targets' | 'review', query: string): RecordValue {
  if (!object(data)) return {error: 'Scientific backend returned an invalid response', query};
  if (data.success === false || data.error) return {error: data.error || 'Scientific backend reported failure', query};
  if (kind === 'targets') {
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
      channel_errors: data.channel_errors, channel_provenance: provenance,
      n_targets_total: data.n_targets_total ?? data.targets.length,
      targets: data.targets,
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
    note: data.citations.length
      ? 'Preserve the answer/reference numbering and source disagreements. Cite only returned references; do not invent DOI/PMID. Low confidence and retrieval limitations must be stated.'
      : 'No literature citations were returned. This is not a literature-backed review; disclose the source/fallback and do not invent references.',
  };
}
