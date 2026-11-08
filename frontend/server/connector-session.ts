/** Convert the UI chat SSE contract to a synchronous connector result. */
export async function readConnectorSession(response: Response) {
  if (!response.ok) throw new Error(`Chat request failed: HTTP ${response.status}`);
  if (!response.headers.get('content-type')?.includes('text/event-stream') || !response.body) {
    throw new Error('Chat API returned no event stream');
  }
  let buffer = '';
  let event = '';
  let data: string[] = [];
  let final: Record<string, any> | undefined;
  let completed = false;
  function dispatch() {
    if (!data.length) { event = ''; return; }
    const payload = JSON.parse(data.join('\n'));
    if (event === 'error' || (event === 'done' && payload.ok === false)) {
      throw new Error(payload.message || 'Chat session failed');
    }
    if (event === 'complete' && payload.blocked) throw new Error('Chat request was blocked');
    if (event === 'final') final = payload;
    if (event === 'done' && payload.ok === true) completed = true;
    event = '';
    data = [];
  }
  function line(value: string) {
    if (!value) dispatch();
    else if (value.startsWith('event:')) event = value.slice(6).trim();
    else if (value.startsWith('data:')) data.push(value.slice(5).replace(/^ /, ''));
  }
  const decoder = new TextDecoder();
  for await (const chunk of response.body as any) {
    buffer += decoder.decode(chunk, { stream: true });
    let newline: number;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      line(buffer.slice(0, newline).replace(/\r$/, ''));
      buffer = buffer.slice(newline + 1);
    }
  }
  buffer += decoder.decode();
  if (buffer) line(buffer.replace(/\r$/, ''));
  dispatch();
  if (!completed || !final || typeof final.response !== 'string') {
    throw new Error('Chat stream ended without a complete final response');
  }
  // Select public UI fields; do not return internal thinking or arbitrary events.
  return {
    response: final.response,
    state: final.state,
    workflow_suggested: final.workflow ?? null,
    subIntentResults: final.subIntentResults ?? [],
    isMultiIntent: final.isMultiIntent ?? false,
    suggestions: final.suggestions ?? [],
    prerequisitesValidation: final.prerequisitesValidation,
    datasetReferenceUnresolvedIds: final.datasetReferenceUnresolvedIds,
    researchResponse: final.researchResponse,
    benchmarkEvidence: final.benchmarkEvidence,
    clarification: {
      parameters: final.metadata?.paramClarifications,
      intent: final.metadata?.intentClarification,
      workflowGenerationDiagnostics: final.metadata?.workflowGenerationDiagnostics,
    },
    ...(final.run_id ? { run_id: final.run_id } : {}),
  };
}
