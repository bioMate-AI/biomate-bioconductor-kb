/** Run tools share the same authorized, live run/output/findings APIs as the UI. */
export async function decodeConnectorResponse(response: Response): Promise<any> {
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HTTP ${response.status}: ${text.slice(0, 300)}`);
  }
  const type = response.headers.get('content-type') || '';
  if (/application\/(?:[\w.+-]*\+)?json/i.test(type)) return response.json();
  if (/text\/markdown/i.test(type)) return { format: 'markdown', content: await response.text() };
  throw new Error(`Unexpected connector response content type: ${type || '(missing)'}`);
}

export function connectorRunResult(run: any, outputs: any[], findings?: any) {
  return {
    run_id: run.id,
    runId: run.id,
    workflowName: run.workflowName,
    status: run.execution?.status || 'unknown',
    startedAt: run.execution?.startedAt || null,
    nextflowRunId: run.execution?.nextflowRunId || null,
    output_files: outputs.map(file => ({
      name: file.name,
      size: file.size,
      s3_uri: file.s3Uri,
      download_url: file.downloadUrl,
      step: file.step,
    })),
    ...(findings === undefined ? {} : { findings }),
  };
}

export function validateReportRequest(body: { format?: string; sections?: string[] }) {
  if (body.format && body.format !== 'markdown') {
    throw new Error('Unsupported report format. This connector currently exports markdown; PDF and DOCX are not implemented.');
  }
  if (body.sections && (!Array.isArray(body.sections) || body.sections.some(s => s !== 'findings'))) {
    throw new Error('Unsupported report sections. This endpoint exports the findings report; other sections are not implemented.');
  }
}

export function createConnectorRunTools(base: string, headers: Record<string, string>) {
  const get = async (pathname: string) => decodeConnectorResponse(await fetch(base + pathname, {
    headers, signal: AbortSignal.timeout(30000),
  }));
  const terminal = (run: any) => ['completed', 'succeeded', 'success'].includes(run.execution?.status);
  return {
    async getRun(runId: string, includeFindings = true) {
      // Refresh executor state before reading outputs; /meta alone reads stale storage.
      const run = await get(`/api/workflows/runs/${encodeURIComponent(runId)}`);
      const id = encodeURIComponent(run.id);
      const [outputs, findings] = await Promise.all([
        get(`/api/runs/${id}/outputs`),
        includeFindings && terminal(run) ? get(`/api/workflows/runs/${id}/findings`) : undefined,
      ]);
      if (!Array.isArray(outputs.outputs)) throw new Error('Canonical output API returned no output inventory');
      return connectorRunResult(run, outputs.outputs, findings);
    },
    async exportReport(runId: string, body: { format?: string; sections?: string[] }) {
      validateReportRequest(body);
      const run = await get(`/api/workflows/runs/${encodeURIComponent(runId)}`);
      if (!terminal(run)) throw new Error('Report requires a successfully completed run');
      const id = encodeURIComponent(run.id);
      // This is the UI's preparation API, not the unrelated chat-analysis endpoint.
      // Keep pending explicit so clients never mistake a status message for a report.
      const findings = await get(`/api/workflows/runs/${id}/findings`);
      if (findings.status !== 'ready') return {
        run_id: run.id, status: findings.status || 'pending', format: 'markdown',
        message: findings.message || 'Findings are being prepared. Call export_report again when ready.',
      };
      const report = await get(`/api/workflows/runs/${id}/findings/report`);
      if (report.format !== 'markdown' || !report.content?.trim()) throw new Error('Report API returned no Markdown content');
      return { run_id: run.id, status: 'ready', ...report };
    },
  };
}
