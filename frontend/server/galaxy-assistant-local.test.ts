import { afterEach, beforeEach, expect, it, vi } from 'vitest';
vi.mock('./storage', () => ({ storage: { getExecutionRuns: vi.fn().mockResolvedValue([
  { id: 'run-test-1', workflowName: 'rnaseq', execution: { status: 'completed', outputs: {} } },
]) } }));
vi.mock('./conversation-state', () => ({ conversationStateManager: {
  loadState: vi.fn().mockResolvedValue({ phase: 'gathering', workflowSteps: [], contextStack: [] }),
} }));
import { GalaxyAssistant } from './galaxy-assistant';
const env = { ...process.env };
beforeEach(() => {
  process.env.BIOMATE_LOCAL_ONLY = '1';
  process.env.BIOMATE_LOCAL_LLM_URL = 'http://localhost:8000/v1';
  process.env.BIOMATE_LOCAL_LLM_ORIGIN = 'http://localhost:8000';
  process.env.BIOMATE_LOCAL_LLM_MODEL = 'trial';
  process.env.GEMINI_API_KEY = 'must-not-be-used';
});
afterEach(() => { process.env = { ...env }; vi.unstubAllGlobals(); });
it('uses the actual GalaxyAssistant tool loop with local inference', async () => {
  const requests: any[] = [];
  vi.stubGlobal('fetch', vi.fn(async (url: string, init: any) => {
    expect(url).toBe('http://localhost:8000/v1/chat/completions');
    const body = JSON.parse(init.body); requests.push(body);
    let message: any = { content: '{}' }; let finish_reason = 'stop';
    if (body.tools && !body.messages.some((m: any) => m.role === 'tool')) {
      message = { tool_calls: [{ id: 'history-call', type: 'function', function: { name: 'list_history', arguments: '{"limit":1}' } }] };
      finish_reason = 'tool_calls';
    } else if (body.messages.some((m: any) => m.role === 'tool')) message = { content: 'Your recent run is run-test-1 (rnaseq).' };
    return new Response(JSON.stringify({ choices: [{ message, finish_reason }] }));
  }));
  const assistant: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
  assistant.setModelConfig({ responseModel: 'gemini-should-not-run', enableThinking: true });
  const events: any[] = [];
  const result = await assistant.generateResponse('List my recent workflow run', { type: 'informational' }, [], [],
    { shouldGenerate: false }, null, { userId: 'trial-user' }, undefined, undefined, () => {}, '', '', [], (e: any) => events.push(e));
  expect(result.message).toContain('run-test-1');
  expect(events.map(e => e.type)).toEqual(['tool_call', 'tool_result']);
  expect(requests.some(r => r.messages.some((m: any) => m.role === 'tool' && m.tool_call_id === 'history-call' && m.content.includes('run-test-1')))).toBe(true);
  expect(assistant.gemini).toBeNull();
  expect(assistant.modelConfig.responseModel).toBe('trial');
  expect(assistant.modelConfig.toolRankingModel).toBe('trial');
});

it('uses the compact local intent contract and preserves correction context', async () => {
  const requests: any[] = [];
  vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
    const body = JSON.parse(init.body); requests.push(body);
    return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
      intents: [{ id: 'intent_1', type: 'workflow_modification', subQuery: 'Use GRCm39 and keep paired-end; do not execute',
        keywords: ['genome'], inlineParameters: { genome: 'GRCm39', paired_end: 'true' }, confidence: 0.95, facts: [], dependsOn: [] }],
      is_sequential: false, key_terms: ['GRCm39'], chain_hint: null,
    }) } }] }));
  }));
  const assistant: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
  assistant._getChainHintNames = async () => ['bulk_rnaseq_de_analysis', 'unrelated_proteomics'];
  const result = await assistant.analyzeIntent('Change genome to GRCm39, keep paired-end and do not run anything.',
    { accumulatedFacts: [{ id: 'fact_1', category: 'genome', value: 'GRCh38' }], previousMessages: [] }, 'Dataset ID: 000123; paired_end=true');
  const system = requests[0].messages[0].content;
  expect(system.length).toBeLessThan(5000);
  expect(system).toContain('000123'); expect(system).toContain('fact_1'); expect(system).toContain('GRCh38');
  expect(result.primaryIntent.inlineParameters).toEqual({ genome: 'GRCm39', paired_end: 'true' });
  expect(result.primaryIntent.actions.needsWorkflowModification).toBe(true);
  expect(result.primaryIntent.actions.needsWorkflowGeneration).toBe(false);
});
