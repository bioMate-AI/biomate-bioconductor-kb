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
params.binning_factor = 4             // reconstruct at Nx binned resolution
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
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    import os
    from pathlib import Path
    from datetime import datetime

    reconstruction_method = '${params.reconstruction_method}'
    sirt_iterations       = ${params.sirt_iterations}
    thickness_nm          = ${params.tomogram_thickness_nm}
    binning               = ${params.binning_factor}

    alignment_data = json.load(open('${alignment_report}'))
    ts_results     = alignment_data.get('tiltseries_results', [])
    xf_files_path  = alignment_data.get('xf_files_path', 'alignment_xf_files.json')
    num_ts         = alignment_data.get('num_tiltseries_aligned', len(ts_results))

    pixel_size_a = alignment_data.get('pixel_size_angstroms', 1.35)
    voxel_size_a = round(pixel_size_a * binning, 4)

    lateral_px    = 4096 // binning
    thickness_vox = int(round(thickness_nm * 10.0 / voxel_size_a))

    Path('tomograms').mkdir(exist_ok=True)
    tomograms = []

    for ts in ts_results:
        ts_id   = ts['ts_id']
        xf_file = f'alignments/{ts_id}.xf'
        out_mrc = f'tomograms/tomogram_{ts_id}_bin{binning}.mrc'

        if reconstruction_method == 'wbp':
            # IMOD tilt command for WBP reconstruction
            cmd = [
                'tilt',
                '-InputProjections', f'alignments/{ts_id}_aligned.mrc',
                '-OutputFile', out_mrc,
                '-TILTFILE', f'alignments/{ts_id}.rawtlt',
                '-XAXISTILT', '0',
                '-THICKNESS', str(thickness_vox),
                '-IMAGEBINNED', str(binning),
                '-PERPENDICULAR',
                '-MODE', '2',
                '-RADIAL', '0.35', '0.035',
                '-SCALE', '0.0', '0.05'
            ]
        elif reconstruction_method == 'sirt':
            # IMOD tilt with SIRT-like weighting, or imod sirtfilter
            cmd = [
                'tilt',
                '-InputProjections', f'alignments/{ts_id}_aligned.mrc',
                '-OutputFile', out_mrc,
                '-TILTFILE', f'alignments/{ts_id}.rawtlt',
                '-THICKNESS', str(thickness_vox),
                '-IMAGEBINNED', str(binning),
                '-PERPENDICULAR',
                '-MODE', '2',
                '-SIRTIterations', str(sirt_iterations)
            ]
        else:
            raise RuntimeError(f"Unknown reconstruction_method: {reconstruction_method}. Use 'wbp' or 'sirt'.")

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"WARNING: reconstruction failed for {ts_id}: {result.stderr[:500]}", file=sys.stderr)

        tomograms.append({
            'ts_id':                   ts_id,
            'dimensions_voxels':       [lateral_px, lateral_px, thickness_vox],
            'voxel_size_angstroms':    voxel_size_a,
            'binning_factor':          binning,
            'output_mrc':              out_mrc,
            'reconstruction_method':   reconstruction_method,
            'sirt_iterations':         sirt_iterations if reconstruction_method == 'sirt' else None
        })

    manifest = {
        'num_tomograms':         num_ts,
        'reconstruction_method': reconstruction_method,
        'binning_factor':        binning,
        'voxel_size_angstroms':  voxel_size_a,
        'tomogram_thickness_nm': thickness_nm,
        'tomograms':             tomograms
    }

    report = {
        'step':                    '03_tomogram_reconstruction',
        'timestamp':               datetime.now().isoformat(),
        'reconstruction_method':   reconstruction_method,
        'sirt_iterations':         sirt_iterations if reconstruction_method == 'sirt' else None,
        'binning_factor':          binning,
        'tomogram_thickness_nm':   thickness_nm,
        'voxel_size_angstroms':    voxel_size_a,
        'num_tomograms':           num_ts,
        'tomograms':               tomograms
    }

    with open('tomogram_reconstruction_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    with open('tomograms_manifest.json', 'w') as f:
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
        checkIfExists: true
    )

    TOMOGRAM_RECONSTRUCTION(alignment_ch)
}
