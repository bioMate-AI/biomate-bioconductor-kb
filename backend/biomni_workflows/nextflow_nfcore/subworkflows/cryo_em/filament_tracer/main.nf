#!/usr/bin/env nextflow
/*
 * CryoSPARC Filament Tracer
 *
 * Picks filamentous particles (microtubules, actin filaments, amyloid fibers,
 * intermediate filaments) by tracing filament axes across micrographs and
 * generating particle picks along each filament with a configurable helical
 * rise and box overlap.  Corresponds to the CryoSPARC "filament_tracer" job
 * type.
 *
 * Typical sample parameters:
 *   Microtubule  : diameter ~250 Å, rise ~8.2 Å (tubulin dimer ~82 Å / 10)
 *   F-actin      : diameter  ~70 Å, rise ~27.5 Å
 *   Amyloid      : diameter  ~50-100 Å, rise ~4.75 Å
 *   Intermediate : diameter ~100 Å, rise ~2.25 Å
 *
 * References:
 *   Bharat et al. 2015 Structure 23:1743  (helical cryo-EM workflow)
 *   Fromm et al. 2021 eLife 10:e68028    (filament tracing strategy)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.filament_diameter_angstroms    = 150   // Å; e.g. microtubule ~250, actin ~70, amyloid ~100
params.helical_rise_angstroms         = 4.75  // Å; inter-subunit rise along helical axis
params.overlap_fraction               = 0.9   // fraction of box overlapping between adjacent picks
params.min_filament_length_angstroms  = 500   // minimum traceable filament length (Å)
params.use_cryosparc                  = false // use live CryoSPARC API
params.outdir                         = './results/filament_tracer'

// ============================================================================
// Process Definition
// ============================================================================

process FILAMENT_TRACER {
    tag "filament_tracer"
    publishDir "${params.outdir}/filament_tracer", mode: 'copy'

    input:
    path micrographs_ctf_cs

    output:
    path "filament_picks.cs",            emit: filament_picks_cs
    path "filament_tracer_report.json",  emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    mics_data   = json.load(open('${micrographs_ctf_cs}'))
    micrographs = mics_data.get('micrographs', [])
    num_mics    = len(micrographs)

    filament_diameter   = ${params.filament_diameter_angstroms}
    helical_rise        = ${params.helical_rise_angstroms}
    overlap_fraction    = ${params.overlap_fraction}
    min_length          = ${params.min_filament_length_angstroms}

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('filament_tracer', connections={
            'micrographs': ('${params.cryosparc_ctf_job_uid ?: ""}', 'micrographs')
        }, params={
            'fil_diameter':        filament_diameter,
            'fil_rise_A':          helical_rise,
            'fil_overlap_fraction': overlap_fraction,
            'fil_min_length_A':    min_length
        })
        job.queue()
        job.wait_for_done()

        picks_out = list(job.load_output('particles'))
        total_filaments = job.doc.get('output_stats', {}).get('num_filaments', len(picks_out))
        total_picks     = len(picks_out)

        cs_data = {
            'picks':           picks_out,
            'num_filaments':   total_filaments,
            'num_picks':       total_picks,
            'num_micrographs': num_mics
        }
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    with open('filament_picks.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    report = {
        'step':                         'filament_tracer',
        'timestamp':                    datetime.now().isoformat(),
        'num_micrographs':              num_mics,
        'total_filaments_traced':       cs_data['num_filaments'],
        'total_particles_picked':       cs_data['num_picks'],
        'filament_diameter_angstroms':  filament_diameter,
        'helical_rise_angstroms':       helical_rise,
        'overlap_fraction':             overlap_fraction,
        'min_filament_length_angstroms': min_length
    }

    with open('filament_tracer_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Filament tracing complete on {num_mics} micrographs")
    print(f"  Total filaments traced  : {cs_data['num_filaments']}")
    print(f"  Total particles picked  : {cs_data['num_picks']}")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC Filament Tracer
    ====================================================================
    Filament diameter  : ${params.filament_diameter_angstroms} Å
    Helical rise       : ${params.helical_rise_angstroms} Å
    Overlap fraction   : ${params.overlap_fraction}
    Min filament length: ${params.min_filament_length_angstroms} Å
    Output             : ${params.outdir}
    ====================================================================
    """.stripIndent()

    ch_ctf = Channel.fromPath(
        params.micrographs_ctf_cs ?: 'micrographs_ctf.cs',
        checkIfExists: true
    )

    FILAMENT_TRACER(ch_ctf)

    FILAMENT_TRACER.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Filament Tracer Results:
          Micrographs : ${r.num_micrographs}
          Filaments   : ${r.total_filaments_traced}
          Picks       : ${r.total_particles_picked}
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Filament Tracer completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
