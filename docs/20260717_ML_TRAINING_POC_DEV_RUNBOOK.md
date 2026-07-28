# ML Training PoC — Dev/GPU Environment Runbook

- **Date**: 2026-07-17
- **Status**: actionable runbook — execute on the dev box / GPU training image (NOT runnable in the sandbox)
- **Prereq reading**: `docs/20260717_DL_TRAINING_PLATFORM_SELECTION_AND_ARCHITECTURE.md` (design), package `backend/lib/galaxy/ai/ml_training/`
- **Branch**: `fix/dev-search-and-admet-routing` (commits `0cd286eba` skeleton, `ac823459c` routing layer)

## Why this is a separate runbook

The pure-Python layer (config / datasets / mlflow_tracker / executor_payload / cli /
orchestrator) is done and unit-tested (**43 pytest passing**). What remains needs a
real ML stack + GPU and therefore MUST be validated where it runs — per CLAUDE.md
"Review Code Before Testing — no speculative deploys", we do not write unvalidated
Chemprop/GPU code into the repo. This runbook is the validation gate: it contains the
reference code to drop in, then the exact commands to prove it works before committing.

Two concrete stubs to fill (both currently raise `NotImplementedError`):
- `chemprop_trainer._train_chemprop()` — the fit loop
- `chemprop_wrapper.ChempropModelWrapper._make_chemprop_predict()` — inference load

---

## Step 0 — Environment / image deps

The training + serving container image must add (pin versions against what the image
already has; chemprop 2.x pulls torch + lightning):

```
chemprop>=2.0,<3        # molecular GNN
torch                    # (transitive, GPU build on the image)
lightning                # (transitive via chemprop 2.x)
rdkit                    # featurization
scikit-learn             # metrics + sklearn_gbr baseline
mlflow                   # tracking/registry client
PyTDC                    # public dataset loading (tdc:hERG)
# serving image also:
bentoml
```

Sanity (on the image):
```bash
python -c "import chemprop, torch, rdkit, sklearn, mlflow; print('deps OK', torch.cuda.is_available())"
```

---

## Step 1 — Fill `_train_chemprop()` (reference; verify against pinned chemprop 2.x API)

Drop into `backend/lib/galaxy/ai/ml_training/chemprop_trainer.py`, replacing the
`raise NotImplementedError(...)` in `_train_chemprop`. **Verify every symbol against the
installed chemprop version** — the 2.x API moved between minor releases.

```python
def _train_chemprop(cfg, ds, artifact_dir):
    import numpy as np
    from lightning import pytorch as pl
    from chemprop import data, featurizers, models, nn
    from sklearn.metrics import roc_auc_score, mean_absolute_error

    hp = cfg.hyperparams
    pl.seed_everything(hp.seed)

    all_pts = [data.MoleculeDatapoint.from_smi(smi, np.array([y])) for smi, y in ds.rows]
    # scaffold or random split
    split = "SCAFFOLD_BALANCED" if cfg.dataset.split == "scaffold" else "RANDOM"
    tr_idx, va_idx, te_idx = data.make_split_indices(
        [p.mol for p in all_pts], split=split,
        sizes=(1 - cfg.dataset.val_frac - cfg.dataset.test_frac,
               cfg.dataset.val_frac, cfg.dataset.test_frac), seed=hp.seed)
    tr, va, te = data.split_data_by_indices(all_pts, tr_idx, va_idx, te_idx)

    feat = featurizers.SimpleMoleculeMolGraphFeaturizer()
    tr_ds, va_ds, te_ds = (data.MoleculeDataset(x, feat) for x in (tr, va, te))
    tr_dl = data.build_dataloader(tr_ds, batch_size=hp.batch_size)
    va_dl = data.build_dataloader(va_ds, batch_size=hp.batch_size, shuffle=False)
    te_dl = data.build_dataloader(te_ds, batch_size=hp.batch_size, shuffle=False)

    mp = nn.BondMessagePassing(depth=hp.depth, d_h=hp.hidden_size, dropout=hp.dropout)
    agg = nn.MeanAggregation()
    if cfg.task_type == "classification":
        ffn = nn.BinaryClassificationFFN(input_dim=mp.output_dim)
    else:
        ffn = nn.RegressionFFN(input_dim=mp.output_dim)
    model = models.MPNN(mp, agg, ffn, batch_norm=True)

    trainer = pl.Trainer(max_epochs=hp.epochs, accelerator="auto", devices=1,
                         enable_checkpointing=True, default_root_dir=artifact_dir,
                         enable_progress_bar=False)
    trainer.fit(model, tr_dl, va_dl)

    # metrics
    def _preds(dl):
        out = trainer.predict(model, dl)
        return np.concatenate([o.numpy().ravel() for o in out])
    metrics = {}
    if cfg.task_type == "classification":
        y_va = np.array([p.y[0] for p in va]); y_te = np.array([p.y[0] for p in te])
        if len(set(y_va)) > 1: metrics["val_auc"] = float(roc_auc_score(y_va, _preds(va_dl)))
        if len(set(y_te)) > 1: metrics["test_auc"] = float(roc_auc_score(y_te, _preds(te_dl)))
    else:
        y_te = np.array([p.y[0] for p in te])
        metrics["test_mae"] = float(mean_absolute_error(y_te, _preds(te_dl)))

    ckpt = str(Path(artifact_dir) / "model.ckpt")
    trainer.save_checkpoint(ckpt)
    import chemprop as _cp
    return TrainingResult(
        model_type="chemprop_gnn", artifact_dir=artifact_dir, metrics=metrics,
        n_train=len(tr), n_val=len(va), n_test=len(te),
        framework_version=f"chemprop=={_cp.__version__}",
        extra={"checkpoint": ckpt, "featurizer": "SimpleMoleculeMolGraphFeaturizer"},
    )
```

