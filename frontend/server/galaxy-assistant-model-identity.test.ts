// @vitest-environment node
/**
 * MODEL IDENTITY + region policy inside GalaxyAssistant (llm-region-policy.ts).
 * Dev 2026-11-12: "which llm you are using right now" → "I'm Claude, made by Anthropic" while the
 * reply ran on Gemini — nothing told the model what it was, so it guessed.
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('./storage', () => ({ storage: { getExecutionRuns: vi.fn().mockResolvedValue([]) } }));
vi.mock('./conversation-state', () => ({ conversationStateManager: {
  loadState: vi.fn().mockResolvedValue({ phase: 'gathering', workflowSteps: [], contextStack: [] }),
  saveSessionMemory: vi.fn().mockResolvedValue(undefined),
} }));
vi.mock('@google/generative-ai', () => ({
  GoogleGenerativeAI: class { getGenerativeModel() { return { generateContent: vi.fn() }; } },
}));
import { GalaxyAssistant } from './galaxy-assistant';
import { llmPolicyStorage, modelIdentity } from './llm-region-policy';

const env = { ...process.env };
afterEach(() => { process.env = { ...env }; vi.unstubAllGlobals(); });

describe('the built system prompt names the model that answers', () => {
  it('China user on DeepSeek: the reply prompt carries the identity block and 国产大模型', async () => {
    process.env.BIOMATE_LOCAL_ONLY = '1';
    process.env.BIOMATE_LOCAL_LLM_URL = 'http://localhost:8000/v1';
    process.env.BIOMATE_LOCAL_LLM_ORIGIN = 'http://localhost:8000';
    process.env.BIOMATE_LOCAL_LLM_MODEL = 'trial';
    const requests: any[] = [];
    vi.stubGlobal('fetch', vi.fn(async (_url: string, init: any) => {
      requests.push(JSON.parse(init.body));
      return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: '我是 BioMate，当前使用的是国产大模型 DeepSeek V4.1 Flash。' } }] }));
    }));
    const assistant: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
    await assistant.generateResponse('which llm you are using right now', { type: 'informational' }, [], [],
      { shouldGenerate: false }, null,
      { userId: 'u', uiLanguage: 'zh', llmRegion: 'cn', modelIdentity: modelIdentity('deepseek/deepseek-v4.1-flash') },
      undefined, undefined, () => {}, '', '', [], () => {});
    const reply = requests.find(r => r.tools)!; // the reply turn (it carries BioMate's tools)
    const system = reply.messages.find((m: any) => m.role === 'system').content as string;
    expect(system).toContain('MODEL IDENTITY');
    expect(system).toContain('DeepSeek V4.1 Flash (deepseek/deepseek-v4.1-flash) from DeepSeek');
    expect(system).toContain('国产大模型');
    expect(system).toMatch(/Never claim to be Claude, GPT, Gemini/);
  });

  it('the OpenRouter chat prompt names the selected model', async () => {
    const assistant: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
    const create = vi.fn(async function* () { yield { choices: [{ delta: { content: 'ok' } }] }; });
    assistant._getOpenRouterClient = () => ({ chat: { completions: { create } } });
    await assistant._generateChatWithOpenRouter('which model?', { selectedModel: 'z-ai/glm-5.3-prime' });
    const system = (create.mock.calls[0] as any)[0].messages[0].content as string;
    expect(system).toContain('GLM 5.3 Prime (z-ai/glm-5.3-prime) from Zhipu AI');
  });
});

describe('responseModelFor — what the label and identity report', () => {
  it('an OpenRouter user: their selected model (GLM stays GLM)', () => {
    const a: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
    expect(a.responseModelFor({ openrouterKey: 'k', selectedModel: 'z-ai/glm-5.3-prime' })).toBe('z-ai/glm-5.3-prime');
    expect(a.responseModelFor({ openrouterKey: 'k', openaiBaseUrl: 'http://dashscope/v1', selectedModel: 'qwen-max' })).toBe('qwen-max');
  });
  it('no key of their own: the built-in response model', () => {
    const a: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
    a.setModelConfig({ responseModel: 'gemini-3.8-flash' });
    expect(a.responseModelFor({})).toBe('gemini-3.8-flash');
  });
});

describe('China users never reach Gemini or the system Claude client', () => {
  const route = { url: 'https://openrouter.ai/api/v1', key: 'zh', model: 'deepseek/deepseek-v4.1-flash', source: 'openrouter_zh_key' as const };
  it('Gemini is unavailable and the Claude client is the Chinese-model shim', () => {
    process.env.GEMINI_API_KEY = 'gemini-key';
    const a: any = new GalaxyAssistant({ galaxyAPIProxy: {}, anthropicApiKey: 'sk-ant-system' } as any);
    expect(a.gemini).not.toBeNull();
    expect(a._getClaude()).toBe(a.claude);
    llmPolicyStorage.run({ region: 'cn', reasons: ['ip'], cnRoute: route }, () => {
      expect(a.gemini).toBeNull();
      expect(a._getClaude()).not.toBe(a.claude);
    });
    llmPolicyStorage.run({ region: 'cn', reasons: ['ip'], cnRoute: null }, () => {
      expect(() => a._getClaude()).toThrow(/国产大模型暂不可用/);
    });
  });
});
