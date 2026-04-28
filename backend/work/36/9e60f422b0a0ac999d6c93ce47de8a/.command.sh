#!/bin/bash -ue
python3 - <<'PYEOF'
import json
from datetime import datetime, timezone

ports   = json.loads('''{"particles_ctf_refined":"20_local_ctf_refinement/particles_ctf_refined.cs","volume_cs":"17_homogeneous_refinement/refined_volume.cs","nu_refined_volume":"21_non_uniform_refinement/volume_nu_refined.mrc","sharpened_map":"23_sharpening/volume_sharpened.mrc","fsc_report":"19_validation_fsc/validation_report.json","local_resolution_map":"22_local_resolution/local_resolution.mrc","micrographs_ctf":"03_ctf_estimation/micrographs_ctf.cs"}''')
params  = json.loads('''{"pixel_size":1.05,"voltage":300,"qc_profile":"cryoem_spa_standard"}''')
metrics = json.loads('''{}''')

manifest = {
    "schema_version": "1.0",
    "pipeline_id":    "cryosparc_standard_spa",
    "invocation_id":  "test_trigger",
    "completed_at":   datetime.now(timezone.utc).isoformat(),
    "outdir":         "/tmp/spa_test3/",
    "ports":          ports,
}
if params:
    manifest["params"] = params
if metrics:
    manifest["metrics"] = metrics

with open("workflow_outputs.json", "w") as f:
    json.dump(manifest, f, indent=2)

print(f"Manifest written: {manifest['pipeline_id']} / {manifest['invocation_id']}")
PYEOF