## Step 2 — Fill `_make_chemprop_predict()` (reference)

Replace the `raise NotImplementedError(...)` in
`chemprop_wrapper.ChempropModelWrapper._make_chemprop_predict`:

```python
def _make_chemprop_predict(self, manifest):
    import numpy as np
    from lightning import pytorch as pl
    from chemprop import data, featurizers, models
    model = models.MPNN.load_from_checkpoint(manifest["extra"]["checkpoint"])
    feat = featurizers.SimpleMoleculeMolGraphFeaturizer()
    trainer = pl.Trainer(accelerator="auto", devices=1, logger=False,
                         enable_progress_bar=False)

    def predict(smiles_list):
        pts = [data.MoleculeDatapoint.from_smi(s) for s in smiles_list]
        ds = data.MoleculeDataset(pts, feat)
        dl = data.build_dataloader(ds, batch_size=64, shuffle=False)
        out = np.concatenate([o.numpy().ravel() for o in trainer.predict(model, dl)])
        return {s: float(v) for s, v in zip(smiles_list, out)}

    return predict
```

Then extend `test_chemprop_wrapper.py`: change
`test_chemprop_artifact_load_is_serving_stub` to a real load+score test guarded by
`pytest.importorskip("chemprop")`.

---

## Step 3 — Local real run (offline, no S3), sklearn baseline first

> **✅ VALIDATED 2026-07-19 (local, no GPU).** The sklearn_gbr baseline was run
> end-to-end through the real code paths (RDKit featurization + real
> GradientBoosting fit + gate + registration into a real `CustomModelRegistry`
> + load-from-artifact inference + bento predict). Result on a 30-mol
> median-MolWt-split set: **test AUC 0.93**, gate pass → registered, heavy
> molecule (376 Da) scored 1.0 vs light (46 Da) 0.0 (signal learned), impossible
> gate (>1.0) correctly halted registration. Captured as a permanent regression
> guard: `tests/test_real_sklearn_e2e.py` (importorskip-guarded; part of the
> 62-passing suite). Only the chemprop-specific fit/inference below still needs
> the GPU image.

Fastest signal — proves the whole orchestrator with a REAL model (no GPU):
```bash
cd backend
python -m galaxy.ai.ml_training.cli \
  --dataset fixture:herg --model-type sklearn_gbr --task-type classification \
  --metric auc --gate-threshold 0.5 --out /tmp/mlt_run
cat /tmp/mlt_run/metrics.json      # expect metrics.test_auc + gate.status
```
Pass criteria: `metrics.json` written, `gate.gates[0].status == "pass"`, exit 0.

