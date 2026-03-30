#!/usr/bin/env python3
import json
import random
from datetime import datetime

random.seed(123)

mock_mode = True
alignment_method = 'aretomo2'
tilt_axis_angle = 0.0
patch_alignment = True

manifest = json.load(open('tiltseries_manifest.json'))
num_tiltseries = manifest['num_tiltseries']
num_tilts = manifest['num_tilts_per_series']
tiltseries = manifest.get('tiltseries', [])

ts_results = []
xf_data = {}

for ts in tiltseries:
    ts_id = ts['ts_id']

    residual_scale = 0.8 if patch_alignment else 1.3
    per_tilt_residuals = [
        round(random.uniform(0.5, 3.5) * residual_scale, 3)
        for _ in range(num_tilts)
    ]
    mean_residual = round(sum(per_tilt_residuals) / len(per_tilt_residuals), 3)
    max_residual = round(max(per_tilt_residuals), 3)

    exclude_threshold = mean_residual * 3.0
    excluded_tilts = [
        i for i, r in enumerate(per_tilt_residuals) if r > exclude_threshold
    ]
    alignment_quality = "good" if mean_residual <= 3.0 else "poor"

    detected_axis_angle = (
        tilt_axis_angle if tilt_axis_angle != 0.0
        else round(random.uniform(-5.0, 5.0), 2)
    )

    ts_results.append({
        "ts_id": ts_id,
        "mean_residual_angstroms": mean_residual,
        "max_residual_angstroms": max_residual,
        "per_tilt_residuals_angstroms": per_tilt_residuals,
        "alignment_quality": alignment_quality,
        "num_excluded_tilts": len(excluded_tilts),
        "excluded_tilt_indices": excluded_tilts,
        "detected_tilt_axis_angle_deg": detected_axis_angle
    })

    xf_data[ts_id] = {
        "tilt_axis_angle_deg": detected_axis_angle,
        "num_transforms": num_tilts - len(excluded_tilts),
        "xf_file_path": f"alignments/{ts_id}.xf"
    }

all_residuals = [ts["mean_residual_angstroms"] for ts in ts_results]
overall_mean = round(sum(all_residuals) / len(all_residuals), 3)
num_poor = sum(1 for ts in ts_results if ts["alignment_quality"] == "poor")

# Propagate acquisition params so tomogram_reconstruction can use the correct
# pixel_size rather than falling back to a hardcoded default.
pixel_size_a = manifest.get('tiltseries', [{}])[0].get('pixel_size_angstroms', 1.35)
voltage_kv   = manifest.get('tiltseries', [{}])[0].get('voltage_kv', 300)

report = {
    "step": "02_tilt_alignment",
    "timestamp": datetime.now().isoformat(),
    "alignment_method": alignment_method,
    "patch_alignment": patch_alignment,
    "tilt_axis_angle_input_deg": tilt_axis_angle,
    "num_tiltseries_aligned": num_tiltseries,
    "num_tiltseries_poor_alignment": num_poor,
    "overall_mean_residual_angstroms": overall_mean,
    "tiltseries_results": ts_results,
    "pixel_size_angstroms": pixel_size_a,
    "voltage_kv": voltage_kv,
    "mock_mode": mock_mode
}

xf_output = {
    "alignment_method": alignment_method,
    "xf_files": xf_data
}

with open("tilt_alignment_report.json", "w") as f:
    json.dump(report, f, indent=2)

with open("alignment_xf_files.json", "w") as f:
    json.dump(xf_output, f, indent=2)

print(f"Tilt alignment complete ({alignment_method})")
print(f"  Overall mean residual: {overall_mean:.2f} A")
if num_poor > 0:
    print(f"  WARNING: {num_poor} tilt series with poor alignment (mean residual > 3.0 A)")
