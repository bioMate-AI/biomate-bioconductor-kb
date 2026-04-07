#!/usr/bin/env nextflow
/*
 * CryoSPARC Import Micrographs
 *
 * Imports preprocessed motion-corrected micrographs (MRC or TIFF) directly
 * into CryoSPARC, bypassing the motion-correction step.  This is the standard
 * starting point when motion correction was already performed externally --
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
    """
    #!/usr/bin/env python3
    import json
    import os
    from pathlib import Path
    from datetime import datetime

    mics_path  = '${params.micrographs_path}'
    pixel_size = ${params.pixel_size}
    voltage    = ${params.voltage}
    cs_mm      = ${params.spherical_aberration}
    total_dose = ${params.total_dose}

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs_conn = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs_conn.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('import_micrographs', params={
            'micrograph_path': mics_path,
            'pixel_size_A':    pixel_size,
            'kv':              voltage,
            'cs_mm':           cs_mm,
            'total_dose_eA2':  total_dose
        })
        job.queue()
        job.wait_for_done()

        mics_out = list(job.load_output('micrographs'))
        num_mics = len(mics_out)
        src_format = 'MRC'
        micrographs = mics_out
    else:
        # Scan the provided directory for micrograph files
        p = Path(mics_path)
        files = sorted(p.glob('*.mrc')) + sorted(p.glob('*.tif')) + sorted(p.glob('*.tiff'))
        num_mics = len(files)
        src_format = 'MRC' if any(f.suffix == '.mrc' for f in files) else 'TIFF'
        micrographs = []
        for i, f in enumerate(files):
            micrographs.append({
                'micrograph_idx':       i,
                'filename':             str(f),
                'pixel_size':           pixel_size,
                'voltage':              voltage,
                'spherical_aberration': cs_mm,
                'dose':                 total_dose,
                'width':                4096,
                'height':               4096,
                'dose_weighted':        True
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
        'source_path':   mics_path
    }

    with open('micrographs_imported.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('import_micrographs_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Imported {num_mics} micrographs ({src_format} format)")
    print(f"  Pixel size : {pixel_size} A/px")
    print(f"  Voltage    : {voltage} kV")
    print(f"  Total dose : {total_dose} e-/A2")
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
    Source path  : ${params.micrographs_path ?: '(required: --micrographs_path)'}
    Pixel size   : ${params.pixel_size} A/px
    Voltage      : ${params.voltage} kV
    Cs           : ${params.spherical_aberration} mm
    Total dose   : ${params.total_dose} e-/A2
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
          Pixel size           : ${r.pixel_size} A/px
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Import Micrographs completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
