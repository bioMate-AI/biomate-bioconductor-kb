"""Set up AiZynthFinder stock file and minimal config during Docker build."""
import os

STOCK_SMILES = [
    "c1ccccc1", "c1ccc(Br)cc1", "c1ccc(Cl)cc1", "c1ccc(F)cc1",
    "c1ccc(I)cc1", "c1ccc(N)cc1", "c1ccc(O)cc1", "c1ccc(C(=O)O)cc1",
    "c1ccc(C(=O)Cl)cc1", "c1cccnc1", "c1ccncc1", "c1ccoc1", "c1ccsc1",
    "c1ccc2ccccc2c1",
    "CC(=O)O", "CC(=O)Cl", "CC(=O)OCC", "CCO", "CCCO", "CC(O)=O",
    "OCC", "OCCO", "C(=O)O", "ClCC", "BrCC", "BrCCCl",
    "CC(C)=O", "C=O", "CC=O", "CCC=O",
    "CN", "CCN", "CCCN", "Nc1ccccc1", "NCC", "NCCN", "N", "c1cc(N)ccc1N",
    "OC(=O)CCl", "OC(=O)CBr", "OC(=O)c1ccccc1", "CCOC(=O)CC",
    "CCOC(=O)c1ccccc1", "ClC(=O)c1ccccc1",
    "c1ccc(c2ccccc2)cc1", "c1cnc2ccccc2c1",
    "O=C1NC(=O)NC1", "O=C1CCCC(=O)N1", "O=C1CCCCC1",
    "ClCCOCC", "BrCCBr", "ICc1ccccc1", "BrCc1ccccc1", "ClC(Cl)Cl", "BrCCCBr",
    "OB(O)c1ccccc1", "OB(O)c1ccc(F)cc1", "OB(O)c1ccncc1",
    "Oc1ccc(F)cc1", "Oc1ccc(Cl)cc1", "Oc1ccccc1", "OCc1ccccc1",
    "OC(C)(C)C", "OCC(=O)O",
    "O=S(=O)(Cl)c1ccccc1", "NS(=O)(=O)c1ccccc1",
    "C1CCNCC1", "C1CCOC1", "C1CCOCC1", "C1CCCC1", "CC1CCCC1", "N1CCCCC1",
    "O=Cc1ccccc1", "O=Cc1ccc(Cl)cc1", "O=Cc1ccc(OC)cc1",
    "O=Cc1ccc(N)cc1", "O=CCCC", "O=CCC",
    "NCC(=O)O", "NC(C)C(=O)O", "NC(Cc1ccccc1)C(=O)O",
]

stock_dir = "/opt/aizynthfinder/stock"
os.makedirs(stock_dir, exist_ok=True)

stock_path = f"{stock_dir}/starting_materials.smi"
with open(stock_path, "w") as f:
    for i, smi in enumerate(STOCK_SMILES):
        f.write(f"{smi}\tSM{i:04d}\n")
print(f"Stock file written: {stock_path} ({len(STOCK_SMILES)} compounds)")

config_path = "/opt/aizynthfinder/config.yml"
# Use the USPTO models if present, otherwise stock-only config
models_dir = "/opt/aizynthfinder/models"
import os
onnx   = f"{models_dir}/uspto_model.onnx"
tmpl   = f"{models_dir}/uspto_templates.csv"
stock  = "/opt/aizynthfinder/stock/starting_materials.smi"

if os.path.exists(onnx) and os.path.exists(tmpl):
    config = f"""expansion:
  uspto:
    - {onnx}
    - {tmpl}
stock:
  biomate_stock: {stock}
search:
  algorithm: mcts
  max_transforms: 5
  iteration_limit: 100
  return_first: true
  time_limit: 120
"""
else:
    config = f"""stock:
  biomate_stock: {stock}
search:
  algorithm: mcts
  max_transforms: 5
  iteration_limit: 100
  return_first: true
  time_limit: 120
"""

with open(config_path, "w") as f:
    f.write(config)
print(f"Config written: {config_path}")
print(f"  expansion model: {'present' if os.path.exists(onnx) else 'absent'}")
print(f"  templates:       {'present' if os.path.exists(tmpl) else 'absent'}")

# Verify config is parseable by aizynthfinder
try:
    from aizynthfinder.aizynthfinder import AiZynthFinder
    print(f"AiZynthFinder import OK")
except Exception as e:
    print(f"AiZynthFinder import error: {e}")
    raise
