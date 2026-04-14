#!/usr/bin/env nextflow
/*
 * CryoSPARC Import Micrographs
 *
 * Imports preprocessed motion-corrected micrographs (MRC or TIFF) directly
 * into CryoSPARC, bypassing the motion-correction step.  This is the standard
 * starting point when motion correction was already performed externally —
 * e.g., in CryoSPARC Live, MotionCor2 standalone, or another pipeline.
 * Corresponds to the CryoSPARC "import_micrographs" job type.
 *
 * References:
 *   Punjani et al. 2017 Nat Methods 14:290  (CryoSPARC)
 *   Zheng et al. 2017 Nat Methods 14:331    (MotionCor2)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.micrographs_path      = null    // directory of preprocessed MRC/TIFF files
params.pixel_size            = 1.05    // Å/pixel
params.voltage               = 300     // kV
params.spherical_aberration  = 2.7     // mm
params.total_dose            = 50.0    // e-/Å²
params.mock_mode             = true
params.use_cryosparc         = false
params.outdir                = './results/import_micrographs'

// ============================================================================
// Process Definition
// ============================================================================

process IMPORT_MICROGRAPHS {
    tag "import_micrographs"
    publishDir "${params.outdir}/import_micrographs", mode: 'copy'

    output:
    path "micrographs_imported.cs",        emit: micrographs_cs
    path "import_micrographs_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import os
    import random
    from pathlib import Path
    from datetime import datetime

    random.seed(None)

    mock_mode      = ${mock}
    mics_path      = '${params.micrographs_path}'
    pixel_size     = ${params.pixel_size}
    voltage        = ${params.voltage}
    cs_mm          = ${params.spherical_aberration}
    total_dose     = ${params.total_dose}

    if mock_mode or mics_path == 'null' or not mics_path:
        # Mock: simulate importing 30 preprocessed micrographs
        num_mics = 30
        src_format = 'MRC'
        micrographs = []
        for i in range(num_mics):
            micrographs.append({
                'micrograph_idx':     i,
                'filename':           f'micrograph_{i:05d}.mrc',
                'pixel_size':         pixel_size,
                'voltage':            voltage,
                'spherical_aberration': cs_mm,
                'dose':               total_dose,
                'width':              4096,
                'height':             4096,
                'dose_weighted':      True,
                'estimated_b_factor': round(random.uniform(-120, -40), 1)
            })
    else:
        # Live: scan the provided directory
        p = Path(mics_path)
        files = sorted(p.glob('*.mrc')) + sorted(p.glob('*.tif')) + sorted(p.glob('*.tiff'))
        num_mics = len(files)
        src_format = 'MRC' if any(f.suffix == '.mrc' for f in files) else 'TIFF'
        micrographs = []
        for i, f in enumerate(files):
            micrographs.append({
                'micrograph_idx':     i,
                'filename':           str(f),
                'pixel_size':         pixel_size,
                'voltage':            voltage,
                'spherical_aberration': cs_mm,
                'dose':               total_dose,
                'width':              4096,
                'height':             4096,
                'dose_weighted':      True
            })

    cs_data = {
        'micrographs': micrographs,
        'count':        num_mics
    }

    report = {
        'step':          'import_micrographs',
        'timestamp':     datetime.now().isoformat(),
        'num_micrographs': num_mics,
        'pixel_size':    pixel_size,
        'voltage':       voltage,
        'spherical_aberration_mm': cs_mm,
        'total_dose':    total_dose,
        'format':        src_format,
        'source_path':   mics_path if mics_path != 'null' else 'mock',
        'mock_mode':     mock_mode
    }

    with open('micrographs_imported.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('import_micrographs_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Imported {num_mics} micrographs ({src_format} format)")
    print(f"  Pixel size : {pixel_size} Å/px")
    print(f"  Voltage    : {voltage} kV")
    print(f"  Total dose : {total_dose} e-/Å²")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC Import Micrographs
    ====================================================================
    Source path  : ${params.micrographs_path ?: '(mock — 30 synthetic micrographs)'}
    Pixel size   : ${params.pixel_size} Å/px
    Voltage      : ${params.voltage} kV
    Cs           : ${params.spherical_aberration} mm
    Total dose   : ${params.total_dose} e-/Å²
    Mode         : ${params.mock_mode ? 'MOCK (testing)' : 'LIVE (CryoSPARC)'}
    Output       : ${params.outdir}
    ====================================================================
    """.stripIndent()

    IMPORT_MICROGRAPHS()

    IMPORT_MICROGRAPHS.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Import Micrographs Results:
          Micrographs imported : ${r.num_micrographs}
          Format               : ${r.format}
          Pixel size           : ${r.pixel_size} Å/px
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Import Micrographs completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
