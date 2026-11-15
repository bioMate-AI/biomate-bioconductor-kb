/** A run / step error as the user reads it: stack lines dropped, storage URIs reduced to the file
 *  name, upload UUIDs removed, infrastructure names (AWS Batch, S3, the storage bucket, the internal
 *  backend) replaced with neutral words. Used by the workflow panel and the after-run report. */
export function userFacingErrorText(msg: unknown): string {
  const text = String(msg ?? '');
  if (!text) return text;
  return text
    .split('\n').filter(l => !/^\s*at\s+[\w.$]+\(/.test(l)).join('\n')
    .replace(/(?:s3|gs):\/\/[^\s'"]+/gi, (m) => {
      const last = m.replace(/\/+$/, '').split('/').pop() || '';
      return /\.[A-Za-z0-9]{1,8}(?:\.gz)?$/.test(last) ? last : 'the stored data';
    })
    .replace(/biomate-nextflow-work|biomate-uploads|biomate-cryo-data|biomate-data|biomate-outputs/gi, 'storage')
    .replace(/\bAWS\s+Batch\b/gi, 'cloud compute')
    .replace(/\b(?:Amazon\s+)?S3\s+(?:bucket|object|path|location|key)s?\b/gi, 'storage')
    .replace(/\bS3\b/g, 'storage')
    .replace(/\bGalaxy\b/g, 'BioMate')
    .replace(/\s*\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, '')
    .replace(/Launcher\.groovy:\d+/gi, '')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
}
