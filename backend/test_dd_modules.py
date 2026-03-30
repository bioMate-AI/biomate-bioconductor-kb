import sys, os, tempfile, csv
sys.path.insert(0, '/home/yzhang/biomate/backend')

# Test 1: AssayCSVValidator
from lib.galaxy.ai.drug_discovery.assay_schema import AssayCSVValidator

with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
    writer = csv.writer(f)
    writer.writerow(['compound_id','smiles','assay_type','value','unit','assay_date'])
    writer.writerow(['CMPD-001','CC(=O)Oc1ccccc1C(=O)O','IC50','0.45','uM','2026-03-10'])
    writer.writerow(['CMPD-002','','hERG','12.3','nM','2026-03-10'])
    csv_path = f.name

validator = AssayCSVValidator()
rows, errors = validator.validate(csv_path)
print(f"Validation: {len(rows)} valid rows, {len(errors)} errors")
assert len(rows) == 2, f"Expected 2 rows, got {len(rows)}"
# nM should be converted to uM
assert abs(rows[1]['value_uM'] - 0.0123) < 0.001, f"Unit conversion failed: {rows[1]['value_uM']}"
print("  AssayCSVValidator: PASS")

# Test 2: AssayIngestionService
from lib.galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
with tempfile.TemporaryDirectory() as tmpdir:
    db = os.path.join(tmpdir, 'test.db')
    svc = AssayIngestionService(db)
    result = svc.ingest('camp-001', csv_path)
    print(f"Ingestion result: {result}")
    assert result['ingested'] == 2
    ranked = svc.get_ranked_compounds('camp-001')
    print(f"Ranked compounds: {ranked}")
print("  AssayIngestionService: PASS")

# Test 3: PythonFunctionWrapper
from lib.galaxy.ai.drug_discovery.custom_model_wrapper import PythonFunctionWrapper

def mock_model(smiles_list):
    return {s: float(len(s)) / 100 for s in smiles_list}  # fake score

wrapper = PythonFunctionWrapper('test_model', 'camp-001', mock_model)
smiles = ['CC', 'CCCC', 'c1ccccc1']
scores, record = wrapper.run(smiles)
print(f"Wrapper scores: {scores}")
assert len(scores) == 3
assert record.success
print("  PythonFunctionWrapper: PASS")

# Test 4: CustomModelRegistry
from lib.galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry
with tempfile.TemporaryDirectory() as tmpdir:
    db = os.path.join(tmpdir, 'reg.db')
    reg = CustomModelRegistry(db)
    reg.register(wrapper)
    models = reg.list_models('camp-001')
    print(f"Registered models: {models}")
    assert len(models) == 1
    results = reg.run_all('camp-001', smiles)
    print(f"Registry run_all: {results}")
    assert 'test_model' in results
print("  CustomModelRegistry: PASS")

print("\nAll tests PASSED")
os.unlink(csv_path)
