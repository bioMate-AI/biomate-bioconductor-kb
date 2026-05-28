#!/usr/bin/env nextflow
/*
 * CryoSPARC 3D Variability Analysis (3DVA)
 *
 * Performs principal component analysis of conformational heterogeneity across
 * all particle images.  Each particle receives latent space coordinates (one
 * per variability mode), and the workflow outputs per-mode component maps that
 * describe the directions of maximum variance in 3D density space.
 *
 * Standard CryoSPARC job type: "var_3D"
 *
 * References:
 *   Punjani & Fleet 2021 Nat Methods 18:860
 *   Punjani et al. 2021 bioRxiv (3DVA display)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.num_components           = 3       // number of variability modes (eigenvectors)
params.filter_res_angstroms     = 6.0     // lowpass filter resolution (Angstroms)
params.num_iterations           = 5       // number of optimization iterations
params.cluster_mode             = 'linear' // 'linear' or 'discrete'
params.num_clusters             = 20      // number of clusters for discrete mode
params.use_cryosparc            = false   // use live CryoSPARC API
params.outdir                   = './results/3d_variability_analysis'

// ============================================================================
// Process Definition
// ============================================================================

process THREE_D_VARIABILITY {
    tag "3d_variability"
    label 'process_gpu'
    publishDir "${params.outdir}/3d_variability_analysis", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "particles_with_latent.cs",  emit: particles_latent_cs
    path "3dva_report.json",          emit: report
    path "variability_component_*.cs", emit: component_maps

    script:
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    from datetime import datetime

    num_components  = ${params.num_components}
    filter_res      = ${params.filter_res_angstroms}
    num_iterations  = ${params.num_iterations}
    cluster_mode    = '${params.cluster_mode}'
    num_clusters    = ${params.num_clusters}

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles      = particles_data.get('particles', [])
    num_particles  = len(particles)
    volume         = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.5)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        # Submit 3D Variability Analysis job via cryosparc-tools
        from cryosparc.tools import CryoSPARC
        cs = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project = cs.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('var_3D', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params={
            'var_num_svd_comp':  num_components,
            'var_filter_res':    filter_res,
            'var_num_iterations': num_iterations,
            'var_cluster_mode':  cluster_mode,
            'var_num_classes':   num_clusters
        })
        job.queue()
        job.wait_for_done()

        outputs = job.doc['output_result_groups']
        particles_output = job.load_output('particles')
        component_maps_output = job.load_output('variability_components')

        component_maps = []
        for comp_idx in range(num_components):
            comp_filename = f'variability_component_{comp_idx}.cs'
            comp_data = component_maps_output[comp_idx] if comp_idx < len(component_maps_output) else {}
            with open(comp_filename, 'w') as f:
                json.dump({'component': comp_data}, f, indent=2)
            component_maps.append(comp_filename)

        particles_out = list(particles_output)
        variance_explained = [0.0] * num_components

        with open('particles_with_latent.cs', 'w') as f:
            json.dump({'particles': particles_out, 'num_components': num_components}, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "--cryosparc_host, --cryosparc_port, --cryosparc_email, --cryosparc_password, "
            "--cryosparc_project_uid, --cryosparc_workspace_uid, "
            "--cryosparc_particles_job_uid, --cryosparc_volume_job_uid"
        )

    report = {
        'step':                       '3d_variability_analysis',
        'timestamp':                  datetime.now().isoformat(),
        'num_components':             num_components,
        'num_particles':              num_particles,
        'resolution_angstroms':       resolution_angstroms,
        'filter_resolution_angstroms': filter_res,
        'num_iterations':             num_iterations,
        'cluster_mode':               cluster_mode,
        'num_clusters':               num_clusters,
        'component_map_files':        component_maps
    }

    with open('3dva_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"3D Variability Analysis complete")
    print(f"  Particles     : {num_particles}")
    print(f"  Components    : {num_components}")
    print(f"  Filter res    : {filter_res} A")
    '''

    stub:
    '''
    touch particles_with_latent.cs 3dva_report.json variability_component_0.cs
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: true
    )

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: true
    )

    THREE_D_VARIABILITY(ch_particles, ch_volume)

    THREE_D_VARIABILITY.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        3D Variability Analysis Summary:
          - Particles   : ${report.num_particles}
          - Components  : ${report.num_components}
          - Resolution  : ${report.resolution_angstroms} A
        """
    }
}
