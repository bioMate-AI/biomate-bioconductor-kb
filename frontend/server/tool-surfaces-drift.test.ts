import {describe, it, expect} from 'vitest';
import {readFileSync} from 'node:fs';
import manifest from './tools_manifest.json';

/**
 * Inventory + drift guard for the tool surfaces (docs/20261102_TOOL_SETS_UNIFICATION_PLAN.md, slice 1).
 * Surfaces today: the connector/MCP/Open Claw manifest (canonical: backend/lib/mcp/tools_manifest.py) and the in-app
 * assistant (BIOMATE_TOOLS in galaxy-assistant.ts). Adding or removing a tool on either must be a conscious edit here.
 */
const ASSISTANT_SRC = readFileSync('server/galaxy-assistant.ts', 'utf8');
const start = ASSISTANT_SRC.indexOf('const BIOMATE_TOOLS:');
const DEFS = ASSISTANT_SRC.slice(start, ASSISTANT_SRC.indexOf('\n];', start));
const assistantTools = [...DEFS.matchAll(/^    name: '([^']+)'/gm)].map(m => m[1]);
const manifestTools = ((manifest as any).anthropic as any[]).map(t => t.name);

const block = (name: string) => {
  const i = DEFS.indexOf(`    name: '${name}'`);
  const j = DEFS.indexOf('\n  {\n    name:', i + 1);
  return DEFS.slice(i, j === -1 ? undefined : j);
};

// Same capability under different names. Unify in slice 4 of the plan; until then the pair is recorded, not hidden.
const KNOWN_RENAMES: Record<string, string> = {search_workflow: 'search_workflows'};

describe('tool surfaces: inventory', () => {
  it('assistant tool set is exactly the recorded list', () => {
    expect(assistantTools).toEqual(['run_code', 'read_file', 'query_domain_knowledge', 'list_history', 'search_literature',
      'query_database', 'search_my_data', 'list_data_sources', 'search_workflows', 'request_new_tool', 'identify_targets', 'write_review',
      'search_chat_history']);
  });
  it('connector manifest tool set is exactly the recorded list', () => {
    expect(manifestTools).toEqual(['biomate_session', 'search_workflow', 'get_workflow_spec', 'run_workflow', 'get_run', 'cancel_run',
      'list_runs', 'watch_run', 'preview_file', 'export_report', 'analyze_results', 'explain_error', 'query_database', 'resolve_accession',
      'browse_data', 'fetch_public_data', 'search_literature', 'recall_memory', 'upload_file']);
  });
  it('every overlap or rename between the surfaces is deliberate', () => {
    const shared = assistantTools.filter(n => manifestTools.includes(n)).sort();
    expect(shared).toEqual(['query_database', 'search_literature']);
    for (const [manifestName, assistantName] of Object.entries(KNOWN_RENAMES)) {
      expect(manifestTools).toContain(manifestName);
      expect(assistantTools).toContain(assistantName);
    }
  });
});

describe('tool surfaces: shared capabilities keep their parameters', () => {
  const props = (name: string) => Object.keys(((manifest as any).anthropic as any[]).find(t => t.name === name).input_schema.properties);
  for (const name of ['query_database', 'search_literature']) {
    it(`${name}: the assistant advertises every parameter the connector advertises`, () => {
      const assistantBlock = block(name);
      const missing = props(name).filter(p => !new RegExp(`\\b${p}\\s*:`).test(assistantBlock));
      expect(missing, `${name}: parameters missing on the assistant`).toEqual([]);
    });
  }
  it('query_database exposes the intent-driven operation on BOTH surfaces (lookup / text / similarity)', () => {
    const m = ((manifest as any).anthropic as any[]).find(t => t.name === 'query_database').input_schema.properties;
    expect(m.operation.enum).toEqual(['lookup', 'text', 'similarity']);
    expect(block('query_database')).toMatch(/enum: \['lookup', 'text', 'similarity'\]/);
  });
  it('the other surfaces generated from the manifest carry the same query_database parameters', () => {
    const mcp = ((manifest as any).mcp as any[]).find(t => t.name === 'query_database').inputSchema.properties;
    const anth = ((manifest as any).anthropic as any[]).find(t => t.name === 'query_database').input_schema.properties;
    const oai = ((manifest as any).openai as any[]).find(t => t.function.name === 'query_database').function.parameters.properties;
    expect(Object.keys(mcp).sort()).toEqual(Object.keys(anth).sort());
    expect(Object.keys(oai).sort()).toEqual(Object.keys(anth).sort());
  });
});
