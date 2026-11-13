import { describe, expect, it } from 'vitest';
import {
  findMetricsFile,
  looksLikeMlTrainingFluff,
  parseMlTrainingFindings,
} from './ml-training-findings';

/** Live potency-predictor metrics.json from session chat-1794589821204-kwkyrwqu5. */
const LIVE_METRICS = `{
  "name": "potency predictor",
  "metrics": {
    "test_mae": 0.7920467257499695,
    "val_mae": 0.9433045983314514
  },
  "gate": {
    "gates": [
      {
        "name": "mae",
        "measured": 0.9433045983314514,
        "threshold": null,
        "status": "pass",
        "direction": "lower_is_better",
        "reason": "no_gate_configured"
      }
    ]
  }
}`;

/** Live Ludwig nesting: R² lives under the target column (pIC50), not combined. */
const LIVE_PROGRESS = `{
  "best_eval_test_metrics": { "combined": { "loss": 1.07 }, "pIC50": { "loss": 1.07, "r2": 0.37242525815963745 } },
  "best_eval_validation_metrics": { "combined": { "loss": 1.27 }, "pIC50": { "loss": 1.27, "r2": 0.4462311863899231 } },
  "best_eval_train_metrics": { "combined": { "loss": 1.20 }, "pIC50": { "loss": 1.20, "r2": 0.3006513714790344 } }
}`;

const LIVE_MANIFEST = `{
  "name": "potency predictor",
  "model_type": "ludwig_tabular",
  "task_type": "regression",
  "metrics": { "test_mae": 0.7920467257499695, "val_mae": 0.9433045983314514 },
  "extra": {
    "target_col": "pIC50",
    "split": {
      "requested": "scaffold",
      "method": "bemis_murcko_scaffold",
      "n_train": 1211,
      "n_val": 151,
      "n_test": 151
    }
  }
}`;

/** The bad sidecar that was served for this session (architecture fluff). */
const BAD_SIDECAR = {
  summary: "A potency predictor model was configured with Ludwig's deep learning framework, incorporating multimodal input processing through a concat combiner layer",
  key_results: [
    { metric: 'Combiner architecture type', value: 'concat', interpretation: '…', source_file: 'model_hyperparameters.json' },
    { metric: 'MolLogP training set mean', value: '3.12', interpretation: '…', source_file: 'training_set_metadata.json' },
  ],
  caveats: ['No model training or validation performance metrics are present in provided files'],
};

describe('parseMlTrainingFindings', () => {
  it('surfaces test/val MAE + gate + R² + scaffold split from real potency outputs', () => {
    const files = [
      { name: 'model_hyperparameters.json', content: '{"combiner":{"type":"concat","output_size":300}}' },
      { name: 'training_set_metadata.json', content: '{"MolLogP":{"mean":3.1,"std":1.2}}' },
      { name: 'metrics.json', content: LIVE_METRICS },
      { name: 'training_progress.json', content: LIVE_PROGRESS },
      { name: 'manifest.json', content: LIVE_MANIFEST },
    ];
    const parsed = parseMlTrainingFindings(files, 'potency predictor');
    expect(parsed).not.toBeNull();
    const f = parsed!.findings;
    expect(f.summary).toMatch(/test MAE=0\.7920/);
    expect(f.summary).toMatch(/validation MAE=0\.9433/);
    expect(f.summary).toMatch(/Key Results|metrics\.json/i);
    expect(f.key_results.find(k => k.metric === 'Test MAE')?.value).toBe('0.7920');
    expect(f.key_results.find(k => k.metric === 'Validation MAE')?.value).toBe('0.9433');
    expect(f.key_results.some(k => /Gate/i.test(k.metric))).toBe(true);
    // Scores before gate — Findings chips / report lead with what users need
    const names = f.key_results.map(k => k.metric);
    expect(names.indexOf('Test MAE')).toBeLessThan(names.findIndex(m => /Gate/i.test(m)));
    expect(f.key_results.find(k => /Test R/i.test(k.metric))?.value).toBe('0.3724');
    expect(f.key_results.find(k => k.metric === 'Data split')?.value).toMatch(/bemis_murcko_scaffold/);
    expect(f.key_results.find(k => k.metric === 'Data split')?.value).toMatch(/train=1211/);
    // Must NOT elevate architecture fluff
    expect(f.key_results.every(k => !/combiner|MolLogP training set/i.test(k.metric))).toBe(true);
    expect(f.evidence_version).toBe('ml-training-metrics-v1');
  });

  it('finds metrics.json even under a nested path name', () => {
    expect(findMetricsFile([
      { name: 'results/metrics.json', content: LIVE_METRICS },
    ])?.name).toBe('results/metrics.json');
  });

  it('returns null when no trainer metrics are present', () => {
    expect(parseMlTrainingFindings([
      { name: 'model_hyperparameters.json', content: '{"combiner":{"type":"concat"}}' },
    ])).toBeNull();
  });
});

describe('looksLikeMlTrainingFluff', () => {
  it('flags the live bad sidecar', () => {
    expect(looksLikeMlTrainingFluff(BAD_SIDECAR)).toBe(true);
  });

  it('accepts a metrics-first findings object', () => {
    expect(looksLikeMlTrainingFluff({
      summary: 'potency predictor finished. Key scores: test MAE=0.7920. Read the Key Results table below.',
      key_results: [{ metric: 'Test MAE', value: '0.7920', interpretation: 'Hold-out', source_file: 'metrics.json' }],
      caveats: ['Scores are read directly from the trainer metrics.json'],
    })).toBe(false);
  });
});