Then the real Chemprop run on public hERG:
```bash
python -m galaxy.ai.ml_training.cli \
  --dataset tdc:hERG --model-type chemprop_gnn --task-type classification \
  --epochs 30 --metric auc --gate-threshold 0.75 --out /tmp/mlt_herg
```
Pass criteria: `model.ckpt` produced; `val_auc`/`test_auc` present; hERG AUC should land
~0.80–0.88 (Chemprop-RDKit reference). If AUC ≪ 0.75, gate halts → NOT registered
(correct behaviour), investigate data/hyperparams before promoting.

---

## Step 4 — End-to-end via the executor path (Batch GPU)

1. Stage the dataset to S3 (Batch workers can't see local paths):
   `aws s3 cp herg.csv s3://biomate-nextflow-work/ml_training/herg.csv`
2. Build the execute payload and POST it:
   ```python
   from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec
   from galaxy.ai.ml_training.executor_payload import build_execute_request
   cfg = TrainingConfig(name="hERG blocker (chemprop)",
                        dataset=DatasetSpec(s3_uri="s3://biomate-nextflow-work/ml_training/herg.csv",
                                            target_col="Y"),
                        gate_threshold=0.75)
   req = build_execute_request(cfg, user_id="<uid>")
   # POST req to http://localhost:8081/api/nextflow/execute
   ```
3. Poll `GET /api/nextflow/status/{run_id}` → status `completed`; confirm the TRAIN
   process landed on the **GPU** Batch queue (label `process_gpu`).
4. Verify `metrics.json` in the run's S3 output prefix.

Pass criteria: run `completed`; GPU queue used; metrics + artifact in S3; a metric-gate
failure surfaces as an SSE `qc_gate_results` event (design §4.3) in the workflow panel.

---

## Step 5 — MLflow tracking server (once, minimal)

```bash
# on an EC2 box; SQLite backend + S3 artifacts (upgrade to Postgres later)
mlflow server --host 0.0.0.0 --port 5001 \
  --backend-store-uri sqlite:////opt/biomate/mlflow/mlflow.db \
  --default-artifact-root s3://biomate-nextflow-work/mlflow-artifacts
export MLFLOW_TRACKING_URI=http://<host>:5001    # set in the training container env
```
Re-run Step 3/4 with `MLFLOW_TRACKING_URI` set; confirm the run + registered model
appear in the MLflow UI. (Without it, `MLflowTracker` degrades to in-memory no-op —
training still works, just untracked.)

---

## Step 6 — Wire `domain=ml_training` into chat routing (higher blast radius — do last, review first)

So a chat request ("train an hERG blocker classifier on this data") surfaces the training
workflow card.

> **✅ DONE (commit 551221f49) — feature-flagged, default OFF.** The hook is wired into
> `ai_assistant.generate_workflow_unified` (right after the "Starting" log). It delegates to
> `routing.route_ml_training_result(user_intent)`, which returns None when
> `ML_TRAINING_ROUTING != "1"`, for non-training intents, and for training requests it can't
> resolve a dataset for — so it is inert until the flag is set and can only ADD a route.
> Lazy-imported + try/guarded → any failure degrades to the normal search path. Contract is
> unit-tested (`tests/test_router_hook.py`, 7 cases). Frontend needs zero change:
> `to_workflow_ga()` emits the param contract `NextflowWorkflowViewer` already renders.

**To see it live on test/dev:** deploy the backend, then set `ML_TRAINING_ROUTING=1` in the
Galaxy container env and restart. A chat message like "train a classifier for hERG blockers"
will then return the ml_training card; "predict hERG for aspirin" still routes normally.
(For chemprop_gnn the training itself needs the GPU image + Steps 1-2 above; ludwig_tabular
already runs on CPU.)

---

## Definition of done

- [ ] chemprop fit + inference stubs filled and validated against pinned chemprop version
- [ ] sklearn baseline real run green (Step 3)
- [ ] chemprop hERG real run: AUC ~0.80–0.88, gate behaves (Step 3)
- [ ] executor/Batch GPU end-to-end green, metrics+artifact in S3 (Step 4)
- [ ] MLflow run + registered model visible (Step 5)
- [ ] chat routing surfaces the training card (Step 6, reviewed)
- [ ] pytest still green (add chemprop-guarded tests); commit + push + sync
- [ ] session doc in `docs/` capturing results + screenshots
