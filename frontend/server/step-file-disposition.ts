/** Safe attachment/inline headers for the authorized run-file route. */
export function stepFileDisposition(name: string, download: unknown): string {
  const clean = name.split(/[\\/]/).pop()?.replace(/[\x00-\x1f\x7f]/g, '') || 'output';
  const ascii = clean.replace(/[^\x20-\x7e]|["\\]/g, '_');
  const encoded = encodeURIComponent(clean).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
  return `${download === '1' ? 'attachment' : 'inline'}; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}
