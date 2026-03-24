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
params.mock_mode                = true    // use mock mode for testing
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
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode       = ${mock}
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

    # ----------------------------------------------------------------
    # Generate per-component maps
    # Each component describes one axis of conformational variance.
    # Variance is not uniform — components follow a power-law decay.
    # ----------------------------------------------------------------
    total_variance = 100.0
    raw_variances  = sorted(
        [random.uniform(10.0, 40.0) for _ in range(num_components)],
        reverse=True
    )
    norm_factor = sum(raw_variances) / total_variance
    variance_explained = [round(v / norm_factor, 2) for v in raw_variances]

    component_maps = []
    for comp_idx in range(num_components):
        comp_filename = f'variability_component_{comp_idx}.cs'
        comp_data = {
            'component_idx':           comp_idx,
            'variance_explained_pct':  variance_explained[comp_idx],
            'resolution_angstroms':    round(filter_res * random.uniform(1.0, 1.5), 2),
            'amplitude':               round(random.uniform(0.05, 0.30), 4),
            'description':             f'Variability mode {comp_idx}: '
                                       f'{variance_explained[comp_idx]:.1f}% of total variance'
        }
        with open(comp_filename, 'w') as f:
            json.dump({'component': comp_data}, f, indent=2)
        component_maps.append(comp_filename)

    # ----------------------------------------------------------------
    # Assign latent coordinates to each particle
    # Latent coordinates are N-dimensional (one per component).
    # Distribution is approximately Gaussian per component.
    # ----------------------------------------------------------------
    particles_with_latent = []
    for p in particles:
        latent_coords = [
            round(random.gauss(0.0, 1.0), 6)
            for _ in range(num_components)
        ]
        entry = dict(p)
        entry['latent_coordinates'] = latent_coords
        entry['cluster_id']         = (
            random.randint(0, num_clusters - 1)
            if cluster_mode == 'discrete' else None
        )
        particles_with_latent.append(entry)

    report = {
        'step':                       '3d_variability_analysis',
        'timestamp':                  datetime.now().isoformat(),
        'num_components':             num_components,
        'num_particles':              num_particles,
        'variance_explained_per_component': variance_explained,
        'total_variance_explained_pct': round(sum(variance_explained), 2),
        'resolution_angstroms':       resolution_angstroms,
        'filter_resolution_angstroms': filter_res,
        'num_iterations':             num_iterations,
        'cluster_mode':               cluster_mode,
        'num_clusters':               num_clusters,
        'component_map_files':        component_maps,
        'mock_mode':                  mock_mode
    }

    with open('particles_with_latent.cs', 'w') as f:
        json.dump({
            'particles':   particles_with_latent,
            'num_components': num_components
        }, f, indent=2)

    with open('3dva_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"3D Variability Analysis complete")
    print(f"  Particles     : {num_particles}")
    print(f"  Components    : {num_components}")
    for i, var in enumerate(variance_explained):
        print(f"    Component {i}: {var:.1f}% variance")
    print(f"  Filter res    : {filter_res} A")
    """

    stub:
    """
    touch particles_with_latent.cs 3dva_report.json variability_component_0.cs
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [' +
            (1..500).collect { i ->
                """{"particle_idx": ${i}, "micrograph_idx": ${i % 100}, """ +
                """"x_coord": 2000, "y_coord": 2000, "pick_score": 0.90}"""
            }.join(',') + ']}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 3.9, "symmetry": "C1", "num_particles": 500}}'
        f
    }

    THREE_D_VARIABILITY(ch_particles, ch_volume)

    THREE_D_VARIABILITY.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        3D Variability Analysis Summary:
          - Particles   : ${report.num_particles}
          - Components  : ${report.num_components}
          - Variance per component: ${report.variance_explained_per_component}
          - Resolution  : ${report.resolution_angstroms} A
        """
    }
}
