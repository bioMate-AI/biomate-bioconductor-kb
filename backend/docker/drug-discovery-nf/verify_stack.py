"""Verify all drug discovery tools are installed correctly in the Docker image."""
import sys
sys.path.insert(0, "/opt/biomate")

results = {}

for pkg, check in [
    ("rdkit",          "import rdkit; results['rdkit'] = rdkit.__version__"),
    ("aizynthfinder",  "from importlib.metadata import version; results['aizynthfinder'] = version('aizynthfinder')"),
    ("gseapy",         "import gseapy; results['gseapy'] = gseapy.__version__"),
    ("pydeseq2",       "from pydeseq2.dds import DeseqDataSet; results['pydeseq2'] = 'OK'"),
    ("pubchempy",      "import pubchempy; results['pubchempy'] = 'OK'"),
    ("scipy",          "import scipy; results['scipy'] = scipy.__version__"),
    ("sklearn",        "import sklearn; results['sklearn'] = sklearn.__version__"),
    ("numpy",          "import numpy; results['numpy'] = numpy.__version__"),
    ("vina",           "from vina import Vina; results['vina'] = 'OK'"),
    ("ViennaRNA",      "import RNA; results['ViennaRNA'] = 'OK'"),
    ("meeko",          "import meeko; results['meeko'] = 'OK'"),
]:
    try:
        exec(check)
    except Exception as e:
        results[pkg] = f"FAIL: {e}"

for pkg, check in [
    ("BayesianOptimizer",            "from drug_discovery.bayesian_optimizer import BayesianOptimizer; results['BayesianOptimizer'] = 'OK'"),
    ("CROOrderExporter",             "from drug_discovery.cro_order_export import CROOrderExporter; results['CROOrderExporter'] = 'OK'"),
    ("CommercialAvailabilityChecker","from drug_discovery.commercial_availability import CommercialAvailabilityChecker; results['CommercialAvailabilityChecker'] = 'OK'"),
    ("AssayIngestionService",        "from drug_discovery.assay_ingestion import AssayIngestionService; results['AssayIngestionService'] = 'OK'"),
    ("CustomModelRegistry",          "from drug_discovery.custom_model_registry import CustomModelRegistry; results['CustomModelRegistry'] = 'OK'"),
]:
    try:
        exec(check)
    except Exception as e:
        results[pkg] = f"FAIL: {e}"

failures = [k for k, v in results.items() if str(v).startswith("FAIL")]
for k, v in results.items():
    status = "OK" if not str(v).startswith("FAIL") else "FAIL"
    print(f"  [{status}] {k}: {v}")

if failures:
    print(f"\nFailed: {failures}")
    sys.exit(1)
else:
    print(f"\nAll {len(results)} checks passed.")
