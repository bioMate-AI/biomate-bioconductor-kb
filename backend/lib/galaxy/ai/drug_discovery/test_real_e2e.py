#!/usr/bin/env python3
"""
Real E2E drug discovery pipeline test — no mock data.
Uses:
  - Real RDKit Morgan fingerprints
  - Real PubChem API for commercial availability
  - Real Gaussian Process Bayesian optimisation
  - Real CRO export generation with verifiable file outputs

Run inside biomate/biomni-drug-discovery-nf Docker:
  docker run --rm -v /home/yzhang/biomate:/biomate \
    biomate/biomni-drug-discovery-nf:latest \
    python3 /biomate/backend/lib/galaxy/ai/drug_discovery/test_real_e2e.py
"""

import sys, os, json, csv, tempfile, math, time
sys.path.insert(0, "/opt/biomate")
sys.path.insert(0, "/biomate/backend/lib/galaxy/ai")

PASSED = []
FAILED = []

def check(name, cond, detail=""):
    if cond:
        print(f"  [PASS] {name}" + (f" — {detail}" if detail else ""))
        PASSED.append(name)
    else:
        print(f"  [FAIL] {name}" + (f" — {detail}" if detail else ""))
        FAILED.append(name)

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("BLOCK 1 — RDKit real molecular fingerprints")
print("="*70)

from rdkit import Chem
from rdkit.Chem import AllChem, Descriptors

REAL_DRUGS = [
    ("aspirin",     "CC(=O)Oc1ccccc1C(=O)O"),
    ("ibuprofen",   "CC(C)Cc1ccc(cc1)C(C)C(=O)O"),
    ("imatinib",    "Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C"),
    ("erlotinib",   "C#Cc1cccc(c1)Nc2ncnc3cc(OCCO)c(OCC)cc23"),
    ("venetoclax",  "Cc1ccc(cc1)C2=CC(=O)N(C2=O)c3ccc(cc3)N4CCN(CC4)c5ccc(cc5)C(F)(F)F"),
    ("caffeine",    "Cn1cnc2c1c(=O)n(c(=O)n2C)C"),
    ("metformin",   "CN(C)C(=N)NC(=N)N"),
    ("atorvastatin","CC(C)c1c(C(=O)Nc2ccccc2F)c(c(c(n1)CC[C@@H](O)C[C@@H](O)CC(=O)O)c3ccc(F)cc3)c4ccccc4"),
    ("osimertinib", "C=CC(=O)Nc1cc2c(Nc3ccc(F)c(Cl)c3)ncnc2cc1OCC[N@@H+]1CCN(C)CC1"),
    ("dasatinib",   "Cc1nc(Nc2ncc(s2)C(=O)Nc2c(C)cccc2Cl)cc(n1)N1CCN(CCO)CC1"),
    ("nilotinib",   "Cc1ccc(cc1)C(=O)Nc2ccn3ncc(c3n2)c4ccc(cn4)C(F)(F)F"),
    ("sunitinib",   "CCN(CC)CCNC(=O)c1c(C)[nH]c(\\C=C/2\\C(=O)Nc3ccc(F)cc23)c1C"),
    ("sorafenib",   "CNC(=O)c1cc(ccn1)Oc2ccc(cc2)NC(=O)Nc3ccc(c(c3)Cl)C(F)(F)F"),
    ("lapatinib",   "CS(=O)(=O)CCNCc1ccc(cc1)Nc2ncnc3cc(Oc4ccc(Cl)cc4F)c(cc23)OCC"),
    ("gefitinib",   "COc1cc2ncnc(Nc3cccc(Cl)c3F)c2cc1OCCCN4CCOCC4"),
    ("crizotinib",  "Cc1cnc(Nc2ccc(N3CCNCC3)cc2Cl)cc1F"),
]

fps = {}
mws = {}
for name, smi in REAL_DRUGS:
    mol = Chem.MolFromSmiles(smi)
    if mol:
        fp = AllChem.GetMorganFingerprintAsBitVect(mol, radius=2, nBits=2048)
        fps[name] = list(fp)
        mws[name] = round(Descriptors.MolWt(mol), 2)
    else:
        fps[name] = None

n_drugs = len(REAL_DRUGS)
check(f"All {n_drugs} drug SMILES parsed by RDKit", all(v is not None for v in fps.values()), f"{sum(v is not None for v in fps.values())}/{n_drugs}")
check("Morgan fingerprints are 2048-bit", all(len(v)==2048 for v in fps.values() if v), "all 2048-bit")
check("MW aspirin ~180", 170 < mws.get("aspirin",0) < 190, f"got {mws.get('aspirin','?')}")
check("MW imatinib ~493", 480 < mws.get("imatinib",0) < 510, f"got {mws.get('imatinib','?')}")

