#!/usr/bin/env nextflow
/*
 * Cryo-ET: Import Tilt Series
 *
 * Imports tilt series MRC/MRCS files and associated MDOC metadata.
 * Generates a tiltseries_manifest.json describing each tilt series
 * (tilt angles, pixel size, dose, voltage) for downstream processing.
 *
 * Step 1 of the Cryo-ET pipeline.
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.tiltseries_path = null       // Directory of tilt series MRC/MRCS files
params.mdoc_path = null             // Directory of MDOC metadata files (optional)
params.pixel_size = 1.35            // A/pixel
params.voltage = 300                // kV
params.spherical_aberration = 2.7   // mm
params.total_dose = 120.0           // e/A2 total
params.tilt_range_min = -60.0       // degrees
params.tilt_range_max = 60.0        // degrees
params.tilt_increment = 3.0         // degrees between tilts
params.outdir = './results/cryo_et'

// ============================================================================
// Process Definition
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

    # Scan the tiltseries directory for MRC/MRCS files
    ts_dir = Path('${params.tiltseries_path ?: "."}')
    ts_files = sorted(ts_dir.glob('*.mrc')) + sorted(ts_dir.glob('*.mrcs')) + sorted(ts_dir.glob('*.st'))
    if not ts_files:
        raise RuntimeError(
            f"No tilt series files (*.mrc/*.mrcs/*.st) found in '{ts_dir}'. "
            "Provide --tiltseries_path pointing to your tilt series directory."
        )

    # Generate expected tilt angles from range
    tilt_angles = []
    t = tilt_min
    while t <= tilt_max + 0.001:
        tilt_angles.append(round(t, 1))
        t += tilt_inc
    num_tilts = len(tilt_angles)
    dose_per_tilt = round(total_dose / num_tilts, 4)

    tiltseries = []
    for ts_idx, ts_file in enumerate(ts_files):
        ts_id = ts_file.stem
        mdoc_file = None
        if mdoc_dir:
            candidate = Path(mdoc_dir) / (ts_file.stem + '.mdoc')
            if candidate.exists():
                mdoc_file = str(candidate)

        tilt_entries = []
        accumulated_dose = 0.0

        # Try to read MDOC for per-tilt metadata
        mdoc_available = mdoc_file is not None
        if mdoc_available:
            try:
                with open(mdoc_file) as fh:
                    content = fh.read()
                # Parse MDOC: extract TiltAngle and ExposureDose per section
                import re
                sections = content.split('[ZValue =')
                for sec in sections[1:]:
                    angle_match = re.search(r'TiltAngle\\s*=\\s*([\\-\\d\\.]+)', sec)
                    dose_match  = re.search(r'ExposureDose\\s*=\\s*([\\-\\d\\.]+)', sec)
                    defocus_match = re.search(r'Defocus\\s*=\\s*([\\-\\d\\.]+)', sec)
                    angle  = float(angle_match.group(1)) if angle_match else 0.0
                    dose   = float(dose_match.group(1)) if dose_match else dose_per_tilt
                    defocus = float(defocus_match.group(1)) if defocus_match else -2.0
                    accumulated_dose += dose
                    tilt_entries.append({
                        'tilt_angle_deg':           round(angle, 1),
                        'accumulated_dose_per_tilt': round(dose, 4),
                        'cumulative_dose_e_per_a2':  round(accumulated_dose, 4),
                        'defocus_um':                round(defocus, 3),
                        'filename':                  str(ts_file)
                    })
            except Exception as e:
                print(f"Warning: failed to parse MDOC {mdoc_file}: {e}")
                mdoc_available = False

        if not tilt_entries:
            # Fall back to range-based angles
            for i, angle in enumerate(tilt_angles):
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
            'mdoc_file':               mdoc_file,
            'pixel_size_angstroms':    pixel_size,
            'voltage_kv':              voltage,
            'spherical_aberration_mm': spherical_aberration,
            'total_dose_e_per_a2':     total_dose
        })

    num_tiltseries = len(tiltseries)

    manifest = {
        'num_tiltseries':        num_tiltseries,
        'num_tilts_per_series':  num_tilts,
        'tilt_range_min_deg':    tilt_min,
        'tilt_range_max_deg':    tilt_max,
        'tilt_increment_deg':    tilt_inc,
        'pixel_size_angstroms':  pixel_size,
        'voltage_kv':            voltage,
        'tiltseries':            tiltseries
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
    print(f"  Tilts per series: {num_tilts} ({tilt_min} to {tilt_max} deg, step {tilt_inc} deg)")
    print(f"  Pixel size: {pixel_size} A/px  |  Voltage: {voltage} kV")
    print(f"  Total dose: {total_dose} e-/A2  |  Per-tilt dose: {dose_per_tilt:.3f} e-/A2")
    """

    stub:
    """
    touch tiltseries_manifest.json
    touch tiltseries_import_report.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    def input_dir = params.tiltseries_path ?: '.'
    tiltseries_ch = Channel.fromPath(input_dir, type: 'dir', checkIfExists: true)

    IMPORT_TILTSERIES(tiltseries_ch)
}
