import {describe, it, expect} from 'vitest';
import {readFileSync} from 'node:fs';
import {scientificToolRequest, scientificToolResult, targetEvidenceReply} from './scientific-chat-tools';

it('presents completed target evidence without stale literature fallback or patient-count inference', () => {
  const result = {status:'ok', targets:[{rank:1,target:'BRAF',score:0.8533,tier:'nominated',conflict:true}],
    ranking:{mode:'primary_channel',primary_channel:'genetics_ot'},channels_run:['genetics_ot'],
    channel_errors:{llm_reasoned:'unavailable'},note:'Scores are associations, not clinical probabilities.'};
  const reply = targetEvidenceReply(result);
  expect(reply).toContain('completed successfully');
  expect(reply).toContain('| 1 | BRAF | 0.8533 | nominated | Yes |');
  expect(reply).toContain('Failed channels: AI-generated reasoning');
  expect(reply).toContain('not clinical probabilities');
  expect(reply).not.toMatch(/patient|not executed|could not be run|genetics_ot|llm_reasoned/);
  expect(() => targetEvidenceReply({...result,status:'error'})).toThrow();
});

describe('scientific chat boundary (pure contracts, no API mocks)', () => {
  it('rejects missing, blank, coerced and structured queries', () => {
    for (const input of [undefined, [], {}, {query:' '}, {query:42}, {query:{text:'melanoma'}}]) {
      expect(() => scientificToolRequest(input, 'targets')).toThrow(/query/);
      expect(() => scientificToolRequest(input, 'review')).toThrow(/query/);
    }
  });
  it('normalizes candidate symbols, caps integers and never guesses a disease id', () => {
    expect(scientificToolRequest({query:' melanoma ', candidate_targets:[' braf ', 'BRAF'], top_k:200}, 'targets')).toEqual({
      query:'melanoma', candidate_targets:['BRAF'], disease_id:null, top_k:100,
    });
    expect(scientificToolRequest({query:'q', disease_id:' MONDO_0005105 '}, 'targets').disease_id).toBe('MONDO_0005105');
    for (const top_k of [0, -1, 1.1, '5', true, NaN, Infinity]) expect(() => scientificToolRequest({query:'q',top_k}, 'targets')).toThrow(/top_k/);
    for (const candidate_targets of ['BRAF', [null], [5], ['']]) expect(() => scientificToolRequest({query:'q',candidate_targets}, 'targets')).toThrow(/candidate_targets/);
    expect(() => scientificToolRequest({query:'q',disease_id:'melanoma'}, 'targets')).toThrow(/disease_id/);
  });
  it('passes the optional ranking, validation and modality options and keeps modality unvalidated', () => {
    expect(scientificToolRequest({query: 'q'}, 'targets')).not.toHaveProperty('ranking_mode');
    const req = scientificToolRequest({query: 'q', ranking_mode: 'integrated', validate: true, suggest_modality: true}, 'targets');
    expect(req).toMatchObject({ranking_mode: 'integrated', validate: true, suggest_modality: true});
    expect(() => scientificToolRequest({query: 'q', ranking_mode: 'x'}, 'targets')).toThrow();
    expect(() => scientificToolRequest({query: 'q', validate: 'yes'}, 'targets')).toThrow();
    const out = scientificToolResult({targets: [{target: 'BRAF', score: 1, rank: 1, tier: 'nominated'}],
      modality_suggestions: [{target: 'BRAF', validated: false}], validation_plan: {n: 1}}, 'targets', 'q');
    expect(out.modality_suggestions).toEqual([{target: 'BRAF', validated: false}]);
    expect(String(out.modality_note)).toMatch(/NOT validated/);
    expect(out.validation_plan).toEqual({n: 1});
  });

  it('requires positive research success, prose and valid citations, including HTTP-200 failures', () => {
    for (const data of [null, {success:false,error:'agent unavailable'}, {}, {success:true,answer:'',citations:[]}, {success:true,answer:'x'}, {success:true,answer:'x',citations:[null]}]) {
      expect(scientificToolResult(data,'review','q')).toHaveProperty('error');
    }
    expect(scientificToolResult({success:false,error:'agent unavailable'},'review','q').error).toBe('agent unavailable');
  });
  it('preserves exact citation order, retrieval stats, conflicts and zero confidence', () => {
    const citations = [{title:'Paper 2',doi:'10.1/second',abstract:'finding'}, {title:'Paper 1',pmid:'123'}];
    const result = scientificToolResult({success:true,answer:'Two studies disagree [1] [2].',citations,confidence:0,conflicts:[{claim:'disagreement'}],retrieval:{PubMed:{found:10,kept:2}},methods_used:['PubMed']},'review','q');
    expect(result).not.toHaveProperty('error');
    expect(result.citations).toBe(citations);
    expect(result.conflicts).toEqual([{claim:'disagreement'}]);
    expect(result.retrieval).toEqual({PubMed:{found:10,kept:2}});
    expect(result.confidence).toBe(0);
    expect(scientificToolResult({success:true,answer:'Missing [3]',citations},'review','q')).toHaveProperty('error');
    expect(scientificToolResult({success:true,answer:'Missing [0]',citations},'review','q')).toHaveProperty('error');
  });
  it('does not mislabel uncited benchmark fallback as a literature-backed review', () => {
    const result = scientificToolResult({success:true,answer:'Benchmark summary',citations:[],source:'benchmark_fallback'},'review','q');
    expect(result.status).toBe('uncited');
    expect(result.note).toContain('not a literature-backed review');
  });
  it('distinguishes malformed target output, genuine empty evidence and unavailable OT', () => {
    expect(scientificToolResult({},'targets','q')).toHaveProperty('error');
    expect(scientificToolResult({targets:[{target:'BRAF',score:'0.9',rank:1,tier:'nominated'}]},'targets','q')).toHaveProperty('error');
    const result = scientificToolResult({targets:[],channels_run:[],channel_errors:{genetics_ot:'timeout'}},'targets','q');
    expect(result.status).toBe('no_evidence');
    expect(result.channel_errors).toEqual({genetics_ot:'timeout'});
    expect(result.note).toContain('NOT established');
  });
  it('preserves supporting/veto/conflict/provenance and reports the actual ranking mode', () => {
    const targets = [{target:'BRAF',score:0.2,rank:1,tier:'supporting',conflict:true,note:'one channel',per_channel_z:{genetics_ot:0.2}}];
    const result = scientificToolResult({targets,ranking:{mode:'primary_channel',primary_channel:'genetics_ot'},channel_provenance:{genetics_ot:{source:'OpenTargets'}}},'targets','q');
    expect(result.targets).toBe(targets);
    expect(result.channel_provenance.genetics_ot.source).toBe('OpenTargets');
    expect(result.note).toContain('Order follows OpenTargets');
    expect(result.note).toContain('not z-scores');
  });
  it('does not present target record counts as patients or LLM agreement as independent evidence', () => {
    const input={targets:[],channel_provenance:{genetics_ot:{source:'OpenTargets',n:200}}};
    const result=scientificToolResult(input,'targets','q');
    expect(result.channel_provenance.genetics_ot).toEqual({source:'OpenTargets',n_targets_retrieved:200});
    expect(input.channel_provenance.genetics_ot.n).toBe(200);
    expect(result.note).toContain('NOT patients');
    expect(result.note).toContain('channel agreement only');
    expect(result.note).toContain('not genetics-only');
  });
  it('wires both model loops through the user-scoped API and does not expose new online tools offline', () => {
    const source = readFileSync('server/galaxy-assistant.ts','utf8');
    for (const name of ['identify_targets','write_review']) {
      expect(source.match(new RegExp(`case '${name}':`, 'g'))).toHaveLength(2);
    }
    const handlers = source.slice(source.indexOf('  /** Thin, user-scoped proxy'),source.indexOf('  // ── Galaxy History context'));
    expect(handlers.match(/this\._api\(\)\.client\.post/g)).toHaveLength(2);
    expect(handlers).not.toContain('fetch(');
    expect(source).toContain("['search_literature', 'list_data_sources', 'identify_targets', 'write_review'].includes(tool.name)");
  });
  it('every advertised built-in tool has a dispatch case in both provider loops', () => {
    const source = readFileSync('server/galaxy-assistant.ts','utf8');
    const start = source.indexOf('const BIOMATE_TOOLS:');
    const definitions = source.slice(start,source.indexOf('\n];', start));
    const names = [...definitions.matchAll(/^    name: '([^']+)'/gm)].map(m=>m[1]);
    expect(names.length).toBeGreaterThan(0);
    for (const name of names) expect(source.match(new RegExp(`case '${name}':`, 'g')),`${name} provider dispatch drift`).toHaveLength(2);
  });
});
