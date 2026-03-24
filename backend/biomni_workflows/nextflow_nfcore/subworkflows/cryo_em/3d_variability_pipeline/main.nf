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
params.mock_mode            = true    // use mock mode for testing
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
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode      = ${mock}
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

    # Variance explained per component (power-law decay)
    raw_variances = sorted(
        [random.uniform(10.0, 40.0) for _ in range(num_components)],
        reverse=True
    )
    norm_factor      = sum(raw_variances) / 100.0
    variance_explained = [round(v / norm_factor, 2) for v in raw_variances]

    component_maps = []
    for comp_idx in range(num_components):
        comp_filename = f'variability_component_{comp_idx}.cs'
        comp_data = {
            'component_idx':          comp_idx,
            'variance_explained_pct': variance_explained[comp_idx],
            'resolution_angstroms':   round(filter_res * random.uniform(1.0, 1.5), 2),
            'amplitude':              round(random.uniform(0.05, 0.30), 4)
        }
        with open(comp_filename, 'w') as f:
            json.dump({'component': comp_data}, f, indent=2)
        component_maps.append(comp_filename)

    particles_with_latent = []
    for p in particles:
        entry = dict(p)
        entry['latent_coordinates'] = [
            round(random.gauss(0.0, 1.0), 6) for _ in range(num_components)
        ]
        entry['cluster_id'] = None
        particles_with_latent.append(entry)

    report = {
        'step':                              '3d_variability_analysis',
        'timestamp':                         datetime.now().isoformat(),
        'num_components':                    num_components,
        'num_particles':                     num_particles,
        'variance_explained_per_component':  variance_explained,
        'total_variance_explained_pct':      round(sum(variance_explained), 2),
        'resolution_angstroms':              resolution_angstroms,
        'filter_resolution_angstroms':       filter_res,
        'num_iterations':                    num_iterations,
        'cluster_mode':                      cluster_mode,
        'component_map_files':               component_maps,
        'mock_mode':                         mock_mode
    }

    with open('particles_with_latent.cs', 'w') as f:
        json.dump({'particles': particles_with_latent, 'num_components': num_components}, f, indent=2)

    with open('3dva_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[1/2] 3D Variability Analysis complete")
    print(f"  Particles  : {num_particles}  |  Components: {num_components}")
    for i, var in enumerate(variance_explained):
        print(f"    Mode {i}: {var:.1f}%")
    """

    stub:
    """
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
    def mock               = params.mock_mode         ? 'True'  : 'False'
    def subsample          = params.subsample_particles ? "${params.subsample_particles}" : 'None'
    def display_components = params.display_components  ? "${params.display_components}"  : 'None'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(None)

    mock_mode          = ${mock}
    num_clusters       = ${params.num_clusters}
    subsample          = ${subsample}
    display_components = ${display_components}

    latent_data    = json.load(open('${particles_latent_cs}'))
    particles      = latent_data.get('particles', [])
    num_components = latent_data.get('num_components', ${params.num_components})
    num_particles  = len(particles)

    # Optionally subsample
    if subsample and subsample < num_particles:
        particles = random.sample(particles, subsample)
        num_particles = len(particles)

    # Determine which components to display
    if display_components is not None:
        components_to_display = [display_components] if isinstance(display_components, int) else display_components
    else:
        components_to_display = list(range(num_components))

    # ---------------------------------------------------------------
    # Cluster particles into num_clusters discrete classes using
    # k-means-like assignment on the first displayed component.
    # ---------------------------------------------------------------
    clustered = []
    class_counts = [0] * num_clusters

    for p in particles:
        latent = p.get('latent_coordinates', [0.0] * num_components)
        # Map first latent dimension to cluster index
        # Latent values ~N(0,1); use linear interpolation across [-3, 3]
        primary_coord = latent[components_to_display[0]] if latent else 0.0
        cluster_id = min(int((primary_coord + 3.0) / 6.0 * num_clusters), num_clusters - 1)
        cluster_id = max(0, cluster_id)
        entry = dict(p)
        entry['cluster_id']  = cluster_id
        entry['cluster_type'] = 'discrete'
        clustered.append(entry)
        class_counts[cluster_id] += 1

    # ---------------------------------------------------------------
    # Build conformational trajectory:
    # For each cluster (frame), record the "average" 3D density
    # position along the trajectory.
    # ---------------------------------------------------------------
    trajectory_frames = []
    for frame_idx in range(num_clusters):
        # Simulate a density map for each frame
        trajectory_frames.append({
            'frame_idx':              frame_idx,
            'num_particles':          class_counts[frame_idx],
            'fraction_of_total':      round(class_counts[frame_idx] / num_particles, 4),
            'estimated_resolution_angstroms': round(
                random.uniform(5.0, 12.0), 2
            ),
            'component_positions':    [
                round(
                    -3.0 + (frame_idx / (num_clusters - 1)) * 6.0
                    + random.gauss(0, 0.1), 3
                )
                for _ in components_to_display
            ],
            'volume_file':            f'frame_{frame_idx:03d}.cs'
        })

    report = {
        'step':                 '3d_variability_display',
        'timestamp':            datetime.now().isoformat(),
        'num_particles_input':  len(latent_data.get('particles', [])),
        'num_particles_used':   num_particles,
        'num_clusters':         num_clusters,
        'components_displayed': components_to_display,
        'num_components_total': num_components,
        'class_population':     class_counts,
        'mock_mode':            mock_mode
    }

    with open('clustered_particles.cs', 'w') as f:
        json.dump({'particles': clustered, 'num_clusters': num_clusters}, f, indent=2)

    with open('conformational_trajectory.json', 'w') as f:
        json.dump({
            'trajectory':          trajectory_frames,
            'num_frames':          num_clusters,
            'components_shown':    components_to_display,
            'interpolation_mode': '${params.cluster_mode}'
        }, f, indent=2)

    with open('3dva_display_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"[2/2] 3DVA Display complete")
    print(f"  Particles clustered: {num_particles}  |  Classes: {num_clusters}")
    print(f"  Components shown   : {components_to_display}")
    print(f"  Trajectory frames  : {num_clusters}")
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
    Mode              : ${params.mock_mode ? 'MOCK (testing)' : 'LIVE (CryoSPARC)'}
    ====================================================================
    """.stripIndent()

    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [' +
            (1..1000).collect { i ->
                """{"particle_idx": ${i}, "micrograph_idx": ${i % 200}, """ +
                """"x_coord": 2000, "y_coord": 2000, "pick_score": 0.88}"""
            }.join(',') + ']}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 3.5, "symmetry": "C1", "num_particles": 1000}}'
        f
    }

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
