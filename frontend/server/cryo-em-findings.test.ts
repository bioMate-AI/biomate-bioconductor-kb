import { describe, expect, it } from 'vitest';
import { parseCryoEmFindings } from './cryo-em-findings';

const CRYO_FILES = [
  {
    name: 'fsc_validation.json',
    content: JSON.stringify({ fsc_0143_resolution: 3.42, cs_job_uid: 'J20', real_mode: true }),
  },
  {
    name: 'workflow_summary.json',
    content: JSON.stringify({
      workflow: 'cryosparc_standard_spa',
      pixel_size_angstroms: 1.96,
      voltage_kv: 300,
      symmetry: 'C1',
      steps_completed: 23,
    }),
  },
  {
    name: 'motion_report_batch_0000.json',
    content: JSON.stringify({ num_micrographs: 20, real_mode: true }),
  },
  {
    name: 'picking_report_batch_0000.json',
    content: JSON.stringify({ num_particles: 27621, particle_diameter_angstroms: 150 }),
  },
  {
    name: 'extract_report.json',
    content: JSON.stringify({ num_particles: 37157, box_size_pix: 192 }),
  },
];

describe('parseCryoEmFindings', () => {
  it('leads Key Results with FSC + particle counts (not hollow pipeline prose)', () => {
    const f = parseCryoEmFindings(CRYO_FILES, 'cryosparc_standard_spa');
    expect(f).not.toBeNull();
    expect(f!.evidence_version).toBe('cryo-em-metrics-v1');
    expect(f!.summary).toMatch(/FSC 0\.143=3\.42/);
    expect(f!.summary).toMatch(/Key Results/);
    const metrics = f!.key_results.map(k => k.metric);
    expect(metrics).toEqual(expect.arrayContaining([
      'FSC 0.143 resolution',
      'particles picked',
      'particles extracted (R2)',
      'micrographs',
      'pixel size',
    ]));
    expect(f!.key_results.find(k => k.metric === 'FSC 0.143 resolution')!.value).toBe('3.42 Å');
  });

  it('still returns acquisition score card when FSC resolution absent (live empty fsc_validation)', () => {
    const files = CRYO_FILES.map(f =>
      f.name === 'fsc_validation.json'
        ? { ...f, content: JSON.stringify({ fsc_curve: [], cs_job_uid: 'J20' }) }
        : f,
    );
    const parsed = parseCryoEmFindings(files, 'cryosparc_standard_spa');
    expect(parsed).not.toBeNull();
    expect(parsed!.key_results.some(k => /FSC/i.test(k.metric))).toBe(false);
    expect(parsed!.key_results.some(k => /picked|extracted|micrographs|pixel/i.test(k.metric))).toBe(true);
    expect(parsed!.summary).toMatch(/Key Results/);
  });

  it('returns null when no quantitative cryo reports present', () => {
    expect(parseCryoEmFindings([
      { name: 'readme.txt', content: 'pipeline finished' },
    ])).toBeNull();
  });
});
