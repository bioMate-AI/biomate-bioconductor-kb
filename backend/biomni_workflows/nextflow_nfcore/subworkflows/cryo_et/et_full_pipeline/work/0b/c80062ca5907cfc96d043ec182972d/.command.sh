#!/usr/bin/env python3
import json
import random
from datetime import datetime

random.seed(77)

mock_mode = True
reconstruction_method = 'wbp'
sirt_iterations = 10
thickness_nm = 200
binning = 4

alignment_data = json.load(open('tilt_alignment_report.json'))
ts_results = alignment_data.get('tiltseries_results', [])
num_ts = alignment_data.get('num_tiltseries_aligned', len(ts_results))

pixel_size_a = alignment_data.get('pixel_size_angstroms', 1.35)
voxel_size_a = round(pixel_size_a * binning, 4)

lateral_px = 4096 // binning
thickness_vox = int(round(thickness_nm * 10.0 / voxel_size_a))

tomograms = []
for ts in ts_results:
    ts_id = ts['ts_id']
    contrast_min = round(random.uniform(-0.08, -0.02), 4)
    contrast_max = round(random.uniform(0.08, 0.20), 4)
    if reconstruction_method == 'sirt':
        contrast_min = round(contrast_min * 0.6, 4)
        contrast_max = round(contrast_max * 0.6, 4)

    tomograms.append({
        "ts_id": ts_id,
        "dimensions_voxels": [lateral_px, lateral_px, thickness_vox],
        "voxel_size_angstroms": voxel_size_a,
        "binning_factor": binning,
        "contrast_min": contrast_min,
        "contrast_max": contrast_max,
        "output_mrc": f"tomogram_{ts_id}_bin{binning}.mrc",
        "reconstruction_method": reconstruction_method,
        "sirt_iterations": sirt_iterations if reconstruction_method == 'sirt' else None
    })

manifest = {
    "num_tomograms": num_ts,
    "reconstruction_method": reconstruction_method,
    "binning_factor": binning,
    "voxel_size_angstroms": voxel_size_a,
    "tomogram_thickness_nm": thickness_nm,
    "tomograms": tomograms
}

report = {
    "step": "03_tomogram_reconstruction",
    "timestamp": datetime.now().isoformat(),
    "reconstruction_method": reconstruction_method,
    "sirt_iterations": sirt_iterations if reconstruction_method == 'sirt' else None,
    "binning_factor": binning,
    "tomogram_thickness_nm": thickness_nm,
    "voxel_size_angstroms": voxel_size_a,
    "num_tomograms": num_ts,
    "tomograms": tomograms,
    "mock_mode": mock_mode
}

with open("tomogram_reconstruction_report.json", "w") as f:
    json.dump(report, f, indent=2)

with open("tomograms_manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)

print(f"Tomogram reconstruction complete ({reconstruction_method.upper()})")
print(f"  Tomograms: {num_ts}  |  Dimensions: {lateral_px}x{lateral_px}x{thickness_vox} voxels")
print(f"  Voxel size: {voxel_size_a} A  |  Binning: {binning}x")
