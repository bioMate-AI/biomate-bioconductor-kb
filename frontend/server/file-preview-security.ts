/** Active output documents run in an opaque origin, never with BioMate's cookie/API privileges. */
export function setFilePreviewSecurityHeaders(res: { setHeader(name: string, value: string): unknown }, contentType: string): void {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (/^(text\/html|image\/svg\+xml)(?:;|$)/i.test(contentType)) {
    res.setHeader('Content-Security-Policy', "sandbox allow-scripts; base-uri 'none'; object-src 'none'");
  }
}
