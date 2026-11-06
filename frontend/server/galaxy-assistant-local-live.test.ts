/** Opt-in live local-model diagnostic using real BioMate prompt/tool orchestration.
 * Storage fixtures are synthetic. This is not a production database or release benchmark.
 */
import { afterAll, expect, it, vi } from 'vitest';
vi.mock('./storage', () => ({ storage: { getExecutionRuns: vi.fn().mockResolvedValue([
  { id: 'fixture-run-729', workflowName: 'rnaseq', execution: { status: 'failed', outputs: {} } },
]) } }));
vi.mock('./conversation-state', () => ({ conversationStateManager: {
  loadState: vi.fn().mockResolvedValue({ phase: 'gathering', workflowSteps: [], contextStack: [] }),
} }));
import { GalaxyAssistant } from './galaxy-assistant';
import { llmGenerate } from './llm-client';
import { writeFileSync } from 'node:fs';
const endpoint = process.env.BIOMATE_LIVE_MODEL_URL;
const original = { ...process.env };
afterAll(() => { process.env = original; });
it.skipIf(!endpoint)('runs the BioMate history tool loop against the live local model', async () => {
  process.env.BIOMATE_LOCAL_ONLY='1';process.env.BIOMATE_LOCAL_LLM_URL=endpoint!;
  process.env.BIOMATE_LOCAL_LLM_ORIGIN=new URL(endpoint!).origin;
  process.env.BIOMATE_LOCAL_LLM_MODEL=process.env.BIOMATE_LIVE_MODEL_NAME || 'Qwen/Qwen3.8-27B';
  process.env.BIOMATE_LOCAL_LLM_TIMEOUT_MS='600000';
  const assistant:any=new GalaxyAssistant({ galaxyAPIProxy:{} } as any);
  // This fixture permits real history-handler reads only. Unexpected model tools
  // return observations but cannot execute code or access other data/services.
  for (const name of ['_toolRunCode','_toolReadFile','_toolQueryKnowledge','_toolSearchLiterature','_toolSearchMyData','_toolListDataSources','_toolListRunOutputs']) {
    assistant[name]=async()=>{ throw new Error('Tool unavailable in this read-only history fixture'); };
  }
  const events:any[]=[];const started=Date.now();
  const result=await assistant.generateResponse('Look up my latest workflow run. Report its ID and status. Do not start another run.',
    {type:'informational'},[],[],{shouldGenerate:false},null,{userId:'synthetic-trial-user'},undefined,undefined,
    ()=>{},'','',[],(e:any)=>events.push(e));
  const report={scope:'live model and actual BioMate orchestration, synthetic storage',model:process.env.BIOMATE_LOCAL_LLM_MODEL,
    latency_ms:Date.now()-started,events,result};
  writeFileSync(process.env.BIOMATE_LIVE_REPORT || '/private/tmp/biomate-core-live.json',JSON.stringify(report,null,2));
  expect(events.some(e=>e.type==='tool_call'&&e.name==='list_history')).toBe(true);
  expect(events.some(e=>e.type==='tool_result'&&JSON.stringify(e.output).includes('fixture-run-729'))).toBe(true);
  expect(events.some(e=>e.type==='tool_call'&&e.name==='run_code')).toBe(false);
  expect(result.message).toContain('fixture-run-729');expect(result.message.toLowerCase()).toContain('failed');
},1200000);

it.skipIf(!endpoint)('validates identifier JSON through the live BioMate adapter', async () => {
  process.env.BIOMATE_LOCAL_ONLY = '1';
  process.env.BIOMATE_LOCAL_LLM_URL = endpoint!;
  process.env.BIOMATE_LOCAL_LLM_ORIGIN = new URL(endpoint!).origin;
  process.env.BIOMATE_LOCAL_LLM_MODEL = process.env.BIOMATE_LIVE_MODEL_NAME || 'Qwen/Qwen3.8-27B';
  process.env.BIOMATE_LOCAL_LLM_TIMEOUT_MS = '600000';
  const started = Date.now();
  const result = await llmGenerate({ prompt: 'Return a JSON object with exactly accession="GSE12345" and platform="GPL96". Preserve these identifiers exactly.', jsonMode: true, maxTokens: 256 });
  const answer = JSON.parse(result.text);
  const passed = answer.accession === 'GSE12345' && answer.platform === 'GPL96' && Object.keys(answer).length === 2;
  writeFileSync('/private/tmp/biomate-json-live.json', JSON.stringify({ scope: 'Synthetic live BioMate JSON adapter diagnostic', latency_ms: Date.now() - started, passed, result }, null, 2));
  expect(answer).toEqual({ accession: 'GSE12345', platform: 'GPL96' });
}, 660000);
