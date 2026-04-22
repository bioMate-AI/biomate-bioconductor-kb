/**
 * Gemini 3 Flash — thin wrapper replacing Claude Haiku for lightweight inference tasks.
 *
 * Usage:
 *   import { callGeminiFlash, GEMINI_FLASH_MODEL } from './gemini-flash';
 *
 *   const text = await callGeminiFlash({
 *     messages: [{ role: 'user', content: 'Classify this query...' }],
 *     system: 'You are a bioinformatics classifier.',
 *     maxTokens: 256,
 *     jsonMode: true,
 *   });
 */

import { GoogleGenerativeAI, GenerativeModel, GenerationConfig } from '@google/generative-ai';

export const GEMINI_FLASH_MODEL = 'gemini-2.5-flash-lite';

function getClient(): GoogleGenerativeAI {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY not set');
  return new GoogleGenerativeAI(apiKey);
}

interface CallGeminiFlashOpts {
  messages: Array<{ role: 'user' | 'assistant'; content: string }>;
  system?: string;
  maxTokens?: number;
  temperature?: number;
  jsonMode?: boolean;
  /** AbortSignal for timeout */
  signal?: AbortSignal;
}

/**
 * Call Gemini 3 Flash with an Anthropic-style messages array.
 * Returns the response text.
 */
export async function callGeminiFlash(opts: CallGeminiFlashOpts): Promise<string> {
  const genAI = getClient();

  const generationConfig: GenerationConfig = {
    maxOutputTokens: opts.maxTokens ?? 1024,
    temperature: opts.temperature ?? 0,
    ...(opts.jsonMode ? { responseMimeType: 'application/json' } : {}),
  };

  const model: GenerativeModel = genAI.getGenerativeModel({
    model: GEMINI_FLASH_MODEL,
    ...(opts.system ? { systemInstruction: opts.system } : {}),
    generationConfig,
  });

  const { messages } = opts;
  if (messages.length === 0) return '';

  if (messages.length === 1) {
    const result = await model.generateContent(messages[0].content);
    return result.response.text();
  }

  // Multi-turn: build history from all but the last message
  const history = messages.slice(0, -1).map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));
  const lastMessage = messages[messages.length - 1].content;
  const chat = model.startChat({ history });
  const result = await chat.sendMessage(lastMessage);
  return result.response.text();
}

/**
 * Convenience: call with a single system + user message pair.
 */
export async function callGeminiFlashSimple(
  userContent: string,
  system?: string,
  maxTokens = 1024,
  jsonMode = false,
): Promise<string> {
  return callGeminiFlash({
    messages: [{ role: 'user', content: userContent }],
    system,
    maxTokens,
    jsonMode,
  });
}