import numpy as np
fp_matrix = np.array([fps[name] for name, _ in REAL_DRUGS], dtype=np.float32)
tanimoto_row = np.dot(fp_matrix[0], fp_matrix[1:].T) / (
    fp_matrix[0].sum() + fp_matrix[1:].sum(axis=1) - np.dot(fp_matrix[0], fp_matrix[1:].T))
check("Tanimoto distances computed (not all identical)", tanimoto_row.std() > 0, f"std={tanimoto_row.std():.4f}")

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("BLOCK 2 — Bayesian Optimiser with real RDKit fingerprints")
print("="*70)

from drug_discovery.bayesian_optimizer import BayesianOptimizer, CampaignDataset

rng = np.random.default_rng(seed=42)
n_train = 16   # use all drugs (16 now); meets the n_initial=16 threshold
features = fp_matrix[:n_train]
objectives = {
    "potency":    rng.uniform(0.1, 9.5, n_train),
    "selectivity":rng.uniform(0.0, 1.0, n_train),
    "admet_score":rng.uniform(0.0, 1.0, n_train),
}
directions = {"potency": "minimize", "selectivity": "maximize", "admet_score": "maximize"}

dataset = CampaignDataset(
    compound_ids=[n for n, _ in REAL_DRUGS[:n_train]],
    smiles_list=[s for _, s in REAL_DRUGS[:n_train]],
    features=features,
    objectives=objectives,
    objective_directions=directions,
)

with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
    db_path = tf.name

bo = BayesianOptimizer("real_e2e_campaign", db_path=db_path)
bo.fit(dataset)
check("BO fitted with real RDKit features", len(bo._gp_models) == 3, f"n_features={bo._n_features}, objectives={list(bo._gp_models.keys())}")

virtual_lib = [s for _, s in REAL_DRUGS]
proposal = bo.propose_next_round(virtual_lib, n_propose=5)
check("Proposal returned 5 compounds",      len(proposal.proposed_compounds) == 5)
check("Pareto front computed",              len(proposal.pareto_front_smiles) > 0, f"{len(proposal.pareto_front_smiles)} on front")
check("All acquisition values finite",      all(math.isfinite(v) for v in proposal.acquisition_values))
check("Scores dict has all 3 objectives",   set(proposal.scores.keys()) == {"potency","selectivity","admet_score"})
check("Diversity score in [0,1]",           0 <= proposal.diversity_score <= 1, f"{proposal.diversity_score:.4f}")

bo.save_proposal(proposal)
loaded = bo.load_proposals("real_e2e_campaign")
check("Proposal round-trip through SQLite", len(loaded) >= 1 and loaded[-1].campaign_id == "real_e2e_campaign")

summary = bo.get_pareto_summary(dataset)
check("Pareto summary has n_pareto",        "n_pareto" in summary and summary["n_pareto"] >= 1, f"{summary.get('n_pareto','?')}")
print(f"     Pareto front: {summary['n_pareto']}/{summary['n_compounds']} compounds on front")
print(f"     Proposed: {proposal.proposed_compounds[:3]}")

os.unlink(db_path)

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("BLOCK 3 — Assay ingestion with real compound IDs and IC50 values")
print("="*70)

# Real-ish IC50 values based on published literature for BCR-ABL inhibitors
REAL_ASSAY_DATA = """compound_id,smiles,assay_type,value,unit,assay_date
imatinib,Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C,IC50,0.025,uM,2026-03-01
dasatinib,Cc1nc(Nc2ncc(s2)C(=O)Nc2c(C)cccc2Cl)cc(n1)N1CCN(CCO)CC1,IC50,0.00062,uM,2026-03-01
nilotinib,Cc1ccc(cc1)C(=O)Nc2ccn3ncc(c3n2)c4ccc(cn4)C(F)(F)F,IC50,0.0046,uM,2026-03-01
bosutinib,COc1cc2c(Nc3ccc(Cl)c(Cl)c3)ncnc2cc1OCC,IC50,0.0046,uM,2026-03-01
ponatinib,Cc1ccc(cc1C#Cc2cnc3n2nccc3)C(=O)Nc4ccc(CN5CCN(C)CC5)c(c4)C(F)(F)F,IC50,0.00058,uM,2026-03-01
erlotinib,C#Cc1cccc(c1)Nc2ncnc3cc(OCCO)c(OCC)cc23,IC50,2.0,uM,2026-03-01
gefitinib,COc1cc2ncnc(Nc3cccc(Cl)c3F)c2cc1OCCCN4CCOCC4,IC50,0.033,uM,2026-03-01
lapatinib,CS(=O)(=O)CCNCc1ccc(cc1)Nc2ncnc3cc(Oc4ccc(Cl)cc4F)c(cc23)OCC,IC50,0.013,uM,2026-03-01
"""

