/**
 * Did Galaxy answer "this Nextflow run does not exist"?
 *
 * Galaxy keeps run state in its container and run-state store; a rebuild loses both and Galaxy
 * then answers 404 {"detail": "Run not found: <id>"} forever. galaxyAPIProxy's response
 * interceptor rethrows axios errors as GalaxyAPIError {status_code, detail}; plain axios errors
 * carry {response: {status, data}}. Accept both shapes.
 */
export function isNextflowRunNotFound(err: any): boolean {
  const status = err?.status_code ?? err?.response?.status;
  const body = err?.detail ?? err?.response?.data ?? '';
  return status === 404 && /Run not found/i.test(typeof body === 'string' ? body : JSON.stringify(body));
}
