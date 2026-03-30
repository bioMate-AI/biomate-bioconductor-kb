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
params.pixel_size = 1.35            // Å/pixel
params.voltage = 300                // kV
params.spherical_aberration = 2.7   // mm
params.total_dose = 120.0           // e⁻/Å² total
params.tilt_range_min = -60.0       // degrees
params.tilt_range_max = 60.0        // degrees
params.tilt_increment = 3.0         // degrees between tilts
params.mock_mode = true
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

    # Generate tilt angles from range
    tilt_angles = []
    t = tilt_min
    while t <= tilt_max + 0.001:
        tilt_angles.append(round(t, 1))
        t += tilt_inc
    num_tilts = len(tilt_angles)
    dose_per_tilt = round(total_dose / num_tilts, 4)

    # Simulate 3 tilt series
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
    tiltseries_ch = Channel.fromPath(input_dir, type: 'dir', checkIfExists: false)
        .ifEmpty { file('.') }

    IMPORT_TILTSERIES(tiltseries_ch)
}
