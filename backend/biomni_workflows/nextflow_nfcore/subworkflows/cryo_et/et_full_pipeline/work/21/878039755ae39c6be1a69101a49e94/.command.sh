#!/usr/bin/env python3
import json
import glob
from datetime import datetime
from pathlib import Path

mock_mode = True

# Collect all JSON report files staged into this task directory
report_files = sorted(glob.glob("*.json"))
steps_data = {}

for rf in report_files:
    try:
        data = json.load(open(rf))
        step_key = data.get("step", rf.replace(".json", ""))
        steps_data[step_key] = data
    except Exception:
        pass

# Extract key summary metrics from each step
import_report = steps_data.get("01_import_tiltseries", {})
alignment_report = steps_data.get("02_tilt_alignment", {})
recon_report = steps_data.get("03_tomogram_reconstruction", {})
sta_report = steps_data.get("04_subtomogram_averaging", {})

summary = {
    "workflow": "cryo_et_full_pipeline",
    "version": "1.0",
    "completion_time": datetime.now().isoformat(),
    "mock_mode": mock_mode,
    "steps_completed": len(steps_data),
    "steps": list(steps_data.keys()),
    "acquisition": {
        "num_tiltseries": import_report.get("num_tiltseries"),
        "num_tilts_per_series": import_report.get("num_tilts_per_series"),
        "pixel_size_angstroms": import_report.get("pixel_size_angstroms"),
        "voltage_kv": import_report.get("voltage_kv"),
        "total_dose_e_per_a2": import_report.get("total_dose_e_per_a2")
    },
    "alignment": {
        "method": alignment_report.get("alignment_method"),
        "overall_mean_residual_angstroms": alignment_report.get("overall_mean_residual_angstroms"),
        "num_poor_alignments": alignment_report.get("num_tiltseries_poor_alignment", 0)
    },
    "reconstruction": {
        "method": recon_report.get("reconstruction_method"),
        "binning_factor": recon_report.get("binning_factor"),
        "voxel_size_angstroms": recon_report.get("voxel_size_angstroms"),
        "num_tomograms": recon_report.get("num_tomograms")
    },
    "sta": {
        "total_particles": sta_report.get("total_particles_picked"),
        "symmetry": sta_report.get("symmetry"),
        "num_rounds": sta_report.get("num_sta_rounds"),
        "final_fsc_0143_resolution_angstroms": sta_report.get("final_fsc_0143_resolution_angstroms")
    },
    "outputs": {
        "tomograms": "03_tomogram_reconstruction/tomograms_manifest.json",
        "sta_map": "04_subtomogram_averaging/sta_report.json"
    }
}

with open("et_pipeline_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

fsc_res = sta_report.get("final_fsc_0143_resolution_angstroms", "N/A")
mean_res = alignment_report.get("overall_mean_residual_angstroms", "N/A")
print("")
print("=" * 70)
print("  Cryo-ET Full Pipeline Complete!")
print("=" * 70)
print(f"  Tilt series imported:         {import_report.get('num_tiltseries', 'N/A')}")
print(f"  Alignment mean residual:       {mean_res} A")
print(f"  Tomograms reconstructed:       {recon_report.get('num_tomograms', 'N/A')}")
print(f"  Particles picked:             {sta_report.get('total_particles_picked', 'N/A')}")
print(f"  STA FSC 0.143 resolution:      {fsc_res} A")
print("=" * 70)
