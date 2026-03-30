#!/usr/bin/env nextflow
/*
 * Cryo-ET: Tomogram Reconstruction
 *
 * Reconstructs tomograms from aligned tilt series using weighted back-projection
 * (WBP, default) or SIRT. All tilt series are processed in parallel.
 *
 * Step 3 of the Cryo-ET pipeline.
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.reconstruction_method = 'wbp'  // 'wbp' (default) or 'sirt'
params.sirt_iterations = 10           // only used when method = sirt
params.tomogram_thickness_nm = 200    // nm
params.binning_factor = 4             // reconstruct at N× binned resolution
params.mock_mode = true
params.outdir = './results/cryo_et'

// ============================================================================
// Process Definition
// ============================================================================

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

    # Load pixel size from alignment report if available (fallback to 1.35 A)
    pixel_size_a = alignment_data.get('pixel_size_angstroms', 1.35)
    voxel_size_a = round(pixel_size_a * binning, 4)

    # Tomogram lateral dimensions: typical 4kx4k camera, binned
    lateral_px = 4096 // binning

    # Thickness in voxels: thickness_nm * 10 A/nm / voxel_size_a
    thickness_vox = int(round(thickness_nm * 10.0 / voxel_size_a))

    tomograms = []
    for ts in ts_results:
        ts_id = ts['ts_id']

        # Simulate contrast stats (normalised floating point MRC)
        contrast_min = round(random.uniform(-0.08, -0.02), 4)
        contrast_max = round(random.uniform(0.08, 0.20), 4)

        # SIRT produces slightly smoother contrast
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
    print(f"  Tomograms reconstructed: {num_ts}")
    print(f"  Dimensions (voxels): {lateral_px} x {lateral_px} x {thickness_vox}")
    print(f"  Voxel size: {voxel_size_a} A  |  Binning: {binning}x")
    if reconstruction_method == 'sirt':
        print(f"  SIRT iterations: {sirt_iterations}")
    """

    stub:
    """
    touch tomogram_reconstruction_report.json
    touch tomograms_manifest.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    alignment_ch = Channel.fromPath(
        params.alignment_report ?: 'tilt_alignment_report.json',
        checkIfExists: false
    ).ifEmpty { file('tilt_alignment_report.json') }

    TOMOGRAM_RECONSTRUCTION(alignment_ch)
}
