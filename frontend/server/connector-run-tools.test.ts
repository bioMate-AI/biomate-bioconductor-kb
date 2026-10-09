import { describe, it, expect } from 'vitest';
import { decodeConnectorResponse, connectorRunResult, validateReportRequest } from './connector-run-tools';

describe('connector run contracts', () => {
  it('preserves Markdown bytes instead of trying to parse them as JSON', async () => {
    const md = '# Findings\n\n中文结果: 0.875\n';
    expect(await decodeConnectorResponse(new Response(md, { headers: { 'content-type': 'text/markdown; charset=utf-8' } })))
      .toEqual({ format: 'markdown', content: md });
  });
  it('decodes JSON and rejects upstream errors and login HTML', async () => {
    expect(await decodeConnectorResponse(Response.json({ status: 'pending' }))).toEqual({ status: 'pending' });
    await expect(decodeConnectorResponse(new Response('Not owned', { status: 404 }))).rejects.toThrow('HTTP 404');
    await expect(decodeConnectorResponse(new Response('<html>Sign in</html>', { headers: { 'content-type': 'text/html' } }))).rejects.toThrow('Unexpected');
  });
  it('supplies the exact s3_uri required by preview_file and excludes private run fields', () => {
    const result = connectorRunResult({ id: 'run-1', userId: 'private', workflowName: 'ADMET', execution: { status: 'completed' } },
      [{ name: 'result.json', s3Uri: 's3://bucket/run/result.json', downloadUrl: 'https://example.test/result', size: 100 }], { status: 'pending' });
    expect(result.status).toBe('completed');
    expect(result.output_files[0].s3_uri).toBe('s3://bucket/run/result.json');
    expect(result.findings).toEqual({ status: 'pending' });
    expect(result).not.toHaveProperty('userId');
    expect(connectorRunResult({ id: 'run-1' }, [])).not.toHaveProperty('findings');
  });
  it('does not disguise unsupported formats or sections as successful exports', () => {
    expect(() => validateReportRequest({ format: 'markdown', sections: ['findings'] })).not.toThrow();
    expect(() => validateReportRequest({ format: 'pdf' })).toThrow('Unsupported report format');
    expect(() => validateReportRequest({ sections: ['methods'] })).toThrow('Unsupported report sections');
  });
});