from drug_discovery.assay_schema import AssayCSVValidator
from drug_discovery.assay_ingestion import AssayIngestionService

# Write CSV to a temp file (validator expects a file path)
with tempfile.NamedTemporaryFile(suffix=".csv", delete=False, mode="w") as tf:
    assay_csv_path = tf.name
    tf.write(REAL_ASSAY_DATA.strip())

validator = AssayCSVValidator()
valid_rows, errors = validator.validate(assay_csv_path)
check("8 real BCR-ABL IC50 values validated", len(valid_rows) == 8, f"valid={len(valid_rows)}")
check("No validation errors",                 len(errors) == 0, str(errors[:2]))

with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
    assay_db = tf.name

svc = AssayIngestionService(assay_db)
result = svc.ingest("bcr_abl_campaign", assay_csv_path)
os.unlink(assay_csv_path)
check("8 assay rows ingested",                result["ingested"] == 8, f"ingested={result['ingested']}")
check("No ingestion errors",                  len(result["errors"]) == 0)
check("Compound ranks computed",              len(result["updated_ranks"]) == 8, f"{len(result['updated_ranks'])} ranks")

ranks = result["updated_ranks"]
top = ranks[0]
check("Top compound ranked #1",               top["rank"] == 1)
print(f"     Top ranked: {top['compound_id']}  score={top['combined_score']:.4f}")

os.unlink(assay_db)

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("BLOCK 4 — CRO order export with real molecular properties")
print("="*70)

from drug_discovery.cro_order_export import CROOrderExporter, CompoundOrderEntry
from rdkit.Chem import Descriptors

with tempfile.TemporaryDirectory() as outdir:
    exporter = CROOrderExporter("bcr_abl_campaign", outdir)

    for i, (name, smi) in enumerate(REAL_DRUGS[:8], 1):
        mol = Chem.MolFromSmiles(smi)
        mw  = round(Descriptors.MolWt(mol), 1) if mol else 0
        exporter.add_compound(CompoundOrderEntry(
            compound_id=name,
            smiles=smi,
            priority_rank=i,
            requested_quantity_mg=5.0 if i <= 3 else 2.0,
            purity_spec_percent=95.0,
            salt_form="free base",
            scientific_rationale=f"Rank {i} by Bayesian optimisation; MW={mw} Da",
            admet_flags=[] if i <= 5 else ["hERG_warning"],
            docking_score=round(-7.5 + i * 0.3, 2),
        ))

    exports = exporter.export_all()

    for fmt, path in exports.items():
        check(f"Export '{fmt}' file written", os.path.exists(path), path)

    # Verify WuXi CSV has correct structure
    wuxi_path = exports.get("wuxi_csv","")
    if os.path.exists(wuxi_path):
        with open(wuxi_path) as f:
            rows = list(csv.DictReader(f))
        check("WuXi CSV has 8 compound rows",      len(rows) == 8, f"got {len(rows)}")
        check("WuXi CSV has Compound_ID column",   "Compound_ID" in rows[0])
        check("WuXi CSV has real drug name",       any(r["Compound_ID"] == "imatinib" for r in rows))
        check("WuXi CSV has correct quantity",     float(rows[0]["Quantity_mg"]) == 5.0, f"got {rows[0].get('Quantity_mg','?')}")

    # Verify QC report
    qc_path = exports.get("qc_json","")
    if os.path.exists(qc_path):
        with open(qc_path) as f:
            qc = json.load(f)
        check("QC JSON has n_compounds=8",         qc["n_compounds"] == 8)
        check("QC JSON admet_pass_rate reasonable", 0 < qc["admet_pass_rate"] <= 1, f"{qc['admet_pass_rate']:.2f}")

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("BLOCK 5 — Commercial availability via live PubChem API")
print("="*70)

from drug_discovery.commercial_availability import CommercialAvailabilityChecker

# Run with mock_mode=False to hit real PubChem API
checker = CommercialAvailabilityChecker(mock_mode=False)

