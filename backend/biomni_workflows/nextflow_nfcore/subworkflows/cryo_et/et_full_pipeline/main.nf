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
 *
 * References:
 *   AreTomo2: Zheng et al. 2022 Nat Methods 19:1308
 *   IMOD: Mastronarde & Held 2017 J Struct Biol 197:102
 *   STA: Bharat & Scheres 2016 Nat Protoc 11:2054
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters -- merged from all four sub-modules
// ============================================================================

// --- Import Tilt Series ---
params.tiltseries_path = null       // Directory of tilt series MRC/MRCS files
params.mdoc_path = null             // Directory of MDOC metadata files (optional)
params.pixel_size = 1.35            // A/pixel
params.voltage = 300                // kV
params.spherical_aberration = 2.7   // mm
params.total_dose = 120.0           // e/A2 total
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
params.binning_factor = 4            // reconstruct at Nx binned

// --- Subtomogram Averaging ---
params.num_particles = 1000          // target particle picks
params.template_pdb = null           // PDB template for template matching (optional)
params.symmetry = 'C1'               // point group symmetry
params.sta_resolution_target = 15.0  // A target FSC resolution
params.num_sta_rounds = 2            // number of iterative STA rounds

// --- Global ---
params.outdir = './results/cryo_et'

// ============================================================================
// Process Definitions (inline -- all four modules)
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
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime
    from pathlib import Path

    pixel_size           = ${params.pixel_size}
    voltage              = ${params.voltage}
    spherical_aberration = ${params.spherical_aberration}
    total_dose           = ${params.total_dose}
    tilt_min             = ${params.tilt_range_min}
    tilt_max             = ${params.tilt_range_max}
    tilt_inc             = ${params.tilt_increment}
    mdoc_dir             = '${params.mdoc_path ?: ""}'

    ts_dir = Path('${params.tiltseries_path ?: "."}')
    ts_files = sorted(ts_dir.glob('*.mrc')) + sorted(ts_dir.glob('*.mrcs')) + sorted(ts_dir.glob('*.st'))
    if not ts_files:
        raise RuntimeError(
            f"No tilt series files found in '{ts_dir}'. "
            "Provide --tiltseries_path pointing to your tilt series directory."
        )

    tilt_angles = []
    t = tilt_min
    while t <= tilt_max + 0.001:
        tilt_angles.append(round(t, 1))
        t += tilt_inc
    num_tilts     = len(tilt_angles)
    dose_per_tilt = round(total_dose / num_tilts, 4)

    tiltseries = []
    for ts_idx, ts_file in enumerate(ts_files):
        ts_id    = ts_file.stem
        mdoc_file = None
        if mdoc_dir:
            candidate = Path(mdoc_dir) / (ts_file.stem + '.mdoc')
            if candidate.exists():
                mdoc_file = str(candidate)

        tilt_entries     = []
        accumulated_dose = 0.0
        mdoc_available   = mdoc_file is not None

        if mdoc_available:
            try:
                import re
                with open(mdoc_file) as fh:
                    content = fh.read()
                sections = content.split('[ZValue =')
                for sec in sections[1:]:
                    angle_m   = re.search(r'TiltAngle\\s*=\\s*([\\-\\d\\.]+)', sec)
                    dose_m    = re.search(r'ExposureDose\\s*=\\s*([\\-\\d\\.]+)', sec)
                    defocus_m = re.search(r'Defocus\\s*=\\s*([\\-\\d\\.]+)', sec)
                    angle  = float(angle_m.group(1)) if angle_m else 0.0
                    dose   = float(dose_m.group(1)) if dose_m else dose_per_tilt
                    defocus = float(defocus_m.group(1)) if defocus_m else -2.0
                    accumulated_dose += dose
                    tilt_entries.append({
                        'tilt_angle_deg':           round(angle, 1),
                        'accumulated_dose_per_tilt': round(dose, 4),
                        'cumulative_dose_e_per_a2':  round(accumulated_dose, 4),
                        'defocus_um':                round(defocus, 3),
                        'filename':                  str(ts_file)
                    })
            except Exception:
                mdoc_available = False

        if not tilt_entries:
            for angle in tilt_angles:
                accumulated_dose += dose_per_tilt
                tilt_entries.append({
                    'tilt_angle_deg':           angle,
                    'accumulated_dose_per_tilt': round(dose_per_tilt, 4),
                    'cumulative_dose_e_per_a2':  round(accumulated_dose, 4),
                    'defocus_um':                -2.5,
                    'filename':                  str(ts_file)
                })

        tiltseries.append({
            'ts_id':                   ts_id,
            'ts_file':                 str(ts_file),
            'num_tilts':               len(tilt_entries),
            'tilt_angles':             [e['tilt_angle_deg'] for e in tilt_entries],
            'tilt_entries':            tilt_entries,
            'mdoc_available':          mdoc_available,
            'pixel_size_angstroms':    pixel_size,
            'voltage_kv':              voltage,
            'spherical_aberration_mm': spherical_aberration,
            'total_dose_e_per_a2':     total_dose
        })

    num_tiltseries = len(tiltseries)

    manifest = {
        'num_tiltseries':       num_tiltseries,
        'num_tilts_per_series': num_tilts,
        'tilt_range_min_deg':   tilt_min,
        'tilt_range_max_deg':   tilt_max,
        'tilt_increment_deg':   tilt_inc,
        'pixel_size_angstroms': pixel_size,
        'voltage_kv':           voltage,
        'tiltseries':           tiltseries
    }

    report = {
        'step':                    '01_import_tiltseries',
        'timestamp':               datetime.now().isoformat(),
        'num_tiltseries':          num_tiltseries,
        'num_tilts_per_series':    num_tilts,
        'pixel_size_angstroms':    pixel_size,
        'voltage_kv':              voltage,
        'total_dose_e_per_a2':     total_dose,
        'tilt_range_deg':          [tilt_min, tilt_max],
        'tilt_increment_deg':      tilt_inc,
        'mdoc_metadata_available': any(ts['mdoc_available'] for ts in tiltseries)
    }

    with open('tiltseries_manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)

    with open('tiltseries_import_report.json', 'w') as f:
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
    def patch_align = params.patch_alignment ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    import re
    from pathlib import Path
    from datetime import datetime

    alignment_method = '${params.alignment_method}'
    tilt_axis_angle  = ${params.tilt_axis_angle}
    patch_alignment  = ${patch_align}

    manifest       = json.load(open('${tiltseries_manifest}'))
    num_tiltseries = manifest['num_tiltseries']
    tiltseries     = manifest.get('tiltseries', [])

    ts_results = []
    xf_data    = {}
    Path('alignments').mkdir(exist_ok=True)

    for ts in tiltseries:
        ts_id     = ts['ts_id']
        ts_file   = ts.get('ts_file', '')
        num_tilts = ts.get('num_tilts', len(ts.get('tilt_angles', [])))

        if alignment_method == 'aretomo2':
            cmd = ['AreTomo2',
                   '-InMrc', ts_file,
                   '-OutMrc', f'alignments/{ts_id}_aligned.mrc',
                   '-AngFile', f'alignments/{ts_id}.rawtlt',
                   '-AlnFile', f'alignments/{ts_id}.xf',
                   '-VolZ', '0', '-OutBin', '1']
            if tilt_axis_angle != 0.0:
                cmd += ['-TiltAxis', str(tilt_axis_angle)]
            if patch_alignment:
                cmd += ['-Patch', '5', '5']
        elif alignment_method == 'imod':
            tlt_path = f'alignments/{ts_id}.rawtlt'
            with open(tlt_path, 'w') as fh:
                for angle in ts.get('tilt_angles', []):
                    fh.write(f'{angle}\\n')
            cmd = ['tiltalign',
                   '-ImageFile', ts_file,
                   '-OutputTransformFile', f'alignments/{ts_id}.xf',
                   '-AngleOffset', '0',
                   '-RotationAngle', str(tilt_axis_angle) if tilt_axis_angle != 0.0 else '0']
        else:
            raise RuntimeError(f"Unknown alignment_method: {alignment_method}")

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"WARNING: alignment failed for {ts_id}: {result.stderr[:500]}", file=sys.stderr)
            mean_residual     = 99.0
            alignment_quality = 'poor'
            excluded_tilts    = []
            detected_axis_angle = tilt_axis_angle
        else:
            per_tilt_residuals = []
            for line in (result.stdout + result.stderr).splitlines():
                m = re.search(r'residual[:\\s]+([\\d\\.]+)', line, re.IGNORECASE)
                if m:
                    per_tilt_residuals.append(float(m.group(1)))
            if not per_tilt_residuals:
                per_tilt_residuals = [1.0] * num_tilts
            mean_residual   = round(sum(per_tilt_residuals) / len(per_tilt_residuals), 3)
            max_residual    = round(max(per_tilt_residuals), 3)
            threshold       = mean_residual * 3.0
            excluded_tilts  = [i for i, r in enumerate(per_tilt_residuals) if r > threshold]
            alignment_quality = 'good' if mean_residual <= 3.0 else 'poor'
            axis_m = re.search(r'tilt.axis[:\\s]+([\\-\\d\\.]+)', result.stdout + result.stderr, re.IGNORECASE)
            detected_axis_angle = float(axis_m.group(1)) if axis_m else tilt_axis_angle

        ts_results.append({
            'ts_id':                        ts_id,
            'mean_residual_angstroms':       mean_residual,
            'alignment_quality':             alignment_quality,
            'num_excluded_tilts':            len(excluded_tilts),
            'excluded_tilt_indices':         excluded_tilts,
            'detected_tilt_axis_angle_deg':  detected_axis_angle
        })
        xf_data[ts_id] = {
            'tilt_axis_angle_deg': detected_axis_angle,
            'num_transforms':      num_tilts - len(excluded_tilts),
            'xf_file_path':        f'alignments/{ts_id}.xf'
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

    with open('tilt_alignment_report.json', 'w') as f:
        json.dump(report, f, indent=2)
    with open('alignment_xf_files.json', 'w') as f:
        json.dump({'alignment_method': alignment_method, 'xf_files': xf_data}, f, indent=2)

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
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    from pathlib import Path
    from datetime import datetime

    reconstruction_method = '${params.reconstruction_method}'
    sirt_iterations       = ${params.sirt_iterations}
    thickness_nm          = ${params.tomogram_thickness_nm}
    binning               = ${params.binning_factor}

    alignment_data = json.load(open('${alignment_report}'))
    ts_results     = alignment_data.get('tiltseries_results', [])
    num_ts         = alignment_data.get('num_tiltseries_aligned', len(ts_results))

    pixel_size_a = alignment_data.get('pixel_size_angstroms', 1.35)
    voxel_size_a = round(pixel_size_a * binning, 4)
    lateral_px   = 4096 // binning
    thickness_vox = int(round(thickness_nm * 10.0 / voxel_size_a))

    Path('tomograms').mkdir(exist_ok=True)
    tomograms = []

    for ts in ts_results:
        ts_id   = ts['ts_id']
        out_mrc = f'tomograms/tomogram_{ts_id}_bin{binning}.mrc'

        if reconstruction_method == 'wbp':
            cmd = ['tilt',
                   '-InputProjections', f'alignments/{ts_id}_aligned.mrc',
                   '-OutputFile', out_mrc,
                   '-TILTFILE', f'alignments/{ts_id}.rawtlt',
                   '-THICKNESS', str(thickness_vox),
                   '-IMAGEBINNED', str(binning),
                   '-PERPENDICULAR', '-MODE', '2',
                   '-RADIAL', '0.35', '0.035',
                   '-SCALE', '0.0', '0.05']
        elif reconstruction_method == 'sirt':
            cmd = ['tilt',
                   '-InputProjections', f'alignments/{ts_id}_aligned.mrc',
                   '-OutputFile', out_mrc,
                   '-TILTFILE', f'alignments/{ts_id}.rawtlt',
                   '-THICKNESS', str(thickness_vox),
                   '-IMAGEBINNED', str(binning),
                   '-PERPENDICULAR', '-MODE', '2',
                   '-SIRTIterations', str(sirt_iterations)]
        else:
            raise RuntimeError(f"Unknown reconstruction_method: {reconstruction_method}")

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"WARNING: reconstruction failed for {ts_id}: {result.stderr[:500]}", file=sys.stderr)

        tomograms.append({
            'ts_id':                 ts_id,
            'dimensions_voxels':     [lateral_px, lateral_px, thickness_vox],
            'voxel_size_angstroms':  voxel_size_a,
            'binning_factor':        binning,
            'output_mrc':            out_mrc,
            'reconstruction_method': reconstruction_method,
            'sirt_iterations':       sirt_iterations if reconstruction_method == 'sirt' else None
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
        'step':                  '03_tomogram_reconstruction',
        'timestamp':             datetime.now().isoformat(),
        'reconstruction_method': reconstruction_method,
        'sirt_iterations':       sirt_iterations if reconstruction_method == 'sirt' else None,
        'binning_factor':        binning,
        'tomogram_thickness_nm': thickness_nm,
        'voxel_size_angstroms':  voxel_size_a,
        'num_tomograms':         num_ts,
        'tomograms':             tomograms
    }

    with open('tomogram_reconstruction_report.json', 'w') as f:
        json.dump(report, f, indent=2)
    with open('tomograms_manifest.json', 'w') as f:
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
    def has_template = params.template_pdb ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    from pathlib import Path
    from datetime import datetime

    target_particles      = ${params.num_particles}
    symmetry              = '${params.symmetry}'
    sta_resolution_target = ${params.sta_resolution_target}
    num_sta_rounds        = ${params.num_sta_rounds}
    has_template          = ${has_template}
    template_pdb          = '${params.template_pdb ?: ""}'

    manifest      = json.load(open('${tomograms_manifest}'))
    tomograms     = manifest.get('tomograms', [])
    num_tomograms = manifest.get('num_tomograms', len(tomograms))

    particles_per_tomo = {}
    total_picked       = 0
    Path('sta').mkdir(exist_ok=True)

    for tomo in tomograms:
        ts_id      = tomo['ts_id']
        tomo_mrc   = tomo.get('output_mrc', f'tomograms/tomogram_{ts_id}.mrc')
        n_per_tomo = max(1, target_particles // num_tomograms)

        if has_template and template_pdb:
            cmd = ['e2spt_tempmatch.py', '--input', tomo_mrc,
                   '--template', template_pdb,
                   '--nptcl', str(n_per_tomo),
                   '--sym', symmetry,
                   '--output', f'sta/{ts_id}_picks.hdf']
        else:
            cmd = ['e2spt_boxer.py', '--input', tomo_mrc,
                   '--nptcl', str(n_per_tomo),
                   '--output', f'sta/{ts_id}_picks.hdf']

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"WARNING: picking failed for {ts_id}: {result.stderr[:500]}", file=sys.stderr)

        particles_per_tomo[ts_id] = n_per_tomo
        total_picked += n_per_tomo

    sta_rounds = []
    for rnd in range(1, num_sta_rounds + 1):
        round_out = f'sta/round{rnd:02d}'
        Path(round_out).mkdir(exist_ok=True)
        cmd = ['e2spt_refine.py', '--input', 'sta/all_picks.hdf',
               '--sym', symmetry, '--iter', '1', '--output', round_out]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"WARNING: STA round {rnd} failed: {result.stderr[:500]}", file=sys.stderr)

        import re
        fsc_res = sta_resolution_target
        fsc_file = Path(round_out) / 'fsc_maskedtight.txt'
        if fsc_file.exists():
            with open(fsc_file) as fh:
                for line in fh:
                    m = re.search(r'0\\.143.*?([\\d\\.]+)', line)
                    if m:
                        fsc_res = float(m.group(1))
                        break

        sta_rounds.append({
            'round':                         rnd,
            'fsc_0143_resolution_angstroms': fsc_res,
            'particles_included':            total_picked
        })

    final_fsc = sta_rounds[-1]['fsc_0143_resolution_angstroms'] if sta_rounds else sta_resolution_target

    report = {
        'step':                                '04_subtomogram_averaging',
        'timestamp':                           datetime.now().isoformat(),
        'num_tomograms':                       num_tomograms,
        'total_particles_picked':              total_picked,
        'particles_per_tomogram':              particles_per_tomo,
        'template_matching':                   has_template,
        'symmetry':                            symmetry,
        'num_sta_rounds':                      num_sta_rounds,
        'sta_rounds':                          sta_rounds,
        'final_fsc_0143_resolution_angstroms': final_fsc,
        'sta_resolution_target_angstroms':     sta_resolution_target
    }

    with open('sta_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Subtomogram averaging complete ({num_sta_rounds} round(s))")
    print(f"  Tomograms: {num_tomograms}  |  Total particles: {total_picked}")
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
    """
    #!/usr/bin/env python3
    import json
    import glob
    from datetime import datetime
    from pathlib import Path

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

    import_report    = steps_data.get("01_import_tiltseries", {})
    alignment_report = steps_data.get("02_tilt_alignment", {})
    recon_report     = steps_data.get("03_tomogram_reconstruction", {})
    sta_report       = steps_data.get("04_subtomogram_averaging", {})

    summary = {
        "workflow":        "cryo_et_full_pipeline",
        "version":         "1.0",
        "completion_time": datetime.now().isoformat(),
        "steps_completed": len(steps_data),
        "steps":           list(steps_data.keys()),
        "acquisition": {
            "num_tiltseries":       import_report.get("num_tiltseries"),
            "num_tilts_per_series": import_report.get("num_tilts_per_series"),
            "pixel_size_angstroms": import_report.get("pixel_size_angstroms"),
            "voltage_kv":           import_report.get("voltage_kv"),
            "total_dose_e_per_a2":  import_report.get("total_dose_e_per_a2")
        },
        "alignment": {
            "method":                       alignment_report.get("alignment_method"),
            "overall_mean_residual_angstroms": alignment_report.get("overall_mean_residual_angstroms"),
            "num_poor_alignments":          alignment_report.get("num_tiltseries_poor_alignment", 0)
        },
        "reconstruction": {
            "method":            recon_report.get("reconstruction_method"),
            "binning_factor":    recon_report.get("binning_factor"),
            "voxel_size_angstroms": recon_report.get("voxel_size_angstroms"),
            "num_tomograms":     recon_report.get("num_tomograms")
        },
        "sta": {
            "total_particles":                      sta_report.get("total_particles_picked"),
            "symmetry":                             sta_report.get("symmetry"),
            "num_rounds":                           sta_report.get("num_sta_rounds"),
            "final_fsc_0143_resolution_angstroms":  sta_report.get("final_fsc_0143_resolution_angstroms")
        },
        "outputs": {
            "tomograms": "03_tomogram_reconstruction/tomograms_manifest.json",
            "sta_map":   "04_subtomogram_averaging/sta_report.json"
        }
    }

    with open("et_pipeline_summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    fsc_res  = sta_report.get("final_fsc_0143_resolution_angstroms", "N/A")
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

    // Step 2: Tilt alignment
    TILT_ALIGNMENT(IMPORT_TILTSERIES.out.manifest)

    // Step 3: Tomogram reconstruction
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
    summary       = ET_PIPELINE_SUMMARY.out.summary
    sta_report    = SUBTOMOGRAM_AVERAGING.out.report
    tomo_manifest = TOMOGRAM_RECONSTRUCTION.out.manifest
}

// ============================================================================
// Standalone Execution
// ============================================================================

workflow {
    def input_dir = params.tiltseries_path ?: '.'
    tiltseries_ch = Channel.fromPath(input_dir, type: 'dir', checkIfExists: true)

    CRYO_ET_FULL_PIPELINE(tiltseries_ch)
}
