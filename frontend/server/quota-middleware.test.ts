import { describe, it, expect, afterEach } from 'vitest';
import { quotaEnforcementEnabled } from './quota-middleware';

/**
 * Configurable quota enforcement (deployment-aware):
 *   - enforce on the AWS SaaS platform
 *   - skip on-premise (customer runs own compute; no SaaS metering)
 *   - explicit BIOMATE_QUOTA_ENFORCEMENT=on|off overrides the inference
 * quotaEnforcementEnabled() reads process.env at call time, so per-test env edits apply.
 */
describe('quotaEnforcementEnabled — deployment-configurable quota', () => {
  const saved = { ...process.env };
  afterEach(() => {
    process.env = { ...saved };
  });

  function setEnv(e: Record<string, string | undefined>) {
    delete process.env.BIOMATE_QUOTA_ENFORCEMENT;
    delete process.env.S3_ENDPOINT_URL;
    delete process.env.NEXTFLOW_USE_AWS;
    for (const [k, v] of Object.entries(e)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }

  it('enforces on AWS SaaS (NEXTFLOW_USE_AWS=true, no MinIO)', () => {
    setEnv({ NEXTFLOW_USE_AWS: 'true' });
    expect(quotaEnforcementEnabled()).toBe(true);
  });

  it('skips on-prem when a MinIO endpoint is set (S3_ENDPOINT_URL)', () => {
    setEnv({ NEXTFLOW_USE_AWS: 'true', S3_ENDPOINT_URL: 'http://minio:9000' });
    expect(quotaEnforcementEnabled()).toBe(false);
  });

  it('skips on-prem when not running on AWS Batch', () => {
    setEnv({});
    expect(quotaEnforcementEnabled()).toBe(false);
  });

  it('honors explicit BIOMATE_QUOTA_ENFORCEMENT=off even on AWS', () => {
    setEnv({ NEXTFLOW_USE_AWS: 'true', BIOMATE_QUOTA_ENFORCEMENT: 'off' });
    expect(quotaEnforcementEnabled()).toBe(false);
  });

  it('honors explicit BIOMATE_QUOTA_ENFORCEMENT=on even on-prem', () => {
    setEnv({ S3_ENDPOINT_URL: 'http://minio:9000', BIOMATE_QUOTA_ENFORCEMENT: 'on' });
    expect(quotaEnforcementEnabled()).toBe(true);
  });

  it('accepts true/false/1/0/yes/no spellings of the override', () => {
    for (const v of ['true', '1', 'yes']) { setEnv({ BIOMATE_QUOTA_ENFORCEMENT: v }); expect(quotaEnforcementEnabled()).toBe(true); }
    for (const v of ['false', '0', 'no']) { setEnv({ NEXTFLOW_USE_AWS: 'true', BIOMATE_QUOTA_ENFORCEMENT: v }); expect(quotaEnforcementEnabled()).toBe(false); }
  });
});
