import { describe, it, expect, afterEach } from 'vitest';
import { quotaEnforcementEnabled } from './quota-middleware';

/**
 * Billing quota is FAIL-SAFE: enforced by default, disabled ONLY via an explicit opt-out
 * (BIOMATE_QUOTA_ENFORCEMENT=off|false|0|no OR BIOMATE_DEPLOYMENT=onprem). Infra vars
 * (NEXTFLOW_USE_AWS / S3_ENDPOINT_URL) must NEVER silently disable billing.
 * quotaEnforcementEnabled() reads process.env at call time, so per-test env edits apply.
 */
describe('quotaEnforcementEnabled — fail-safe, explicit opt-out only', () => {
  const saved = { ...process.env };
  afterEach(() => { process.env = { ...saved }; });

  function setEnv(e: Record<string, string | undefined>) {
    for (const k of ['BIOMATE_QUOTA_ENFORCEMENT', 'BIOMATE_DEPLOYMENT', 'S3_ENDPOINT_URL', 'NEXTFLOW_USE_AWS']) delete process.env[k];
    for (const [k, v] of Object.entries(e)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  }

  it('enforces by DEFAULT (no flags set)', () => {
    setEnv({});
    expect(quotaEnforcementEnabled()).toBe(true);
  });

  it('skips when BIOMATE_QUOTA_ENFORCEMENT=off', () => {
    setEnv({ BIOMATE_QUOTA_ENFORCEMENT: 'off' });
    expect(quotaEnforcementEnabled()).toBe(false);
  });

  it('skips when BIOMATE_DEPLOYMENT=onprem (also on-prem / on_prem)', () => {
    for (const v of ['onprem', 'on-prem', 'on_prem', 'onpremise', 'on-premise']) {
      setEnv({ BIOMATE_DEPLOYMENT: v });
      expect(quotaEnforcementEnabled()).toBe(false);
    }
  });

  it('FAIL-SAFE: infra vars do NOT silently disable quota (regression for the fail-open bug)', () => {
    // These used to turn quota OFF via inference — they must NOT anymore.
    setEnv({ S3_ENDPOINT_URL: 'http://minio:9000' });
    expect(quotaEnforcementEnabled()).toBe(true);
    setEnv({ NEXTFLOW_USE_AWS: '1' });   // truthy spelling that the old === 'true' missed
    expect(quotaEnforcementEnabled()).toBe(true);
    setEnv({ NEXTFLOW_USE_AWS: 'yes' });
    expect(quotaEnforcementEnabled()).toBe(true);
    setEnv({});                          // unset NEXTFLOW_USE_AWS (old code inferred on-prem → off)
    expect(quotaEnforcementEnabled()).toBe(true);
  });

  it('explicit opt-out wins over infra vars; explicit opt-in wins over deployment flag', () => {
    setEnv({ S3_ENDPOINT_URL: 'http://minio:9000', BIOMATE_QUOTA_ENFORCEMENT: 'off' });
    expect(quotaEnforcementEnabled()).toBe(false);
    setEnv({ BIOMATE_DEPLOYMENT: 'onprem', BIOMATE_QUOTA_ENFORCEMENT: 'on' });
    expect(quotaEnforcementEnabled()).toBe(true);
  });

  it('accepts on/off spellings (on,true,1,yes / off,false,0,no)', () => {
    for (const v of ['on', 'true', '1', 'yes']) { setEnv({ BIOMATE_QUOTA_ENFORCEMENT: v }); expect(quotaEnforcementEnabled()).toBe(true); }
    for (const v of ['off', 'false', '0', 'no']) { setEnv({ BIOMATE_QUOTA_ENFORCEMENT: v }); expect(quotaEnforcementEnabled()).toBe(false); }
  });
});
