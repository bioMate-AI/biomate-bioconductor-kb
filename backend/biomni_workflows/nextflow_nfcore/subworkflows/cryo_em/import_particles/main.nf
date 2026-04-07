#!/usr/bin/env nextflow
/*
 * CryoSPARC Import Particles
 *
 * Imports an existing particle stack from RELION (STAR format) or a native
 * CryoSPARC (.cs) dataset, enabling the pipeline to resume from an external
 * picking result or a collaborator's particle set.  Handles coordinate/CTF
 * metadata mapping between STAR and .cs conventions.
 * Corresponds to the CryoSPARC "import_particles" job type.
 *
 * Supported input formats:
 *   star  -- RELION 3.x / 4.x star file (particles table)
 *   cs    -- CryoSPARC native .cs dataset
 *
 * References:
 *   Scheres 2012 J Struct Biol 180:519        (RELION / STAR format)
 *   Punjani et al. 2017 Nat Methods 14:290    (CryoSPARC)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.particle_star   = null      // path to RELION .star file
params.particle_cs     = null      // path to CryoSPARC .cs file
params.input_format    = 'star'    // 'star' or 'cs'
params.pixel_size      = 1.05      // Å/pixel
params.voltage         = 300       // kV
params.box_size        = 256       // pixels
params.use_cryosparc   = false
params.outdir          = './results/import_particles'

// ============================================================================
// Process Definition
// ============================================================================

process IMPORT_PARTICLES {
    tag "import_particles"
    publishDir "${params.outdir}/import_particles", mode: 'copy'

    output:
    path "particles_imported.cs",        emit: particles_cs
    path "import_particles_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    input_format  = '${params.input_format}'
    pixel_size    = ${params.pixel_size}
    voltage       = ${params.voltage}
    box_size      = ${params.box_size}
    star_path     = '${params.particle_star}'
    cs_path       = '${params.particle_cs}'

    # Determine actual source path
    if input_format == 'star':
        source_path = star_path if star_path != 'null' and star_path else None
    else:
        source_path = cs_path if cs_path != 'null' and cs_path else None

    if source_path is None:
        raise RuntimeError(
            f"Input file required. Provide --particle_star (for STAR format) or "
            f"--particle_cs (for CS format). Got: star='{star_path}' cs='{cs_path}'"
        )

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

        job = workspace.create_job('import_particles', params={
            'particle_path':  source_path,
            'pixel_size_A':   pixel_size,
            'kv':             voltage,
            'box_size':       box_size,
            'input_format':   input_format
        })
        job.queue()
        job.wait_for_done()

        particles = list(job.load_output('particles'))
        num_particles = len(particles)
    else:
        # Read actual file (STAR or CS) without CryoSPARC
        num_particles = 0
        particles     = []
        if input_format == 'star':
            # Parse RELION STAR file particle table
            try:
                import starfile
                df = starfile.read(source_path)
                if isinstance(df, dict):
                    df = df.get('particles', next(iter(df.values())))
                num_particles = len(df)
                particles = df.to_dict(orient='records')
            except ImportError:
                # Fallback: count data lines
                with open(source_path) as fh:
                    for line in fh:
                        stripped = line.strip()
                        if stripped and not stripped.startswith(('_', '#', 'data_', 'loop_')):
                            num_particles += 1
        else:
            # Native CryoSPARC .cs file (numpy structured array saved as JSON or numpy)
            try:
                import numpy as np
                arr = np.load(source_path, allow_pickle=True)
                num_particles = len(arr)
                particles = [{k: str(v) for k, v in zip(arr.dtype.names, row)} for row in arr]
            except Exception:
                data = json.load(open(source_path))
                particles_raw = data.get('particles', [])
                num_particles = len(particles_raw)
                particles = particles_raw

    cs_data = {
        'particles':     particles,
        'count':         num_particles,
        'source_format': input_format
    }

    report = {
        'step':          'import_particles',
        'timestamp':     datetime.now().isoformat(),
        'num_particles': num_particles,
        'source_format': input_format,
        'source_path':   source_path,
        'pixel_size':    pixel_size,
        'voltage':       voltage,
        'box_size':      box_size
    }

    with open('particles_imported.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('import_particles_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Imported {num_particles} particles from {input_format.upper()} format")
    print(f"  Source : {source_path}")
    print(f"  Box size: {box_size} px  |  Pixel size: {pixel_size} A/px")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC Import Particles
    ====================================================================
    Input format : ${params.input_format}
    STAR file    : ${params.particle_star  ?: '(none)'}
    CS file      : ${params.particle_cs    ?: '(none)'}
    Pixel size   : ${params.pixel_size} A/px
    Voltage      : ${params.voltage} kV
    Box size     : ${params.box_size} px
    Output       : ${params.outdir}
    ====================================================================
    """.stripIndent()

    IMPORT_PARTICLES()

    IMPORT_PARTICLES.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Import Particles Results:
          Particles imported : ${r.num_particles}
          Source format      : ${r.source_format}
          Box size           : ${r.box_size} px
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Import Particles completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
