#!/bin/bash -ue
python3 "/home/yzhang/biomate/backend/biomni_workflows/pipeline_composition/modules/../manifests/write_manifest.py" \
    --pipeline_id   "cryosparc_standard_spa" \
    --invocation_id "test_001" \
    --outdir        "/tmp/spa_test/" \
    --ports_json    '{"particles_ctf_refined":"20_local_ctf_refinement/particles_ctf_refined.cs","volume_cs":"17_homogeneous_refinement/refined_volume.cs","nu_refined_volume":"21_non_uniform_refinement/volume_nu_refined.mrc","sharpened_map":"23_sharpening/volume_sharpened.mrc","fsc_report":"19_validation_fsc/validation_report.json","local_resolution_map":"22_local_resolution/local_resolution.mrc","micrographs_ctf":"03_ctf_estimation/micrographs_ctf.cs"}' \
    --params_json   '{"pixel_size":1.05,"voltage":300,"qc_profile":"cryoem_spa_standard"}' \
    --metrics_json  '{}' \
    --output        workflow_outputs.json
