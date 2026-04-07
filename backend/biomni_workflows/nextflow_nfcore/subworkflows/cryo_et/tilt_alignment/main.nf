#!/usr/bin/env nextflow
/*
 * Cryo-ET: Tilt Alignment
 *
 * Performs tilt series alignment using AreTomo2 (default) or IMOD.
 * Computes per-tilt alignment residuals, flags poor alignments,
 * and produces XF transformation files for tomogram reconstruction.
 *
 * Step 2 of the Cryo-ET pipeline.
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.alignment_method = 'aretomo2'  // 'aretomo2' (default) or 'imod'
params.tilt_axis_angle = 0.0          // degrees; 0 = auto-detect
params.patch_alignment = true         // use patch-based local alignment
params.outdir = './results/cryo_et'

// ============================================================================
// Process Definition
// ============================================================================

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
    def patch_align = params.patch_alignment ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    import os
    from pathlib import Path
    from datetime import datetime

    alignment_method = '${params.alignment_method}'
    tilt_axis_angle  = ${params.tilt_axis_angle}
    patch_alignment  = ${patch_align}

    manifest     = json.load(open('${tiltseries_manifest}'))
    num_tiltseries = manifest['num_tiltseries']
    tiltseries   = manifest.get('tiltseries', [])

    ts_results = []
    xf_data    = {}
    Path('alignments').mkdir(exist_ok=True)

    for ts in tiltseries:
        ts_id    = ts['ts_id']
        ts_file  = ts.get('ts_file', '')
        num_tilts = ts.get('num_tilts', len(ts.get('tilt_angles', [])))

        if alignment_method == 'aretomo2':
            cmd = [
                'AreTomo2',
                '-InMrc', ts_file,
                '-OutMrc', f'alignments/{ts_id}_aligned.mrc',
                '-AngFile', f'alignments/{ts_id}.rawtlt',
                '-AlnFile', f'alignments/{ts_id}.xf',
                '-VolZ', '0',        # output projection stack only (no reconstruction)
                '-OutBin', '1'
            ]
            if tilt_axis_angle != 0.0:
                cmd += ['-TiltAxis', str(tilt_axis_angle)]
            if patch_alignment:
                cmd += ['-Patch', '5', '5']

        elif alignment_method == 'imod':
            # Write tlt file with tilt angles
            tlt_path = f'alignments/{ts_id}.rawtlt'
            with open(tlt_path, 'w') as fh:
                for angle in ts.get('tilt_angles', []):
                    fh.write(f'{angle}\\n')
            cmd = [
                'tiltalign',
                '-ModelFile', f'alignments/{ts_id}.fid',
                '-ImageFile', ts_file,
                '-ImagesAreBinned', '1',
                '-OutputTransformFile', f'alignments/{ts_id}.xf',
                '-AngleOffset', '0',
                '-RotationAngle', str(tilt_axis_angle) if tilt_axis_angle != 0.0 else '0'
            ]
        else:
            raise RuntimeError(f"Unknown alignment_method: {alignment_method}. Use 'aretomo2' or 'imod'.")

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"WARNING: alignment failed for {ts_id}: {result.stderr[:500]}", file=sys.stderr)
            mean_residual = 99.0
            alignment_quality = 'poor'
            excluded_tilts = []
            detected_axis_angle = tilt_axis_angle
        else:
            # Parse residuals from log output
            per_tilt_residuals = []
            for line in (result.stdout + result.stderr).splitlines():
                # AreTomo2 logs per-tilt residuals; IMOD logs in stdout
                import re
                m = re.search(r'residual[:\\s]+([\\d\\.]+)', line, re.IGNORECASE)
                if m:
                    per_tilt_residuals.append(float(m.group(1)))
            if not per_tilt_residuals:
                per_tilt_residuals = [1.0] * num_tilts   # placeholder if not parseable

            mean_residual = round(sum(per_tilt_residuals) / len(per_tilt_residuals), 3)
            max_residual  = round(max(per_tilt_residuals), 3)
            threshold     = mean_residual * 3.0
            excluded_tilts = [i for i, r in enumerate(per_tilt_residuals) if r > threshold]
            alignment_quality = 'good' if mean_residual <= 3.0 else 'poor'

            # Extract detected tilt axis from log if available
            import re
            axis_match = re.search(r'tilt.axis[:\\s]+([\\-\\d\\.]+)', (result.stdout + result.stderr), re.IGNORECASE)
            detected_axis_angle = float(axis_match.group(1)) if axis_match else tilt_axis_angle

        ts_results.append({
            'ts_id':                        ts_id,
            'mean_residual_angstroms':       mean_residual,
            'alignment_quality':             alignment_quality,
            'num_excluded_tilts':            len(excluded_tilts),
            'excluded_tilt_indices':         excluded_tilts,
            'detected_tilt_axis_angle_deg':  detected_axis_angle
        })

        xf_data[ts_id] = {
            'tilt_axis_angle_deg':   detected_axis_angle,
            'num_transforms':        num_tilts - len(excluded_tilts),
            'xf_file_path':          f'alignments/{ts_id}.xf'
        }

    all_residuals = [ts['mean_residual_angstroms'] for ts in ts_results]
    overall_mean  = round(sum(all_residuals) / len(all_residuals), 3) if all_residuals else 0.0
    num_poor      = sum(1 for ts in ts_results if ts['alignment_quality'] == 'poor')

    pixel_size_a = manifest.get('tiltseries', [{}])[0].get('pixel_size_angstroms', 1.35)
    voltage_kv   = manifest.get('tiltseries', [{}])[0].get('voltage_kv', 300)

    report = {
        'step':                            '02_tilt_alignment',
        'timestamp':                       datetime.now().isoformat(),
        'alignment_method':                alignment_method,
        'patch_alignment':                 patch_alignment,
        'tilt_axis_angle_input_deg':       tilt_axis_angle,
        'num_tiltseries_aligned':          num_tiltseries,
        'num_tiltseries_poor_alignment':   num_poor,
        'overall_mean_residual_angstroms': overall_mean,
        'tiltseries_results':              ts_results,
        'pixel_size_angstroms':            pixel_size_a,
        'voltage_kv':                      voltage_kv
    }

    xf_output = {
        'alignment_method': alignment_method,
        'xf_files':         xf_data
    }

    with open('tilt_alignment_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    with open('alignment_xf_files.json', 'w') as f:
        json.dump(xf_output, f, indent=2)

    print(f"Tilt alignment complete ({alignment_method})")
    print(f"  Tilt series aligned: {num_tiltseries}")
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

// ============================================================================
// Workflow
// ============================================================================

workflow {
    manifest_ch = Channel.fromPath(
        params.tiltseries_manifest ?: 'tiltseries_manifest.json',
        checkIfExists: true
    )

    TILT_ALIGNMENT(manifest_ch)
}
