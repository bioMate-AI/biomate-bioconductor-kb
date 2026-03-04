#!/usr/bin/env nextflow
/*
 * pharmacology/qsar_rf_model
 * Quantitative Structure-Activity Relationship (QSAR) modelling using
 * Random Forest with 5-fold cross-validation.
 *
 * Input:  CSV with columns: smiles, <target_property>
 * Output: qsar_results.json with cv_r2_score, cv_rmse, n_compounds, model_type
 *
 * Quality gate (qc_trace_monitor.py):
 *   cv_r2_score < 0.5 → SILVER blocking (Golbraikh & Tropsha 2002 J Mol Graph Model 20:269)
 *   n_compounds < 50  → BRONZE advisory
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.input_csv         = null          // Path to CSV with smiles + target columns
params.target_column     = 'pIC50'       // Name of the target property column
params.smiles_column     = 'smiles'      // Name of the SMILES column
params.n_folds           = 5            // Cross-validation folds
params.n_estimators      = 200          // RF trees
params.random_state      = 42

process QSAR_RF_MODEL {
    tag "qsar_rf"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    path input_csv

    output:
    path "qsar_results.json",    emit: results
    path "qsar_model_report.txt", emit: report
    path "versions.yml",         emit: versions

    script:
    """
    #!/usr/bin/env python3
    import json
    import os
    import sys
    import csv
    import math

    target_col    = "${params.target_column}"
    smiles_col    = "${params.smiles_column}"
    n_folds       = int("${params.n_folds}")
    n_estimators  = int("${params.n_estimators}")
    random_state  = int("${params.random_state}")
    input_path    = "${input_csv}"

    # ── 1. Load data ──────────────────────────────────────────────────────────
    rows = []
    with open(input_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                smiles = row[smiles_col].strip()
                target = float(row[target_col])
                rows.append((smiles, target))
            except (KeyError, ValueError):
                continue

    n_compounds = len(rows)
    print(f"Loaded {n_compounds} compounds with target '{target_col}'", file=sys.stderr)

    results = {
        "success": False,
        "model_type": "random_forest",
        "target_property": target_col,
        "n_compounds": n_compounds,
        "n_folds": n_folds,
        "n_estimators": n_estimators,
    }

    if n_compounds < 10:
        results["error"] = f"Too few compounds ({n_compounds}); need at least 10 for QSAR."
        with open("qsar_results.json", "w") as f:
            json.dump(results, f, indent=2)
        with open("qsar_model_report.txt", "w") as f:
            f.write(f"ERROR: {results['error']}\\n")
        print(f"ERROR: {results['error']}", file=sys.stderr)
        sys.exit(1)

    # ── 2. Featurise with RDKit Morgan fingerprints ───────────────────────────
    try:
        import subprocess, shutil
        venv_dir = "/tmp/qsar_venv"
        if os.path.exists(venv_dir):
            shutil.rmtree(venv_dir)
        subprocess.run([sys.executable, "-m", "venv", venv_dir],
                       capture_output=True, check=True)
        venv_py = os.path.join(venv_dir, "bin", "python")
        subprocess.run([venv_py, "-m", "pip", "install", "-q", "--no-cache-dir",
                        "numpy<2", "rdkit", "scikit-learn"],
                       capture_output=True, check=True)
    except Exception as e:
        print(f"WARNING: Could not set up venv ({e}). Using fallback features.", file=sys.stderr)
        venv_py = sys.executable  # fallback: may lack rdkit

    # Write data for subprocess
    import tempfile
    data_file = "/tmp/qsar_data.json"
    with open(data_file, "w") as f:
        json.dump({
            "rows": rows,
            "n_folds": n_folds,
            "n_estimators": n_estimators,
            "random_state": random_state,
        }, f)

    script_content = '''
import sys, json, math, random
import numpy as np

with open(sys.argv[1]) as f:
    cfg = json.load(f)

rows = cfg["rows"]
n_folds = cfg["n_folds"]
n_estimators = cfg["n_estimators"]
random_state = cfg["random_state"]

smiles_list = [r[0] for r in rows]
targets = [r[1] for r in rows]

# Featurise: Morgan fingerprints (radius 2, 1024 bits)
try:
    from rdkit import Chem
    from rdkit.Chem import AllChem
    X = []
    valid_idx = []
    for i, smi in enumerate(smiles_list):
        mol = Chem.MolFromSmiles(smi)
        if mol:
            fp = AllChem.GetMorganFingerprintAsBitVect(mol, radius=2, nBits=1024)
            X.append(list(fp))
            valid_idx.append(i)
    X = np.array(X)
    y = np.array([targets[i] for i in valid_idx])
    featurizer = "morgan_fp_r2_1024"
except Exception as e:
    print(f"RDKit unavailable ({e}), using random features (mock mode)", file=sys.stderr)
    # Mock mode: random features for CI/testing
    rng = random.Random(random_state)
    n = len(rows)
    X = np.array([[rng.gauss(0, 1) for _ in range(64)] for _ in range(n)])
    y = np.array(targets)
    featurizer = "mock_random"

n = len(X)
print(f"Features: {X.shape[1]}, Compounds: {n}, Featurizer: {featurizer}", file=sys.stderr)

from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import KFold
from sklearn.metrics import r2_score, mean_squared_error

kf = KFold(n_splits=n_folds, shuffle=True, random_state=random_state)
r2_scores, rmse_scores = [], []
for train_idx, val_idx in kf.split(X):
    X_train, X_val = X[train_idx], X[val_idx]
    y_train, y_val = y[train_idx], y[val_idx]
    model = RandomForestRegressor(n_estimators=n_estimators, random_state=random_state)
    model.fit(X_train, y_train)
    preds = model.predict(X_val)
    r2_scores.append(r2_score(y_val, preds))
    rmse_scores.append(math.sqrt(mean_squared_error(y_val, preds)))

cv_r2 = round(float(np.mean(r2_scores)), 4)
cv_rmse = round(float(np.mean(rmse_scores)), 4)
cv_r2_std = round(float(np.std(r2_scores)), 4)

print(json.dumps({
    "cv_r2_score": cv_r2,
    "cv_rmse": cv_rmse,
    "cv_r2_std": cv_r2_std,
    "n_compounds": n,
    "featurizer": featurizer,
}))
'''

    import subprocess
    script_file = "/tmp/run_qsar.py"
    with open(script_file, "w") as f:
        f.write(script_content)

    proc = subprocess.run([venv_py, script_file, data_file],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        results["error"] = proc.stderr[-2000:]
        with open("qsar_results.json", "w") as f:
            json.dump(results, f, indent=2)
        with open("qsar_model_report.txt", "w") as f:
            f.write(f"QSAR modelling failed:\\n{proc.stderr}\\n")
        sys.exit(1)

    cv_output = json.loads(proc.stdout.strip())

    results.update({
        "success": True,
        "cv_r2_score": cv_output["cv_r2_score"],
        "cv_rmse": cv_output["cv_rmse"],
        "cv_r2_std": cv_output.get("cv_r2_std", 0.0),
        "n_compounds": cv_output["n_compounds"],
        "featurizer": cv_output.get("featurizer", "unknown"),
    })

    with open("qsar_results.json", "w") as f:
        json.dump(results, f, indent=2)

    with open("qsar_model_report.txt", "w") as f:
        f.write(f"QSAR Random Forest Model Report\\n")
        f.write(f"{'='*40}\\n")
        f.write(f"Target property : {target_col}\\n")
        f.write(f"Compounds       : {results['n_compounds']}\\n")
        f.write(f"Featurizer      : {results.get('featurizer')}\\n")
        f.write(f"CV folds        : {n_folds}\\n")
        f.write(f"RF estimators   : {n_estimators}\\n")
        f.write(f"\\nResults:\\n")
        f.write(f"  CV R²   : {results['cv_r2_score']:.4f} (±{results['cv_r2_std']:.4f})\\n")
        f.write(f"  CV RMSE : {results['cv_rmse']:.4f}\\n")
        gate_status = "PASS" if results["cv_r2_score"] >= 0.5 else "FAIL (< 0.50 threshold)"
        f.write(f"\\nQC gate : {gate_status}\\n")

    print(f"✓ QSAR CV R² = {results['cv_r2_score']:.3f}, RMSE = {results['cv_rmse']:.3f}", file=sys.stderr)
    """
}

workflow QSAR_RF_MODEL_WORKFLOW {
    take:
    ch_input  // channel: path(input_csv)

    main:
    QSAR_RF_MODEL(ch_input)

    emit:
    results  = QSAR_RF_MODEL.out.results
    report   = QSAR_RF_MODEL.out.report
    versions = QSAR_RF_MODEL.out.versions
}

workflow {
    if (!params.input_csv) {
        error "Please provide --input_csv <path>"
    }
    ch_csv = Channel.fromPath(params.input_csv)
    QSAR_RF_MODEL_WORKFLOW(ch_csv)
    QSAR_RF_MODEL_WORKFLOW.out.results.view { "Results: $it" }
}
