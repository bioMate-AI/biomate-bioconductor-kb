import { decryptField } from './field-encrypt';

/** Decide from a nonempty decrypted personal key, never shared-proxy fallback. */
export function hasPersonalSkillAccess(user: { galaxyApiKey?: unknown } | undefined): boolean {
  const raw = user?.galaxyApiKey;
  return typeof raw === 'string' && raw.trim().length > 0 && decryptField(raw).trim().length > 0;
}
