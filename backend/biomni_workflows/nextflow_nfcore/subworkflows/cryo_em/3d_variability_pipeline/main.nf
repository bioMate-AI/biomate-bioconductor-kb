#!/usr/bin/env nextflow
/*
 * CryoSPARC 3D Variability Pipeline
 *
 * Full two-step pipeline for exploring conformational heterogeneity:
 *   1. THREE_D_VARIABILITY       — PCA of density space; assigns latent coords
 *   2. THREE_D_VARIABILITY_DISPLAY — clusters particles, generates conformational
 *                                    trajectory frames (20 discrete classes by default)
 *
 * The display step is the standard follow-up to 3DVA in CryoSPARC to produce
 * a "movie" of the conformational trajectory along each variability mode.
 *
 * References:
 *   Punjani & Fleet 2021 Nat Methods 18:860
 *   Punjani et al. 2021 bioRxiv (3DVA display)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters — merged from both steps
// ============================================================================

// --- 3D Variability ---
params.num_components       = 3       // number of variability modes
params.filter_res_angstroms = 6.0     // lowpass filter resolution (Angstroms)
params.num_iterations       = 5       // optimization iterations
params.cluster_mode         = 'linear' // 'linear' or 'discrete'

// --- 3D Variability Display ---
params.num_clusters         = 20      // discrete classes for trajectory
params.display_components   = null    // which components to display; null = all
params.subsample_particles  = null    // subsample N particles for faster display

// --- Global ---
params.use_cryosparc        = false   // use live CryoSPARC API
params.outdir               = './results/3d_variability_pipeline'

// ============================================================================
// Process Definitions (inline)
// ============================================================================

process THREE_D_VARIABILITY {
    tag "3d_variability"
    label 'process_gpu'
    publishDir "${params.outdir}/01_3dva", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "particles_with_latent.cs",    emit: particles_latent_cs
    path "3dva_report.json",            emit: report
    path "variability_component_*.cs",  emit: component_maps

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    num_components = ${params.num_components}
    filter_res     = ${params.filter_res_angstroms}
    num_iterations = ${params.num_iterations}
    cluster_mode   = '${params.cluster_mode}'
    num_clusters   = ${params.num_clusters}

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles            = particles_data.get('particles', [])
    num_particles        = len(particles)
    volume               = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.5)

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

        job = workspace.create_job('var_3D', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params={
            'var_num_svd_comp':   num_components,
            'var_filter_res':     filter_res,
            'var_num_iterations': num_iterations,
            'var_cluster_mode':   cluster_mode,
            'var_num_classes':    num_clusters
        })
        job.queue()
        job.wait_for_done()

        component_maps = []
        for comp_idx in range(num_components):
            comp_filename = f'variability_component_{comp_idx}.cs'
            with open(comp_filename, 'w') as f:
                json.dump({'component': {'component_idx': comp_idx}}, f, indent=2)
            component_maps.append(comp_filename)

        particles_out = list(job.load_output('particles'))
        with open('particles_with_latent.cs', 'w') as f:
            json.dump({'particles': particles_out, 'num_components': num_components}, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    report = {
        'step':                              '3d_variability_analysis',
        'timestamp':                         datetime.now().isoformat(),
        'num_components':                    num_components,
        'num_particles':                     num_particles,
        'resolution_angstroms':              resolution_angstroms,
        'filter_resolution_angstroms':       filter_res,
        'num_iterations':                    num_iterations,
        'cluster_mode':                      cluster_mode,
        'component_map_files':               component_maps
    }

    with open('3dva_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[1/2] 3D Variability Analysis complete")
    print(f"  Particles  : {num_particles}  |  Components: {num_components}")
    '''

    stub:
    '''
    touch particles_with_latent.cs 3dva_report.json variability_component_0.cs
    """
}

process THREE_D_VARIABILITY_DISPLAY {
    tag "3dva_display"
    label 'process_gpu'
    publishDir "${params.outdir}/02_3dva_display", mode: 'copy'

    input:
    path particles_latent_cs
    path component_maps

    output:
    path "clustered_particles.cs",       emit: clustered_particles_cs
    path "conformational_trajectory.json", emit: trajectory
    path "3dva_display_report.json",     emit: report

    script:
    def subsample          = params.subsample_particles ? "${params.subsample_particles}" : 'None'
    def display_components = params.display_components  ? "${params.display_components}"  : 'None'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    num_clusters       = ${params.num_clusters}
    subsample          = ${subsample}
    display_components = ${display_components}

    latent_data    = json.load(open('${particles_latent_cs}'))
    particles      = latent_data.get('particles', [])
    num_components = latent_data.get('num_components', ${params.num_components})
    num_particles  = len(particles)

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

        job_params = {
            'num_clusters': num_clusters
        }
        if subsample is not None:
            job_params['subsample_particles'] = subsample
        if display_components is not None:
            job_params['display_components'] = display_components

        job = workspace.create_job('var_3D_disp', connections={
            'particles': ('${params.cryosparc_dva_job_uid ?: ""}', 'particles'),
            'variability_components': ('${params.cryosparc_dva_job_uid ?: ""}', 'variability_components')
        }, params=job_params)
        job.queue()
        job.wait_for_done()

        clustered_out = list(job.load_output('particles'))
        with open('clustered_particles.cs', 'w') as f:
            json.dump({'particles': clustered_out, 'num_clusters': num_clusters}, f, indent=2)

        trajectory_frames = []
        with open('conformational_trajectory.json', 'w') as f:
            json.dump({
                'trajectory': trajectory_frames,
                'num_frames': num_clusters,
                'components_shown': list(range(num_components)) if display_components is None else [display_components],
                'interpolation_mode': '${params.cluster_mode}'
            }, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    report = {
        'step':                 '3d_variability_display',
        'timestamp':            datetime.now().isoformat(),
        'num_particles_input':  len(latent_data.get('particles', [])),
        'num_particles_used':   num_particles,
        'num_clusters':         num_clusters,
        'num_components_total': num_components
    }

    with open('3dva_display_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[2/2] 3DVA Display complete")
    print(f"  Particles clustered: {num_particles}  |  Classes: {num_clusters}")
    """

    stub:
    """
    touch clustered_particles.cs conformational_trajectory.json 3dva_display_report.json
    """
}

// ============================================================================
// Named Workflow
// ============================================================================

workflow THREE_D_VARIABILITY_PIPELINE {
    take:
    particles_cs
    volume_cs

    main:
    // Step 1: 3D Variability Analysis
    THREE_D_VARIABILITY(particles_cs, volume_cs)

    // Step 2: Display — cluster into discrete conformational classes
    THREE_D_VARIABILITY_DISPLAY(
        THREE_D_VARIABILITY.out.particles_latent_cs,
        THREE_D_VARIABILITY.out.component_maps.collect()
    )

    emit:
    clustered_particles_cs = THREE_D_VARIABILITY_DISPLAY.out.clustered_particles_cs
    trajectory             = THREE_D_VARIABILITY_DISPLAY.out.trajectory
    dva_report             = THREE_D_VARIABILITY.out.report
    display_report         = THREE_D_VARIABILITY_DISPLAY.out.report
}

// ============================================================================
// Standalone Execution
// ============================================================================

workflow {
    log.info """
    ====================================================================
    CryoSPARC 3D Variability Pipeline
    ====================================================================
    Components        : ${params.num_components}
    Filter resolution : ${params.filter_res_angstroms} A
    Num clusters      : ${params.num_clusters}
    Cluster mode      : ${params.cluster_mode}
    ====================================================================
    """.stripIndent()

    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: true
    )

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: true
    )

    THREE_D_VARIABILITY_PIPELINE(ch_particles, ch_volume)

    THREE_D_VARIABILITY_PIPELINE.out.trajectory.view { traj_file ->
        def traj = new groovy.json.JsonSlurper().parse(traj_file)
        """
        3DVA Pipeline Summary:
          - Trajectory frames   : ${traj.num_frames}
          - Components shown    : ${traj.components_shown}
          - Interpolation mode  : ${traj.interpolation_mode}
        """
    }
}
