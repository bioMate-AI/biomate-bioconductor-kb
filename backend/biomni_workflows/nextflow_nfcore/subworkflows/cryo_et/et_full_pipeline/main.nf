#!/usr/bin/env nextflow
/*
 * Cryo-ET Full Pipeline
 *
 * End-to-end cryo electron tomography workflow:
 *   1. Import Tilt Series
 *   2. Tilt Alignment (AreTomo2 / IMOD)
 *   3. Tomogram Reconstruction (WBP / SIRT)
 *   4. Subtomogram Averaging (STA)
 *   5. Pipeline Summary
 *
 * All tilt series are processed in parallel across steps 2-3.
 * Mock mode enabled by default for testing without GPU hardware.
 *
 * References:
 *   AreTomo2: Zheng et al. 2022 Nat Methods 19:1308
 *   IMOD: Mastronarde & Held 2017 J Struct Biol 197:102
 *   STA: Bharat & Scheres 2016 Nat Protoc 11:2054
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters — merged from all four sub-modules
// ============================================================================

// --- Import Tilt Series ---
params.tiltseries_path = null       // Directory of tilt series MRC/MRCS files
params.mdoc_path = null             // Directory of MDOC metadata files (optional)
params.pixel_size = 1.35            // Å/pixel
params.voltage = 300                // kV
params.spherical_aberration = 2.7   // mm
params.total_dose = 120.0           // e⁻/Å² total
params.tilt_range_min = -60.0       // degrees
params.tilt_range_max = 60.0        // degrees
params.tilt_increment = 3.0         // degrees between tilts

// --- Tilt Alignment ---
params.alignment_method = 'aretomo2' // 'aretomo2' (default) or 'imod'
params.tilt_axis_angle = 0.0         // degrees; 0 = auto-detect
params.patch_alignment = true        // use patch-based local alignment

// --- Tomogram Reconstruction ---
params.reconstruction_method = 'wbp' // 'wbp' (default) or 'sirt'
params.sirt_iterations = 10          // only used when method = sirt
params.tomogram_thickness_nm = 200   // nm
params.binning_factor = 4            // reconstruct at N× binned

// --- Subtomogram Averaging ---
params.num_particles = 1000          // target particle picks
params.template_pdb = null           // PDB template for template matching (optional)
params.symmetry = 'C1'               // point group symmetry
params.sta_resolution_target = 15.0  // Å target FSC resolution
params.num_sta_rounds = 2            // number of iterative STA rounds

// --- Global ---
params.mock_mode = true
params.outdir = './results/cryo_et'

// ============================================================================
// Process Definitions (inline — all four modules)
// ============================================================================

process IMPORT_TILTSERIES {
    tag "import_tiltseries"
    publishDir "${params.outdir}/01_import_tiltseries", mode: 'copy'

    input:
    path tiltseries_dir

    output:
    path "tiltseries_manifest.json", emit: manifest
    path "tiltseries_import_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime
    from pathlib import Path

    random.seed(42)

    mock_mode = ${mock}
    pixel_size = ${params.pixel_size}
    voltage = ${params.voltage}
    spherical_aberration = ${params.spherical_aberration}
    total_dose = ${params.total_dose}
    tilt_min = ${params.tilt_range_min}
    tilt_max = ${params.tilt_range_max}
    tilt_inc = ${params.tilt_increment}

    tilt_angles = []
    t = tilt_min
    while t <= tilt_max + 0.001:
        tilt_angles.append(round(t, 1))
        t += tilt_inc
    num_tilts = len(tilt_angles)
    dose_per_tilt = round(total_dose / num_tilts, 4)

    num_tiltseries = 3
    tiltseries = []

    for ts_idx in range(num_tiltseries):
        ts_id = f"TS_{ts_idx + 1:03d}"
        tilt_entries = []
        accumulated_dose = 0.0
        for i, angle in enumerate(tilt_angles):
            accumulated_dose += dose_per_tilt
            tilt_entries.append({
                "tilt_angle_deg": angle,
                "accumulated_dose_per_tilt": round(dose_per_tilt, 4),
                "cumulative_dose_e_per_a2": round(accumulated_dose, 4),
                "defocus_um": round(random.uniform(-4.0, -1.5), 3),
                "filename": f"tiltseries_{ts_id}_tilt{i + 1:03d}.mrc"
            })

        tiltseries.append({
            "ts_id": ts_id,
            "num_tilts": num_tilts,
            "tilt_angles": tilt_angles,
            "tilt_entries": tilt_entries,
            "mdoc_available": False,
            "pixel_size_angstroms": pixel_size,
            "voltage_kv": voltage,
            "spherical_aberration_mm": spherical_aberration,
            "total_dose_e_per_a2": total_dose
        })

    manifest = {
        "num_tiltseries": num_tiltseries,
        "num_tilts_per_series": num_tilts,
        "tilt_range_min_deg": tilt_min,
        "tilt_range_max_deg": tilt_max,
        "tilt_increment_deg": tilt_inc,
        "pixel_size_angstroms": pixel_size,
        "voltage_kv": voltage,
        "tiltseries": tiltseries
    }

    report = {
        "step": "01_import_tiltseries",
        "timestamp": datetime.now().isoformat(),
        "num_tiltseries": num_tiltseries,
        "num_tilts_per_series": num_tilts,
        "pixel_size_angstroms": pixel_size,
        "voltage_kv": voltage,
        "total_dose_e_per_a2": total_dose,
        "tilt_range_deg": [tilt_min, tilt_max],
        "tilt_increment_deg": tilt_inc,
        "mdoc_metadata_available": False,
        "mock_mode": mock_mode
    }

    with open("tiltseries_manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)

    with open("tiltseries_import_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print(f"Imported {num_tiltseries} tilt series")
    print(f"  Tilts per series: {num_tilts} ({tilt_min} to {tilt_max} deg)")
    print(f"  Pixel size: {pixel_size} A/px  |  Voltage: {voltage} kV")
    """

    stub:
    """
    touch tiltseries_manifest.json
    touch tiltseries_import_report.json
    """
}

// ----------------------------------------------------------------------------

process TILT_ALIGNMENT {
    tag "tilt_alignment"
    label 'process_gpu'
    publishDir "${params.outdir}/02_tilt_alignment", mode: 'copy'

    input:
    path tiltseries_manifest

    output:
    path "tilt_alignment_report.json", emit: report
    path "alignment_xf_files.json",    emit: xf_files

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def patch_align = params.patch_alignment ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(123)

    mock_mode = ${mock}
    alignment_method = '${params.alignment_method}'
    tilt_axis_angle = ${params.tilt_axis_angle}
    patch_alignment = ${patch_align}

    manifest = json.load(open('${tiltseries_manifest}'))
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
    """

    stub:
    """
    touch tilt_alignment_report.json
    touch alignment_xf_files.json
    """
}

// ----------------------------------------------------------------------------

process TOMOGRAM_RECONSTRUCTION {
    tag "tomogram_reconstruction"
    publishDir "${params.outdir}/03_tomogram_reconstruction", mode: 'copy'

    input:
    path alignment_report

    output:
    path "tomogram_reconstruction_report.json", emit: report
    path "tomograms_manifest.json",             emit: manifest

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(77)

    mock_mode = ${mock}
    reconstruction_method = '${params.reconstruction_method}'
    sirt_iterations = ${params.sirt_iterations}
    thickness_nm = ${params.tomogram_thickness_nm}
    binning = ${params.binning_factor}

    alignment_data = json.load(open('${alignment_report}'))
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
    """

    stub:
    """
    touch tomogram_reconstruction_report.json
    touch tomograms_manifest.json
    """
}

// ----------------------------------------------------------------------------

process SUBTOMOGRAM_AVERAGING {
    tag "subtomogram_averaging"
    label 'process_gpu'
    publishDir "${params.outdir}/04_subtomogram_averaging", mode: 'copy'

    input:
    path tomograms_manifest

    output:
    path "sta_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def has_template = params.template_pdb ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(256)

    mock_mode = ${mock}
    target_particles = ${params.num_particles}
    symmetry = '${params.symmetry}'
    sta_resolution_target = ${params.sta_resolution_target}
    num_sta_rounds = ${params.num_sta_rounds}
    has_template = ${has_template}

    manifest = json.load(open('${tomograms_manifest}'))
    tomograms = manifest.get('tomograms', [])
    num_tomograms = manifest.get('num_tomograms', len(tomograms))

    raw_weights = [random.uniform(0.5, 1.5) for _ in range(num_tomograms)]
    total_weight = sum(raw_weights)
    particles_per_tomo = {}
    total_picked = 0

    for i, tomo in enumerate(tomograms):
        ts_id = tomo['ts_id']
        if i < num_tomograms - 1:
            n = int(round(target_particles * raw_weights[i] / total_weight))
        else:
            n = target_particles - total_picked
        n = max(1, n)
        particles_per_tomo[ts_id] = n
        total_picked += n

    picking_snr = round(random.uniform(1.8, 3.5) * (1.3 if has_template else 1.0), 3)

    sta_rounds = []
    current_res = round(sta_resolution_target * random.uniform(1.4, 1.8), 2)

    for rnd in range(1, num_sta_rounds + 1):
        if rnd > 1:
            improvement = random.uniform(0.60, 0.80)
            current_res = round(current_res * improvement, 2)
        current_res = max(10.0, min(50.0, current_res))
        sta_rounds.append({
            "round": rnd,
            "fsc_0143_resolution_angstroms": current_res,
            "particles_included": int(total_picked * random.uniform(0.85, 1.0))
        })

    final_fsc = sta_rounds[-1]["fsc_0143_resolution_angstroms"]

    report = {
        "step": "04_subtomogram_averaging",
        "timestamp": datetime.now().isoformat(),
        "num_tomograms": num_tomograms,
        "total_particles_picked": total_picked,
        "particles_per_tomogram": particles_per_tomo,
        "picking_snr": picking_snr,
        "template_matching": has_template,
        "symmetry": symmetry,
        "num_sta_rounds": num_sta_rounds,
        "sta_rounds": sta_rounds,
        "final_fsc_0143_resolution_angstroms": final_fsc,
        "sta_resolution_target_angstroms": sta_resolution_target,
        "mock_mode": mock_mode
    }

    with open("sta_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print(f"Subtomogram averaging complete ({num_sta_rounds} round(s))")
    print(f"  Tomograms: {num_tomograms}  |  Total particles: {total_picked}")
    print(f"  Symmetry: {symmetry}  |  Template matching: {has_template}")
    for r in sta_rounds:
        print(f"  Round {r['round']}: FSC 0.143 = {r['fsc_0143_resolution_angstroms']:.1f} A")
    print(f"  Final FSC 0.143 resolution: {final_fsc:.1f} A")
    """

    stub:
    """
    touch sta_report.json
    """
}

// ----------------------------------------------------------------------------

process ET_PIPELINE_SUMMARY {
    tag "et_summary"
    publishDir "${params.outdir}/05_pipeline_summary", mode: 'copy'

    input:
    path reports

    output:
    path "et_pipeline_summary.json", emit: summary

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import glob
    from datetime import datetime
    from pathlib import Path

    mock_mode = ${mock}

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
    """

    stub:
    """
    touch et_pipeline_summary.json
    """
}

// ============================================================================
// Main Workflow
// ============================================================================

workflow CRYO_ET_FULL_PIPELINE {
    take:
    tiltseries_dir

    main:
    // Step 1: Import tilt series
    IMPORT_TILTSERIES(tiltseries_dir)

    // Step 2: Tilt alignment (runs on the manifest describing all tilt series;
    //         AreTomo2 internally processes them in parallel)
    TILT_ALIGNMENT(IMPORT_TILTSERIES.out.manifest)

    // Step 3: Tomogram reconstruction (parallel per tilt series internally)
    TOMOGRAM_RECONSTRUCTION(TILT_ALIGNMENT.out.report)

    // Step 4: Subtomogram averaging
    SUBTOMOGRAM_AVERAGING(TOMOGRAM_RECONSTRUCTION.out.manifest)

    // Collect all step reports for the summary process
    all_reports = IMPORT_TILTSERIES.out.report
        .mix(TILT_ALIGNMENT.out.report)
        .mix(TOMOGRAM_RECONSTRUCTION.out.report)
        .mix(SUBTOMOGRAM_AVERAGING.out.report)
        .collect()

    // Step 5: Generate pipeline summary
    ET_PIPELINE_SUMMARY(all_reports)

    emit:
    summary    = ET_PIPELINE_SUMMARY.out.summary
    sta_report = SUBTOMOGRAM_AVERAGING.out.report
    tomo_manifest = TOMOGRAM_RECONSTRUCTION.out.manifest
}

// ============================================================================
// Standalone Execution
// ============================================================================

workflow {
    def input_dir = params.tiltseries_path ?: '.'
    tiltseries_ch = Channel.fromPath(input_dir, type: 'dir', checkIfExists: false)
        .ifEmpty { file('.') }

    CRYO_ET_FULL_PIPELINE(tiltseries_ch)
}
