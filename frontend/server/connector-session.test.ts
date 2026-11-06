import { describe, it, expect } from 'vitest';
import { readConnectorSession } from './connector-session';

function stream(text: string, chunkSize = 7) {
  const bytes = new TextEncoder().encode(text);
  return new Response(new ReadableStream({ start(controller) {
    for (let offset = 0; offset < bytes.length; offset += chunkSize) controller.enqueue(bytes.slice(offset, offset + chunkSize));
    controller.close();
  } }), { headers: { 'content-type': 'text/event-stream' } });
}
const frame = (event: string, data: any) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
describe('connector chat adapter', () => {
  it('preserves final branch plans, Unicode and clarification instead of partial deltas', async () => {
    const workflow = { workflow_type: 'chain', chain_steps: [{ id: 'a', depends_on: [] }, { id: 'b', depends_on: ['a'], dimensions: { species: 'human' } }], coverage_axes: ['species'] };
    const subIntentResults = [{ workflow, intent: '分析' }];
    const result = await readConnectorSession(stream(frame('delta', { text: 'partial' }) + frame('final', {
      response: '中文分析完成', workflow, subIntentResults, isMultiIntent: true, state: 'needs_input',
      metadata: { paramClarifications: ['species'], intentClarification: { question: 'Which samples?' } },
      thinking_content: 'private reasoning',
    }) + frame('done', { ok: true }), 1));
    expect(result.response).toBe('中文分析完成');
    expect(result.workflow_suggested).toEqual(workflow);
    expect(result.subIntentResults).toEqual(subIntentResults);
    expect(result.clarification.parameters).toEqual(['species']);
    expect(result).not.toHaveProperty('thinking_content');
  });
  it('handles CRLF, comments, multiline data and a final frame without a newline', async () => {
    const text = ': heartbeat\r\n\r\nevent: final\r\ndata: {"response":\r\ndata: "ok"}\r\n\r\nevent: done\r\ndata: {"ok":true}';
    expect((await readConnectorSession(stream(text))).response).toBe('ok');
  });
  it('rejects HTTP errors and non-SSE responses', async () => {
    await expect(readConnectorSession(new Response('', { status: 401 }))).rejects.toThrow('HTTP 401');
    await expect(readConnectorSession(new Response('<html>login</html>'))).rejects.toThrow('no event stream');
  });
  it('does not report success for partial, malformed or failed streams', async () => {
    for (const text of [frame('delta', { text: 'partial' }), frame('final', { response: 'incomplete' }),
      frame('final', { response: 'draft' }) + frame('done', { ok: false }),
      frame('error', { message: 'upstream failed' }), 'event: final\ndata: broken\n\n',
      frame('complete', { blocked: true })]) {
      await expect(readConnectorSession(stream(text))).rejects.toThrow();
    }
  });
});
