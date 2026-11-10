"""Explicit, train-only evaluation protocols. No model or data downloads on import."""
import numpy as np


def fold_standardize(train, test):
    """Fit statistics on labelled adaptation/training rows only; inputs already log/CLR transformed."""
    train, test = np.asarray(train), np.asarray(test)
    if train.ndim != 2 or test.ndim != 2 or train.shape[1] != test.shape[1] or not len(train):
        raise ValueError('Expected nonempty training matrix and feature-aligned test matrix')
    if not np.isfinite(train).all() or not np.isfinite(test).all():
        raise ValueError('Nonfinite features')
    mu = train.mean(axis=0); scale = train.std(axis=0) + 1e-6
    return ((train-mu)/scale).astype(np.float32), ((test-mu)/scale).astype(np.float32)


def validate_checkpoint_parameters(model, state):
    """Trainable checkpoints must include every trainable parameter, including the encoder.

    Frozen parameters/buffers may be omitted by the existing save format. Shape errors
    and unexpected keys are separately rejected by the caller/load_state_dict.
    """
    missing = [name for name, p in model.named_parameters() if p.requires_grad and name not in state]
    if missing:
        raise ValueError('Missing trainable checkpoint parameters: ' + ', '.join(missing[:20]))


def adaptation_split(y, k, seed):
    """Reserve >=1 query cell for every included class; omit singleton classes explicitly."""
    y = np.asarray(y)
    if k < 1: raise ValueError('k must be positive')
    rng = np.random.RandomState(seed); adapt = []; query = []; omitted = []
    for c in np.unique(y):
        ix = np.flatnonzero(y == c)
        if len(ix) < 2:
            omitted.extend(ix.tolist()); continue
        picked = rng.choice(ix, min(k, max(1, len(ix)//2)), replace=False)
        adapt.extend(picked.tolist()); query.extend(np.setdiff1d(ix, picked).tolist())
    return np.asarray(adapt, dtype=int), np.asarray(query, dtype=int), np.asarray(omitted, dtype=int)


def within_study_fewshot(X, y, study, k, seed):
    """Separate classifier per held-out study; equal-study summary, explicit skipped studies."""
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import f1_score
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    X, y, study = np.asarray(X), np.asarray(y), np.asarray(study)
    rows = []
    for s in np.unique(study):
        ix = np.flatnonzero(study == s); a, q, omitted = adaptation_split(y[ix], k, seed)
        row = dict(study=str(s), n_adapt=len(a), n_query=len(q), n_singleton_excluded=len(omitted))
        if len(np.unique(y[ix[a]])) < 2 or not len(q):
            row.update(status='skipped', reason='fewer than two eligible classes or no query cells')
        else:
            clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=500))
            clf.fit(X[ix[a]], y[ix[a]])
            row.update(status='ok', macroF1=float(f1_score(y[ix[q]], clf.predict(X[ix[q]]), average='macro')))
        rows.append(row)
    scores = [r['macroF1'] for r in rows if r['status']=='ok']
    return dict(mean_study_macroF1=float(np.mean(scores)) if scores else None, n_studies_scored=len(scores), studies=rows)
