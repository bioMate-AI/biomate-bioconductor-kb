import { describe, expect, it } from 'vitest';
import { looksLikeHollowFindings, scoreFindingsSampleName } from './findings-quality';
import { looksLikeMlTrainingFluff, parseMlTrainingFindings } from './ml-training-findings';

const LIVE_METRICS = `{
  "name": "potency predictor",
  "metrics": { "test_mae": 0.7920467257499695, "val_mae": 0.9433045983314514 },
  "gate": { "gates": [{ "name": "mae", "measured": 0.9433045983314514, "threshold": null, "status": "pass", "direction": "lower_is_better", "reason": "no_gate_configured" }] }
}`;

const LIVE_PROGRESS = `{
  "best_eval_test_metrics": { "combined": { "r2": 0.37242525815963745 } },
  "best_eval_validation_metrics": { "combined": { "r2": 0.4462311863899231 } },
  "best_eval_train_metrics": { "combined": { "r2": 0.3006513714790344 } }
}`;

const BAD_SIDECAR = {
  summary: "A potency predictor model was configured with Ludwig's deep learning framework, incorporating multimodal input processing through a concat combiner layer",
  key_results: [
    { metric: 'Combiner architecture type', value: 'concat', interpretation: '…', source_file: 'model_hyperparameters.json' },
  ],
  caveats: ['No model training or validation performance metrics are present in provided files'],
};

describe('scoreFindingsSampleName', () => {
  it('ranks trainer metrics / toxicity / DESeq2 above Ludwig bookkeeping', () => {
    const names = [
      'model_hyperparameters.json',
      'qc_events.json',
      'results/metrics.json',
      'toxicity_report.json',
      'deseq2_results.tsv',
      '.nextflow.log',
      'training_progress.json',
      'manifest.json',
    ];
    const ranked = [...names].sort((a, b) => scoreFindingsSampleName(b) - scoreFindingsSampleName(a));
    // Score-card files must outrank Ludwig / Nextflow bookkeeping.
    for (const good of ['results/metrics.json', 'manifest.json', 'toxicity_report.json', 'deseq2_results.tsv', 'training_progress.json']) {
      expect(ranked.indexOf(good)).toBeLessThan(ranked.indexOf('model_hyperparameters.json'));
      expect(ranked.indexOf(good)).toBeLessThan(ranked.indexOf('qc_events.json'));
      expect(ranked.indexOf(good)).toBeLessThan(ranked.indexOf('.nextflow.log'));
    }
    expect(scoreFindingsSampleName('results/metrics.json')).toBeGreaterThan(scoreFindingsSampleName('model_hyperparameters.json'));
  });

  it('ranks vina results and boltz qc_metrics above Nextflow bookkeeping', () => {
    expect(scoreFindingsSampleName('docking_autodock_vina_results.json'))
      .toBeGreaterThan(scoreFindingsSampleName('.nextflow.log'));
    expect(scoreFindingsSampleName('qc_metrics.json'))
      .toBeGreaterThan(scoreFindingsSampleName('model_hyperparameters.json'));
    expect(scoreFindingsSampleName('boltz_summary.json'))
      .toBeGreaterThan(scoreFindingsSampleName('_timeline.html'));
  });

  it('ranks cryo FSC / workflow_summary above Nextflow bookkeeping', () => {
    expect(scoreFindingsSampleName('fsc_validation.json'))
      .toBeGreaterThan(scoreFindingsSampleName('.nextflow.log'));
    expect(scoreFindingsSampleName('workflow_summary.json'))
      .toBeGreaterThan(scoreFindingsSampleName('model_hyperparameters.json'));
  });
});

describe('looksLikeHollowFindings (class gate)', () => {
  it('flags the live Ludwig fluff sidecar even without an ml_training run tag', () => {
    expect(looksLikeHollowFindings(BAD_SIDECAR)).toBe(true);
    expect(looksLikeMlTrainingFluff(BAD_SIDECAR)).toBe(true);
  });

  it('flags source_file pointing at model_hyperparameters', () => {
    expect(looksLikeHollowFindings({
      summary: 'Training finished.',
      key_results: [{ metric: 'layers', value: '3', source_file: 'model_hyperparameters.json' }],
      caveats: [],
    })).toBe(true);
  });

  it('flags empty summary that redirects to Outputs for the numbers', () => {
    expect(looksLikeHollowFindings({
      summary: 'See the Outputs panel to retrieve the metrics.',
      key_results: [],
      caveats: [],
    })).toBe(true);
  });

  it('accepts metrics-first findings', () => {
    expect(looksLikeHollowFindings({
      summary: 'potency predictor finished. Key scores: test MAE=0.7920.',
      key_results: [{ metric: 'Test MAE', value: '0.7920', source_file: 'metrics.json' }],
      caveats: ['Scores are read directly from the trainer metrics.json'],
    })).toBe(false);
  });

  it('flags docking/structure summaries that admit missing scores with empty key_results', () => {
    expect(looksLikeHollowFindings({
      summary: 'Docking finished but no affinities could be extracted.',
      key_results: [],
      caveats: [],
    })).toBe(true);
    expect(looksLikeHollowFindings({
      summary: 'Structure prediction completed; confidence metrics are missing.',
      key_results: [],
      caveats: ['No pLDDT scores present'],
    })).toBe(true);
  });
});

describe('parseMlTrainingFindings — report / chip order', () => {
  it('puts Test/Validation MAE before Gate so headline chips prefer scores', () => {
    const parsed = parseMlTrainingFindings([
      { name: 'metrics.json', content: LIVE_METRICS },
      { name: 'training_progress.json', content: LIVE_PROGRESS },
    ], 'potency predictor');
    expect(parsed).not.toBeNull();
    const metrics = parsed!.findings.key_results.map(k => k.metric);
    expect(metrics.indexOf('Test MAE')).toBeLessThan(metrics.indexOf('Gate · MAE'));
    expect(metrics.indexOf('Validation MAE')).toBeLessThan(metrics.indexOf('Gate · MAE'));
    // Report table contents
    const mdRows = parsed!.findings.key_results
      .map(k => `| ${k.metric} | ${k.value} | ${k.source_file} |`)
      .join('\n');
    expect(mdRows).toMatch(/Test MAE \| 0\.7920 \| metrics\.json/);
    expect(mdRows).toMatch(/Validation MAE \| 0\.9433 \| metrics\.json/);
    expect(mdRows).not.toMatch(/combiner/i);
  });

  it('returns null when only Ludwig fluff files are sampled (missing metrics)', () => {
    expect(parseMlTrainingFindings([
      { name: 'model_hyperparameters.json', content: '{"combiner":{"type":"concat"}}' },
      { name: 'training_set_metadata.json', content: '{"MolLogP":{"mean":3.1}}' },
    ])).toBeNull();
  });
});
