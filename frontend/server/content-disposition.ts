/** RFC 6266 attachment header: ASCII fallback + UTF-8 filename* (Chinese and other names survive). */
export function attachmentDisposition(name: string): string {
  const base = (name.split('/').pop() || 'download').replace(/[\r\n"]/g, '_');
  const ascii = base.replace(/[^\x20-\x7e]/g, '_');
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(base)}`;
}