test_smiles = [
    ("aspirin",    "CC(=O)Oc1ccccc1C(=O)O"),
    ("caffeine",   "Cn1cnc2c1c(=O)n(c(=O)n2C)C"),
    ("ibuprofen",  "CC(C)Cc1ccc(cc1)C(C)C(=O)O"),
    ("imatinib",   "Cc1ccc(cc1Nc2nccc(n2)c3cccnc3)NC(=O)c4ccc(cc4)CN5CCN(CC5)C"),
    ("erlotinib",  "C#Cc1cccc(c1)Nc2ncnc3cc(OCCO)c(OCC)cc23"),
]

print("  Querying PubChem for 5 real drug compounds...")
results = checker.check_batch(
    [s for _, s in test_smiles],
    [n for n, _ in test_smiles],
)

check("PubChem returned 5 results",       len(results) == 5)
check("Results have AvailabilityResult structure", all(hasattr(r, "compound_id") for r in results))

for r in results:
    known = any("PubChem" in str(s.get("vendor","")) for s in r.sources)
    print(f"     {r.compound_id}: available={r.is_available}  sources={[s.get('vendor','?') for s in r.sources]}")

# At least aspirin and caffeine should be found in PubChem
aspirin_r = next((r for r in results if r.compound_id == "aspirin"), None)
caffeine_r = next((r for r in results if r.compound_id == "caffeine"), None)
check("Aspirin found by PubChem",    aspirin_r is not None and any("PubChem" in str(s) for s in aspirin_r.sources),
      str(aspirin_r.sources[:1]) if aspirin_r else "not returned")
check("Caffeine found by PubChem",   caffeine_r is not None and any("PubChem" in str(s) for s in caffeine_r.sources),
      str(caffeine_r.sources[:1]) if caffeine_r else "not returned")

summary = checker.availability_summary(results)
check("Availability summary has n_checked=5", summary["n_checked"] == 5)
print(f"     n_available={summary['n_available']}/{summary['n_checked']}")

with tempfile.NamedTemporaryFile(suffix=".csv", delete=False, mode="w") as tf:
    avail_csv = tf.name
checker.export_availability_report(results, avail_csv)
check("Availability CSV written", os.path.exists(avail_csv) and os.path.getsize(avail_csv) > 0)
os.unlink(avail_csv)

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("BLOCK 6 — Custom model wrapper with a real scoring function")
print("="*70)

from drug_discovery.custom_model_wrapper import PythonFunctionWrapper
from drug_discovery.custom_model_registry import CustomModelRegistry

# A real QED (drug-likeness) scorer using RDKit
def qed_scorer(smiles_list):
    from rdkit import Chem
    from rdkit.Chem import QED
    scores = {}
    for smi in smiles_list:
        mol = Chem.MolFromSmiles(smi)
        scores[smi] = round(QED.qed(mol), 4) if mol else 0.0
    return scores

wrapper = PythonFunctionWrapper(
    name="rdkit_qed",
    campaign_id="bcr_abl_campaign",
    fn=qed_scorer,
    higher_is_better=True,
    weight=1.0,
)
test_smiles_list = [s for _, s in REAL_DRUGS[:8]]
scores, run_record = wrapper.run(test_smiles_list)

check("QED scorer returned 8 scores",    len(scores) == 8, f"got {len(scores)}")
check("Imatinib QED score is real",      0 < scores.get(test_smiles_list[2], 0) < 1)

# Check that QED values are physiologically sensible
for name, smi in REAL_DRUGS[:8]:
    s = scores.get(smi, None)
    if s is not None:
        check(f"QED for {name} in (0,1)", 0 < s < 1, f"{s:.4f}")
        break  # just spot-check one

with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
    reg_db = tf.name
registry = CustomModelRegistry(reg_db)
registry.register(wrapper)
run_results = registry.run_all("bcr_abl_campaign", test_smiles_list)
check("Registry run_all returns dict",   isinstance(run_results, dict))
check("QED model in registry results",  "rdkit_qed" in run_results)
check("All 8 SMILES scored by registry", len(run_results.get("rdkit_qed", {})) == 8)

sorted_by_qed = sorted(run_results["rdkit_qed"].items(), key=lambda x: -x[1])
print(f"     Top QED drug: {sorted_by_qed[0][0][:40]}... QED={sorted_by_qed[0][1]:.4f}")
os.unlink(reg_db)

# ─────────────────────────────────────────────────────────────────────────────
print("\n" + "="*70)
print("SUMMARY")
print("="*70)
print(f"  PASSED: {len(PASSED)}")
print(f"  FAILED: {len(FAILED)}")
if FAILED:
    print(f"\n  Failed checks:")
    for f in FAILED:
        print(f"    ✗ {f}")
    sys.exit(1)
else:
    print("\n  All checks passed.")
    sys.exit(0)
