import { it, expect } from 'vitest';
import { hasPersonalSkillAccess } from './skill-access';

it('never treats absent, blank or structured credentials as personal skill access', () => {
  for (const user of [undefined, {}, {galaxyApiKey:null}, {galaxyApiKey:''}, {galaxyApiKey:'   '}, {galaxyApiKey:{key:'other'}}]) {
    expect(hasPersonalSkillAccess(user)).toBe(false);
  }
  expect(hasPersonalSkillAccess({galaxyApiKey:'legacy-personal-key'})).toBe(true);
});

it('does not turn decryption failure into shared-account access', () => {
  expect(() => hasPersonalSkillAccess({galaxyApiKey:'bad:bad:bad'})).toThrow();
});
