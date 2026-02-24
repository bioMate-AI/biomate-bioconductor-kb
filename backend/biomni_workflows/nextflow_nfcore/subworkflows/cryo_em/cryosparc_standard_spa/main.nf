#!/usr/bin/env nextflow
/*
 * CryoSPARC Standard Single Particle Analysis (SPA) Workflow
 *
 * Based on emcryo RESOURCES.md 23-step standard workflow
 * https://guide.cryosparc.com/processing-data/get-started-with-cryosparc-introductory-tutorial
 *
 * Workflow Steps:
 * 1. Import Movies
 * 2. Patch Motion Correction
 * 3. Patch CTF Estimation
 * 4. Micrograph Denoiser
 * 5. Blob Particle Picker (Round 1)
 * 6. Junk 2D Detector
 * 7. Inspect Particle Picks
 * 8. Extract Particles (Round 1)
 * 9. 2D Classification (Round 1)
 * 10. Select 2D Classes (Round 1)
 * 11. Template Picker (Round 2)
 * 12. Inspect Particle Picks (Round 2)
 * 13. Extract Particles (Round 2)
 * 14. 2D Classification (Round 2)
 * 15. Select 2D Classes (Round 2)
 * 16. Ab-Initio Reconstruction
 * 17. Homogeneous Refinement
 * 18. Volume Tools (Filter/Mask)
 * 19. Validation FSC
 * 20. Local CTF Refinement
 * 21. Non-Uniform Refinement
 * 22. Local Resolution Estimation
 * 23. Post-Processing (Sharpening)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

// Input/Output
params.movies_path = null                   // Path to movie files (*.tif, *.mrc, *.eer)
params.gain_ref = null                       // Optional gain reference
params.outdir = './results/cryosparc_spa'
params.project_name = 'biomate_spa'

// Acquisition parameters
params.pixel_size = 1.05                     // Angstroms per pixel
params.voltage = 300                         // kV
params.spherical_aberration = 2.7            // mm
params.total_dose = 50.0                     // e-/A^2
params.dose_per_frame = null                 // Auto-calculated if null

// Sample parameters (for context-aware recommendations)
params.sample_type = 'unknown'               // 'membrane_protein', 'virus', 'ribosome', 'small_protein', 'unknown'
params.particle_diameter_angstroms = null    // If null, estimated from molecular weight
params.molecular_weight_kda = null           // Used to estimate diameter if not provided
params.symmetry = 'C1'                       // Point group symmetry

// Processing mode
params.mock_mode = true                      // Use mock mode for testing
params.use_cryosparc = false                 // Use live CryoSPARC API
params.cryosparc_license = null              // CryoSPARC license ID
params.cryosparc_host = 'localhost'
params.cryosparc_port = 39000
params.cryosparc_lane = 'default'

// Processing parameters (can be auto-tuned based on sample_type)
params.motion_correction_dose_weighting = true
params.ctf_fitting_resolution_min = 30.0     // Angstroms
params.ctf_fitting_resolution_max = 5.0      // Angstroms
params.particle_box_size = null              // Auto-calculated
params.num_ab_initio_classes = 3
params.max_resolution_refinement = 2.5       // Angstroms

// GPU settings
params.gpu_memory_gb = 16
params.enable_low_memory_mode = false        // Auto-enabled for <16GB GPUs

// ============================================================================
// Helper Functions
// ============================================================================

def estimate_particle_diameter(mw_kda) {
    // Empirical formula: diameter (Å) ≈ 6.8 × (MW in kDa)^(1/3)
    if (mw_kda == null) return null
    return (6.8 * Math.pow(mw_kda, 1.0/3.0)).round(1)
}

def estimate_box_size(diameter_angstroms, pixel_size) {
    // Box should be 1.5-2x particle diameter, rounded to nearest power of 2
    if (diameter_angstroms == null) return 256 // Default
    def min_box = diameter_angstroms * 1.8 / pixel_size
    def powers = [64, 96, 128, 192, 256, 320, 384, 440, 512, 640, 768, 896, 1024]
    return powers.find { it >= min_box } ?: 256
}

def get_sample_recommendations(sample_type) {
    // Context-aware parameter recommendations based on sample type
    def recommendations = [
        membrane_protein: [
            num_2d_classes: 100,
            class_similarity_threshold: 0.3,
            ab_initio_iterations: 100,
            refinement_mask_threshold: 0.5,
            notes: 'Membrane proteins have detergent micelle, need more classes'
        ],
        virus: [
            num_2d_classes: 50,
            class_similarity_threshold: 0.2,
            ab_initio_iterations: 50,
            refinement_mask_threshold: 0.4,
            notes: 'Virus particles are symmetric and homogeneous'
        ],
        ribosome: [
            num_2d_classes: 200,
            class_similarity_threshold: 0.4,
            ab_initio_iterations: 150,
            refinement_mask_threshold: 0.35,
            notes: 'Ribosomes show conformational heterogeneity'
        ],
        small_protein: [
            num_2d_classes: 100,
            class_similarity_threshold: 0.25,
            ab_initio_iterations: 100,
            refinement_mask_threshold: 0.45,
            notes: 'Small proteins may have lower SNR, need more averaging'
        ],
        unknown: [
            num_2d_classes: 100,
            class_similarity_threshold: 0.3,
            ab_initio_iterations: 100,
            refinement_mask_threshold: 0.4,
            notes: 'Default conservative settings'
        ]
    ]
    return recommendations[sample_type] ?: recommendations['unknown']
}

// ============================================================================
// Process Definitions
// ============================================================================

process IMPORT_MOVIES {
    tag "import"
    publishDir "${params.outdir}/01_import_movies", mode: 'copy'

    input:
    path movies

    output:
    path "movies.cs", emit: movies_cs
    path "import_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import os
    from pathlib import Path
    from datetime import datetime

    movies = sorted(Path('.').glob('*.tif')) + sorted(Path('.').glob('*.mrc')) + sorted(Path('.').glob('*.eer'))

    report = {
        'step': '01_import_movies',
        'timestamp': datetime.now().isoformat(),
        'num_movies': len(movies),
        'pixel_size_angstroms': ${params.pixel_size},
        'voltage_kv': ${params.voltage},
        'spherical_aberration_mm': ${params.spherical_aberration},
        'gain_reference': '${params.gain_ref}' if '${params.gain_ref}' != 'null' else None,
        'mock_mode': ${mock}
    }

    # Create CryoSPARC-style .cs file (mock format)
    cs_data = {
        'movies': [
            {
                'movie_path': str(m),
                'movie_idx': i,
                'num_frames': 40,
                'total_dose': ${params.total_dose}
            } for i, m in enumerate(movies)
        ]
    }

    with open('movies.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('import_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Imported {len(movies)} movies")
    """
}

process PATCH_MOTION_CORRECTION {
    tag "motion"
    publishDir "${params.outdir}/02_motion_correction", mode: 'copy'

    input:
    path movies_cs

    output:
    path "micrographs.cs", emit: micrographs_cs
    path "motion_report.json", emit: report
    path "motion_trajectories.json", emit: trajectories

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def dose_weight = params.motion_correction_dose_weighting ? 'True' : 'False'
    def low_mem = (params.enable_low_memory_mode || params.gpu_memory_gb < 16) ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    movies_data = json.load(open('${movies_cs}'))
    num_movies = len(movies_data.get('movies', []))

    # Simulate motion correction
    micrographs = []
    trajectories = []

    for i in range(num_movies):
        # Simulate realistic motion metrics
        total_motion = round(random.uniform(8.0, 45.0), 2)
        early_motion = round(random.uniform(5.0, 25.0), 2)
        late_motion = total_motion - early_motion

        micrographs.append({
            'micrograph_idx': i,
            'micrograph_path': f'micrograph_{i:05d}.mrc',
            'total_motion_angstroms': total_motion,
            'early_motion_angstroms': early_motion,
            'late_motion_angstroms': late_motion,
            'dose_weighted': ${dose_weight}
        })

        # Simulate frame-by-frame motion trajectory
        trajectories.append({
            'micrograph_idx': i,
            'frame_motions': [round(random.uniform(0.5, 3.0), 2) for _ in range(40)]
        })

    report = {
        'step': '02_patch_motion_correction',
        'timestamp': datetime.now().isoformat(),
        'num_micrographs': num_movies,
        'avg_total_motion_angstroms': round(sum(m['total_motion_angstroms'] for m in micrographs) / num_movies, 2),
        'dose_weighting_enabled': ${dose_weight},
        'low_memory_mode': ${low_mem},
        'mock_mode': ${mock}
    }

    with open('micrographs.cs', 'w') as f:
        json.dump({'micrographs': micrographs}, f, indent=2)

    with open('motion_trajectories.json', 'w') as f:
        json.dump({'trajectories': trajectories}, f, indent=2)

    with open('motion_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Motion corrected {num_movies} micrographs")
    print(f"  Average motion: {report['avg_total_motion_angstroms']} Å")
    """
}

process PATCH_CTF_ESTIMATION {
    tag "ctf"
    publishDir "${params.outdir}/03_ctf_estimation", mode: 'copy'

    input:
    path micrographs_cs

    output:
    path "micrographs_ctf.cs", emit: ctf_cs
    path "ctf_report.json", emit: report
    path "ctf_diagnostics.json", emit: diagnostics

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    mics_data = json.load(open('${micrographs_cs}'))
    micrographs = mics_data.get('micrographs', [])

    # Simulate CTF estimation
    ctf_data = []
    diagnostics = []

    for mic in micrographs:
        # Simulate realistic CTF parameters
        defocus_u = round(random.uniform(10000, 35000), 1)
        defocus_v = round(random.uniform(defocus_u * 0.9, defocus_u * 1.1), 1)
        astigmatism = abs(defocus_u - defocus_v)
        astigmatism_angle = round(random.uniform(0, 180), 1)
        fit_resolution = round(random.uniform(3.5, 8.0), 2)
        cross_correlation = round(random.uniform(0.05, 0.20), 4)

        ctf_data.append({
            **mic,
            'defocus_u_angstroms': defocus_u,
            'defocus_v_angstroms': defocus_v,
            'astigmatism_angstroms': astigmatism,
            'astigmatism_angle_degrees': astigmatism_angle,
            'ctf_fit_resolution_angstroms': fit_resolution,
            'ctf_cross_correlation': cross_correlation
        })

        diagnostics.append({
            'micrograph_idx': mic['micrograph_idx'],
            'ice_thickness': random.choice(['thin', 'optimal', 'thick']),
            'estimated_b_factor': round(random.uniform(-150, -50), 1)
        })

    report = {
        'step': '03_patch_ctf_estimation',
        'timestamp': datetime.now().isoformat(),
        'num_micrographs': len(micrographs),
        'avg_defocus_angstroms': round(sum(m['defocus_u_angstroms'] for m in ctf_data) / len(ctf_data), 1),
        'avg_fit_resolution_angstroms': round(sum(m['ctf_fit_resolution_angstroms'] for m in ctf_data) / len(ctf_data), 2),
        'voltage_kv': ${params.voltage},
        'spherical_aberration_mm': ${params.spherical_aberration},
        'mock_mode': ${mock}
    }

    with open('micrographs_ctf.cs', 'w') as f:
        json.dump({'micrographs': ctf_data}, f, indent=2)

    with open('ctf_diagnostics.json', 'w') as f:
        json.dump({'diagnostics': diagnostics}, f, indent=2)

    with open('ctf_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ CTF estimated for {len(micrographs)} micrographs")
    print(f"  Average defocus: {report['avg_defocus_angstroms']} Å")
    print(f"  Average fit resolution: {report['avg_fit_resolution_angstroms']} Å")
    """
}

process MICROGRAPH_DENOISER {
    tag "denoise"
    publishDir "${params.outdir}/04_denoiser", mode: 'copy'

    input:
    path ctf_cs

    output:
    path "micrographs_denoised.cs", emit: denoised_cs
    path "denoise_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    mics_data = json.load(open('${ctf_cs}'))
    micrographs = mics_data.get('micrographs', [])

    # Add denoising metadata
    denoised = [
        {**mic, 'denoised': True, 'noise_model': 'gaussian'}
        for mic in micrographs
    ]

    report = {
        'step': '04_micrograph_denoiser',
        'timestamp': datetime.now().isoformat(),
        'num_micrographs': len(micrographs),
        'denoiser_model': 'janni',
        'mock_mode': ${mock}
    }

    with open('micrographs_denoised.cs', 'w') as f:
        json.dump({'micrographs': denoised}, f, indent=2)

    with open('denoise_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Denoised {len(micrographs)} micrographs")
    """
}

process BLOB_PICKER {
    tag "pick_blob"
    publishDir "${params.outdir}/05_blob_picker", mode: 'copy'

    input:
    path denoised_cs

    output:
    path "particles_blob.cs", emit: particles_cs
    path "picking_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def diameter = params.particle_diameter_angstroms ?: estimate_particle_diameter(params.molecular_weight_kda) ?: 150
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    mics_data = json.load(open('${denoised_cs}'))
    micrographs = mics_data.get('micrographs', [])

    # Simulate blob picking
    all_particles = []
    particle_idx = 0

    for mic in micrographs:
        # Variable number of picks per micrograph
        num_picks = random.randint(80, 350)

        for _ in range(num_picks):
            all_particles.append({
                'particle_idx': particle_idx,
                'micrograph_idx': mic['micrograph_idx'],
                'x_coord': random.randint(100, 3900),
                'y_coord': random.randint(100, 3900),
                'pick_score': round(random.uniform(0.3, 1.0), 3),
                'pick_method': 'blob'
            })
            particle_idx += 1

    report = {
        'step': '05_blob_picker',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(all_particles),
        'num_micrographs': len(micrographs),
        'avg_particles_per_micrograph': round(len(all_particles) / len(micrographs), 1),
        'particle_diameter_angstroms': ${diameter},
        'mock_mode': ${mock}
    }

    with open('particles_blob.cs', 'w') as f:
        json.dump({'particles': all_particles}, f, indent=2)

    with open('picking_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Picked {len(all_particles)} particles using blob picker")
    print(f"  Average per micrograph: {report['avg_particles_per_micrograph']}")
    """
}

process JUNK_2D_DETECTOR {
    tag "junk_detect"
    publishDir "${params.outdir}/06_junk_detector", mode: 'copy'

    input:
    path particles_cs

    output:
    path "particles_filtered.cs", emit: filtered_cs
    path "junk_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    particles_data = json.load(open('${particles_cs}'))
    particles = particles_data.get('particles', [])

    # Simulate junk filtering (remove ~10-20% of particles)
    filtered = [
        {**p, 'junk_score': round(random.uniform(0.0, 0.3), 3)}
        for p in particles
        if random.random() > 0.15  # Keep 85%
    ]

    report = {
        'step': '06_junk_2d_detector',
        'timestamp': datetime.now().isoformat(),
        'num_input_particles': len(particles),
        'num_output_particles': len(filtered),
        'num_rejected': len(particles) - len(filtered),
        'rejection_rate': round((len(particles) - len(filtered)) / len(particles), 3),
        'mock_mode': ${mock}
    }

    with open('particles_filtered.cs', 'w') as f:
        json.dump({'particles': filtered}, f, indent=2)

    with open('junk_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Filtered particles: {len(particles)} → {len(filtered)} ({report['rejection_rate']*100:.1f}% rejected)")
    """
}

process INSPECT_PICKS {
    tag "inspect_r1"
    publishDir "${params.outdir}/07_inspect_picks_round1", mode: 'copy'

    input:
    path filtered_cs

    output:
    path "particles_inspected.cs", emit: inspected_cs
    path "inspect_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    # In mock mode, inspection just passes through
    # In real mode, this would create interactive visualization

    particles_data = json.load(open('${filtered_cs}'))

    report = {
        'step': '07_inspect_picks_round1',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(particles_data.get('particles', [])),
        'inspection_mode': 'auto_pass',
        'mock_mode': True
    }

    # Pass through
    with open('particles_inspected.cs', 'w') as f:
        json.dump(particles_data, f, indent=2)

    with open('inspect_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Inspection complete: {report['num_particles']} particles")
    """
}

process EXTRACT_PARTICLES_R1 {
    tag "extract_r1"
    publishDir "${params.outdir}/08_extract_round1", mode: 'copy'

    input:
    path inspected_cs

    output:
    path "particles_extracted_r1.cs", emit: extracted_cs
    path "extract_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def box_size = params.particle_box_size ?: estimate_box_size(
        params.particle_diameter_angstroms ?: estimate_particle_diameter(params.molecular_weight_kda) ?: 150,
        params.pixel_size
    )
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    particles_data = json.load(open('${inspected_cs}'))
    particles = particles_data.get('particles', [])

    # Add extraction metadata
    extracted = [
        {**p, 'box_size_pixels': ${box_size}, 'extracted': True}
        for p in particles
    ]

    report = {
        'step': '08_extract_particles_round1',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(extracted),
        'box_size_pixels': ${box_size},
        'pixel_size_angstroms': ${params.pixel_size},
        'mock_mode': ${mock}
    }

    with open('particles_extracted_r1.cs', 'w') as f:
        json.dump({'particles': extracted}, f, indent=2)

    with open('extract_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Extracted {len(extracted)} particles (box size: ${box_size} px)")
    """
}

process CLASSIFY_2D_R1 {
    tag "class2d_r1"
    publishDir "${params.outdir}/09_classify_2d_round1", mode: 'copy'

    input:
    path extracted_cs

    output:
    path "class2d_r1.cs", emit: classes_cs
    path "class2d_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def recommendations = get_sample_recommendations(params.sample_type)
    def num_classes = recommendations.num_2d_classes
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    particles_data = json.load(open('${extracted_cs}'))
    num_particles = len(particles_data.get('particles', []))

    # Simulate 2D classification
    num_classes = ${num_classes}
    classes = []

    for class_idx in range(num_classes):
        # Simulate class quality (some good, some bad)
        resolution = round(random.uniform(8.0, 25.0), 2)
        num_particles_in_class = random.randint(50, num_particles // num_classes * 2)

        # Good classes have better resolution and more particles
        is_good = resolution < 15.0 and num_particles_in_class > num_particles // num_classes * 0.8

        classes.append({
            'class_idx': class_idx,
            'num_particles': num_particles_in_class,
            'resolution_angstroms': resolution,
            'class_distribution': round(num_particles_in_class / num_particles, 4),
            'is_good_class': is_good
        })

    num_good = sum(1 for c in classes if c['is_good_class'])

    report = {
        'step': '09_classify_2d_round1',
        'timestamp': datetime.now().isoformat(),
        'num_particles': num_particles,
        'num_classes': num_classes,
        'num_good_classes': num_good,
        'avg_resolution_angstroms': round(sum(c['resolution_angstroms'] for c in classes) / num_classes, 2),
        'sample_type': '${params.sample_type}',
        'mock_mode': ${mock}
    }

    with open('class2d_r1.cs', 'w') as f:
        json.dump({'classes': classes}, f, indent=2)

    with open('class2d_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ 2D classified {num_particles} particles into {num_classes} classes")
    print(f"  Good classes: {num_good}/{num_classes}")
    """
}

process SELECT_2D_R1 {
    tag "select_r1"
    publishDir "${params.outdir}/10_select_2d_round1", mode: 'copy'

    input:
    path classes_cs
    path extracted_cs

    output:
    path "particles_selected_r1.cs", emit: selected_cs
    path "selection_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    classes_data = json.load(open('${classes_cs}'))
    particles_data = json.load(open('${extracted_cs}'))

    classes = classes_data.get('classes', [])
    all_particles = particles_data.get('particles', [])

    # Select particles from good classes
    good_class_indices = [c['class_idx'] for c in classes if c.get('is_good_class', False)]

    # Simulate selection: keep 60-80% of particles from good classes
    num_to_select = int(len(all_particles) * random.uniform(0.6, 0.8))
    selected = random.sample(all_particles, num_to_select)

    # Add class assignment
    for p in selected:
        p['assigned_class'] = random.choice(good_class_indices) if good_class_indices else 0

    report = {
        'step': '10_select_2d_round1',
        'timestamp': datetime.now().isoformat(),
        'num_input_particles': len(all_particles),
        'num_selected_particles': len(selected),
        'selection_ratio': round(len(selected) / len(all_particles), 3),
        'num_good_classes': len(good_class_indices)
    }

    with open('particles_selected_r1.cs', 'w') as f:
        json.dump({'particles': selected}, f, indent=2)

    with open('selection_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Selected {len(selected)}/{len(all_particles)} particles ({report['selection_ratio']*100:.1f}%)")
    """
}

process TEMPLATE_PICKER {
    tag "template_pick"
    publishDir "${params.outdir}/11_template_picker", mode: 'copy'

    input:
    path selected_cs
    path denoised_mics_cs

    output:
    path "particles_template.cs", emit: template_particles_cs
    path "template_pick_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    selected_data = json.load(open('${selected_cs}'))
    mics_data = json.load(open('${denoised_mics_cs}'))

    selected_particles = selected_data.get('particles', [])
    micrographs = mics_data.get('micrographs', [])

    # Template picking finds more particles using good 2D classes as templates
    # Simulate finding 2-3x more particles
    new_particles = []
    particle_idx = len(selected_particles)

    for mic in micrographs:
        num_new = random.randint(200, 500)
        for _ in range(num_new):
            new_particles.append({
                'particle_idx': particle_idx,
                'micrograph_idx': mic['micrograph_idx'],
                'x_coord': random.randint(100, 3900),
                'y_coord': random.randint(100, 3900),
                'pick_score': round(random.uniform(0.5, 1.0), 3),
                'pick_method': 'template'
            })
            particle_idx += 1

    report = {
        'step': '11_template_picker',
        'timestamp': datetime.now().isoformat(),
        'num_new_particles': len(new_particles),
        'num_micrographs': len(micrographs),
        'avg_new_particles_per_micrograph': round(len(new_particles) / len(micrographs), 1),
        'num_templates_used': len(selected_particles)
    }

    with open('particles_template.cs', 'w') as f:
        json.dump({'particles': new_particles}, f, indent=2)

    with open('template_pick_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Template picking found {len(new_particles)} new particles")
    """
}

process INSPECT_PICKS_R2 {
    tag "inspect_r2"
    publishDir "${params.outdir}/12_inspect_picks_round2", mode: 'copy'

    input:
    path template_particles_cs

    output:
    path "particles_inspected_r2.cs", emit: inspected_cs
    path "inspect_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    particles_data = json.load(open('${template_particles_cs}'))

    report = {
        'step': '12_inspect_picks_round2',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(particles_data.get('particles', [])),
        'inspection_mode': 'auto_pass'
    }

    with open('particles_inspected_r2.cs', 'w') as f:
        json.dump(particles_data, f, indent=2)

    with open('inspect_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Inspection complete: {report['num_particles']} particles")
    """
}

process EXTRACT_PARTICLES_R2 {
    tag "extract_r2"
    publishDir "${params.outdir}/13_extract_round2", mode: 'copy'

    input:
    path inspected_r2_cs

    output:
    path "particles_extracted_r2.cs", emit: extracted_cs
    path "extract_report.json", emit: report

    script:
    def box_size = params.particle_box_size ?: estimate_box_size(
        params.particle_diameter_angstroms ?: estimate_particle_diameter(params.molecular_weight_kda) ?: 150,
        params.pixel_size
    )
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    particles_data = json.load(open('${inspected_r2_cs}'))
    particles = particles_data.get('particles', [])

    extracted = [
        {**p, 'box_size_pixels': ${box_size}, 'extracted': True}
        for p in particles
    ]

    report = {
        'step': '13_extract_particles_round2',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(extracted),
        'box_size_pixels': ${box_size}
    }

    with open('particles_extracted_r2.cs', 'w') as f:
        json.dump({'particles': extracted}, f, indent=2)

    with open('extract_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Extracted {len(extracted)} particles (round 2)")
    """
}

process CLASSIFY_2D_R2 {
    tag "class2d_r2"
    publishDir "${params.outdir}/14_classify_2d_round2", mode: 'copy'

    input:
    path extracted_r2_cs

    output:
    path "class2d_r2.cs", emit: classes_cs
    path "class2d_report.json", emit: report

    script:
    def recommendations = get_sample_recommendations(params.sample_type)
    def num_classes = recommendations.num_2d_classes
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    particles_data = json.load(open('${extracted_r2_cs}'))
    num_particles = len(particles_data.get('particles', []))

    num_classes = ${num_classes}
    classes = []

    for class_idx in range(num_classes):
        resolution = round(random.uniform(6.0, 20.0), 2)
        num_in_class = random.randint(100, num_particles // num_classes * 2)
        is_good = resolution < 12.0

        classes.append({
            'class_idx': class_idx,
            'num_particles': num_in_class,
            'resolution_angstroms': resolution,
            'is_good_class': is_good
        })

    num_good = sum(1 for c in classes if c['is_good_class'])

    report = {
        'step': '14_classify_2d_round2',
        'timestamp': datetime.now().isoformat(),
        'num_particles': num_particles,
        'num_classes': num_classes,
        'num_good_classes': num_good
    }

    with open('class2d_r2.cs', 'w') as f:
        json.dump({'classes': classes}, f, indent=2)

    with open('class2d_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ 2D classified {num_particles} particles (round 2)")
    """
}

process SELECT_2D_R2 {
    tag "select_r2"
    publishDir "${params.outdir}/15_select_2d_round2", mode: 'copy'

    input:
    path classes_r2_cs
    path extracted_r2_cs

    output:
    path "particles_selected_r2.cs", emit: selected_cs
    path "selection_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    classes_data = json.load(open('${classes_r2_cs}'))
    particles_data = json.load(open('${extracted_r2_cs}'))

    all_particles = particles_data.get('particles', [])

    # Select ~70% for 3D reconstruction
    num_to_select = int(len(all_particles) * 0.7)
    selected = random.sample(all_particles, num_to_select)

    report = {
        'step': '15_select_2d_round2',
        'timestamp': datetime.now().isoformat(),
        'num_input_particles': len(all_particles),
        'num_selected_particles': len(selected),
        'selection_ratio': round(len(selected) / len(all_particles), 3)
    }

    with open('particles_selected_r2.cs', 'w') as f:
        json.dump({'particles': selected}, f, indent=2)

    with open('selection_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Selected {len(selected)} particles for 3D reconstruction")
    """
}

process AB_INITIO {
    tag "ab_initio"
    publishDir "${params.outdir}/16_ab_initio", mode: 'copy'

    input:
    path selected_r2_cs

    output:
    path "volumes_ab_initio.cs", emit: volumes_cs
    path "ab_initio_report.json", emit: report

    script:
    def num_classes = params.num_ab_initio_classes
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    particles_data = json.load(open('${selected_r2_cs}'))
    num_particles = len(particles_data.get('particles', []))

    # Simulate ab-initio reconstruction
    volumes = []
    for vol_idx in range(${num_classes}):
        resolution = round(random.uniform(10.0, 25.0), 2)
        fraction = round(random.uniform(0.2, 0.5), 3)

        volumes.append({
            'volume_idx': vol_idx,
            'resolution_angstroms': resolution,
            'num_particles': int(num_particles * fraction),
            'particle_fraction': fraction
        })

    # Best volume is the one with most particles
    best_vol = max(volumes, key=lambda v: v['num_particles'])

    report = {
        'step': '16_ab_initio',
        'timestamp': datetime.now().isoformat(),
        'num_particles': num_particles,
        'num_classes': ${num_classes},
        'symmetry': '${params.symmetry}',
        'best_volume_idx': best_vol['volume_idx'],
        'best_resolution_angstroms': best_vol['resolution_angstroms']
    }

    with open('volumes_ab_initio.cs', 'w') as f:
        json.dump({'volumes': volumes, 'best_volume': best_vol}, f, indent=2)

    with open('ab_initio_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Ab-initio reconstruction: {${num_classes}} classes")
    print(f"  Best volume: {best_vol['resolution_angstroms']} Å resolution")
    """
}

process HOMOGENEOUS_REFINEMENT {
    tag "homo_refine"
    publishDir "${params.outdir}/17_homogeneous_refinement", mode: 'copy'

    input:
    path volumes_cs
    path particles_cs

    output:
    path "refined_volume.cs", emit: refined_cs
    path "refinement_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    volumes_data = json.load(open('${volumes_cs}'))
    particles_data = json.load(open('${particles_cs}'))

    best_volume = volumes_data.get('best_volume', volumes_data['volumes'][0])
    num_particles = len(particles_data.get('particles', []))

    # Simulate refinement improving resolution
    initial_res = best_volume['resolution_angstroms']
    final_res = round(initial_res * random.uniform(0.4, 0.7), 2)  # Improve by 30-60%

    refined = {
        'volume_idx': 0,
        'resolution_angstroms': final_res,
        'num_particles': num_particles,
        'fsc_0143_resolution': round(final_res * 1.05, 2)
    }

    report = {
        'step': '17_homogeneous_refinement',
        'timestamp': datetime.now().isoformat(),
        'num_particles': num_particles,
        'initial_resolution_angstroms': initial_res,
        'final_resolution_angstroms': final_res,
        'resolution_improvement': round((initial_res - final_res) / initial_res * 100, 1),
        'symmetry': '${params.symmetry}'
    }

    with open('refined_volume.cs', 'w') as f:
        json.dump({'volume': refined}, f, indent=2)

    with open('refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Homogeneous refinement: {initial_res} Å → {final_res} Å")
    """
}

process VOLUME_TOOLS {
    tag "vol_tools"
    publishDir "${params.outdir}/18_volume_tools", mode: 'copy'

    input:
    path refined_cs

    output:
    path "volume_processed.cs", emit: processed_cs
    path "volume_tools_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    refined_data = json.load(open('${refined_cs}'))
    volume = refined_data.get('volume', {})

    # Simulate filtering and masking
    processed = {
        **volume,
        'filtered': True,
        'masked': True,
        'lowpass_resolution': volume['resolution_angstroms']
    }

    report = {
        'step': '18_volume_tools',
        'timestamp': datetime.now().isoformat(),
        'operations': ['lowpass_filter', 'auto_mask'],
        'resolution_angstroms': volume['resolution_angstroms']
    }

    with open('volume_processed.cs', 'w') as f:
        json.dump({'volume': processed}, f, indent=2)

    with open('volume_tools_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Volume filtering and masking complete")
    """
}

process VALIDATION_FSC {
    tag "val_fsc"
    publishDir "${params.outdir}/19_validation_fsc", mode: 'copy'

    input:
    path processed_cs

    output:
    path "fsc_validation.json", emit: fsc
    path "validation_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    processed_data = json.load(open('${processed_cs}'))
    volume = processed_data.get('volume', {})
    resolution = volume['resolution_angstroms']

    # Simulate FSC curve
    fsc_curve = []
    for freq in [0.001, 0.01, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5]:
        shell_res = 1.0 / freq if freq > 0 else 999
        if shell_res > resolution * 2:
            fsc = 0.99
        elif shell_res > resolution:
            fsc = 0.5 + (shell_res - resolution) / resolution * 0.4
        else:
            fsc = 0.143 + (resolution - shell_res) / resolution * 0.3

        fsc_curve.append({
            'spatial_frequency': freq,
            'resolution_angstroms': round(shell_res, 2),
            'fsc': round(max(0, min(1, fsc)), 4)
        })

    report = {
        'step': '19_validation_fsc',
        'timestamp': datetime.now().isoformat(),
        'fsc_0143_resolution': resolution,
        'fsc_05_resolution': round(resolution * 1.2, 2)
    }

    with open('fsc_validation.json', 'w') as f:
        json.dump({'fsc_curve': fsc_curve}, f, indent=2)

    with open('validation_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ FSC validation complete: {resolution} Å at 0.143 cutoff")
    """
}

process LOCAL_CTF_REFINEMENT {
    tag "ctf_refine"
    publishDir "${params.outdir}/20_local_ctf_refinement", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "particles_ctf_refined.cs", emit: refined_particles_cs
    path "ctf_refinement_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    particles_data = json.load(open('${particles_cs}'))
    particles = particles_data.get('particles', [])

    # Simulate per-particle CTF refinement
    refined_particles = [
        {**p, 'ctf_refined': True, 'local_defocus_shift': round(random.uniform(-500, 500), 1)}
        for p in particles
    ]

    report = {
        'step': '20_local_ctf_refinement',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(particles),
        'avg_defocus_shift_angstroms': round(sum(abs(p['local_defocus_shift']) for p in refined_particles) / len(particles), 1)
    }

    with open('particles_ctf_refined.cs', 'w') as f:
        json.dump({'particles': refined_particles}, f, indent=2)

    with open('ctf_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Local CTF refinement complete")
    """
}

process NON_UNIFORM_REFINEMENT {
    tag "nu_refine"
    publishDir "${params.outdir}/21_non_uniform_refinement", mode: 'copy'

    input:
    path refined_particles_cs
    path volume_cs

    output:
    path "volume_nu_refined.mrc", emit: final_volume
    path "nu_refinement_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    import struct
    from datetime import datetime

    particles_data = json.load(open('${refined_particles_cs}'))
    volume_data = json.load(open('${volume_cs}'))

    num_particles = len(particles_data.get('particles', []))
    current_res = volume_data.get('volume', {}).get('resolution_angstroms', 5.0)

    # Non-uniform refinement typically improves by 10-20%
    final_res = round(current_res * random.uniform(0.8, 0.9), 2)

    # Create mock MRC file
    size = 128
    with open('volume_nu_refined.mrc', 'wb') as f:
        header = struct.pack('3i', size, size, size)
        header += struct.pack('3i', 2, 0, 0)
        header += struct.pack('3i', size, size, size)
        header += struct.pack('3f', float(size * ${params.pixel_size}),
                                    float(size * ${params.pixel_size}),
                                    float(size * ${params.pixel_size}))
        header += struct.pack('3f', 90.0, 90.0, 90.0)
        header += struct.pack('3i', 1, 2, 3)
        header += struct.pack('3f', -1.0, 1.0, 0.0)
        header += b'\\x00' * (1024 - len(header))
        f.write(header)

        for i in range(size * size * size):
            f.write(struct.pack('f', random.gauss(0, 0.1)))

    report = {
        'step': '21_non_uniform_refinement',
        'timestamp': datetime.now().isoformat(),
        'num_particles': num_particles,
        'initial_resolution_angstroms': current_res,
        'final_resolution_angstroms': final_res,
        'resolution_improvement': round((current_res - final_res) / current_res * 100, 1)
    }

    with open('nu_refinement_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Non-uniform refinement: {current_res} Å → {final_res} Å")
    """
}

process LOCAL_RESOLUTION {
    tag "local_res"
    publishDir "${params.outdir}/22_local_resolution", mode: 'copy'
    errorStrategy 'ignore'

    input:
    path final_volume

    output:
    path "local_resolution.mrc", emit: local_res_map
    path "local_resolution_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import random
    import shutil
    from datetime import datetime

    # Copy volume as local resolution map (in mock mode)
    shutil.copy('${final_volume}', 'local_resolution.mrc')

    # Simulate local resolution statistics
    resolutions = [round(random.gauss(4.5, 1.5), 2) for _ in range(100)]

    report = {
        'step': '22_local_resolution',
        'timestamp': datetime.now().isoformat(),
        'mean_resolution_angstroms': round(sum(resolutions) / len(resolutions), 2),
        'min_resolution_angstroms': round(min(resolutions), 2),
        'max_resolution_angstroms': round(max(resolutions), 2),
        'std_resolution_angstroms': round((sum((r - sum(resolutions)/len(resolutions))**2 for r in resolutions) / len(resolutions))**0.5, 2)
    }

    with open('local_resolution_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Local resolution: {report['mean_resolution_angstroms']} Å (mean)")
    """
}

process SHARPEN {
    tag "sharpen"
    publishDir "${params.outdir}/23_sharpening", mode: 'copy'

    input:
    path final_volume

    output:
    path "volume_sharpened.mrc", emit: sharpened_volume
    path "sharpening_report.json", emit: report
    path "workflow_summary.json", emit: summary

    script:
    """
    #!/usr/bin/env python3
    import json
    import shutil
    from datetime import datetime

    # Copy volume as sharpened (in mock mode)
    shutil.copy('${final_volume}', 'volume_sharpened.mrc')

    # Simulate sharpening
    b_factor = round(-120.0 + (4.5 - 3.5) * 30, 1)  # B-factor depends on resolution

    report = {
        'step': '23_sharpening',
        'timestamp': datetime.now().isoformat(),
        'b_factor_applied': b_factor,
        'lowpass_filter': '${params.max_resolution_refinement}',
        'final_output': 'volume_sharpened.mrc'
    }

    # Create workflow summary
    summary = {
        'workflow': 'cryosparc_standard_spa',
        'version': '1.0',
        'completion_time': datetime.now().isoformat(),
        'sample_type': '${params.sample_type}',
        'pixel_size_angstroms': ${params.pixel_size},
        'voltage_kv': ${params.voltage},
        'symmetry': '${params.symmetry}',
        'mock_mode': ${params.mock_mode ? 'True' : 'False'},
        'outputs': {
            'final_map': 'volume_sharpened.mrc',
            'local_resolution_map': 'local_resolution.mrc',
            'fsc_validation': 'fsc_validation.json'
        },
        'steps_completed': 23
    }

    with open('sharpening_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    with open('workflow_summary.json', 'w') as f:
        json.dump(summary, f, indent=2)

    print(f"✓ Sharpening complete (B-factor: {b_factor})")
    print(f"")
    print(f"=" * 70)
    print(f"  CryoSPARC Standard SPA Workflow Complete!")
    print(f"=" * 70)
    """
}

// ============================================================================
// Main Workflow
// ============================================================================

workflow CRYOSPARC_STANDARD_SPA {
    take:
    movies_path

    main:
    // Step 1: Import Movies
    IMPORT_MOVIES(movies_path)

    // Step 2: Motion Correction
    PATCH_MOTION_CORRECTION(IMPORT_MOVIES.out.movies_cs)

    // Step 3: CTF Estimation
    PATCH_CTF_ESTIMATION(PATCH_MOTION_CORRECTION.out.micrographs_cs)

    // Step 4: Denoise Micrographs
    MICROGRAPH_DENOISER(PATCH_CTF_ESTIMATION.out.ctf_cs)

    // Step 5: Blob Picker (Round 1)
    BLOB_PICKER(MICROGRAPH_DENOISER.out.denoised_cs)

    // Step 6: Junk 2D Detector
    JUNK_2D_DETECTOR(BLOB_PICKER.out.particles_cs)

    // Step 7: Inspect Picks (Round 1)
    INSPECT_PICKS(JUNK_2D_DETECTOR.out.filtered_cs)

    // Step 8: Extract Particles (Round 1)
    EXTRACT_PARTICLES_R1(INSPECT_PICKS.out.inspected_cs)

    // Step 9: 2D Classification (Round 1)
    CLASSIFY_2D_R1(EXTRACT_PARTICLES_R1.out.extracted_cs)

    // Step 10: Select 2D Classes (Round 1)
    SELECT_2D_R1(CLASSIFY_2D_R1.out.classes_cs, EXTRACT_PARTICLES_R1.out.extracted_cs)

    // Step 11: Template Picker (Round 2)
    TEMPLATE_PICKER(SELECT_2D_R1.out.selected_cs, MICROGRAPH_DENOISER.out.denoised_cs)

    // Step 12: Inspect Picks (Round 2)
    INSPECT_PICKS_R2(TEMPLATE_PICKER.out.template_particles_cs)

    // Step 13: Extract Particles (Round 2)
    EXTRACT_PARTICLES_R2(INSPECT_PICKS_R2.out.inspected_cs)

    // Step 14: 2D Classification (Round 2)
    CLASSIFY_2D_R2(EXTRACT_PARTICLES_R2.out.extracted_cs)

    // Step 15: Select 2D Classes (Round 2)
    SELECT_2D_R2(CLASSIFY_2D_R2.out.classes_cs, EXTRACT_PARTICLES_R2.out.extracted_cs)

    // Step 16: Ab-Initio Reconstruction
    AB_INITIO(SELECT_2D_R2.out.selected_cs)

    // Step 17: Homogeneous Refinement
    HOMOGENEOUS_REFINEMENT(AB_INITIO.out.volumes_cs, SELECT_2D_R2.out.selected_cs)

    // Step 18: Volume Tools
    VOLUME_TOOLS(HOMOGENEOUS_REFINEMENT.out.refined_cs)

    // Step 19: Validation FSC
    VALIDATION_FSC(VOLUME_TOOLS.out.processed_cs)

    // Step 20: Local CTF Refinement
    LOCAL_CTF_REFINEMENT(SELECT_2D_R2.out.selected_cs, VOLUME_TOOLS.out.processed_cs)

    // Step 21: Non-Uniform Refinement
    NON_UNIFORM_REFINEMENT(LOCAL_CTF_REFINEMENT.out.refined_particles_cs, VOLUME_TOOLS.out.processed_cs)

    // Step 22: Local Resolution
    LOCAL_RESOLUTION(NON_UNIFORM_REFINEMENT.out.final_volume)

    // Step 23: Sharpening
    SHARPEN(NON_UNIFORM_REFINEMENT.out.final_volume)

    emit:
    final_map = SHARPEN.out.sharpened_volume
    local_res_map = LOCAL_RESOLUTION.out.local_res_map
    fsc = VALIDATION_FSC.out.fsc
    summary = SHARPEN.out.summary
}

// ============================================================================
// Standalone Execution
// ============================================================================

workflow {
    // Auto-calculate derived parameters
    if (params.particle_diameter_angstroms == null && params.molecular_weight_kda != null) {
        params.particle_diameter_angstroms = estimate_particle_diameter(params.molecular_weight_kda)
        log.info "Estimated particle diameter: ${params.particle_diameter_angstroms} Å"
    }

    if (params.particle_box_size == null) {
        params.particle_box_size = estimate_box_size(
            params.particle_diameter_angstroms ?: 150,
            params.pixel_size
        )
        log.info "Calculated box size: ${params.particle_box_size} px"
    }

    if (params.gpu_memory_gb < 16 && !params.enable_low_memory_mode) {
        params.enable_low_memory_mode = true
        log.warn "GPU memory < 16GB detected. Enabling low memory mode."
    }

    // Print workflow configuration
    def recommendations = get_sample_recommendations(params.sample_type)
    log.info """
    ====================================================================
    CryoSPARC Standard SPA Workflow
    ====================================================================
    Sample Type: ${params.sample_type}
    ${recommendations.notes}

    Acquisition:
      - Pixel size: ${params.pixel_size} Å/px
      - Voltage: ${params.voltage} kV
      - Spherical aberration: ${params.spherical_aberration} mm
      - Total dose: ${params.total_dose} e-/Å²

    Particle:
      - Diameter: ${params.particle_diameter_angstroms ?: 'auto'} Å
      - Box size: ${params.particle_box_size} px
      - Symmetry: ${params.symmetry}

    Processing:
      - 2D classes: ${recommendations.num_2d_classes}
      - Ab-initio classes: ${params.num_ab_initio_classes}
      - Low memory mode: ${params.enable_low_memory_mode}

    Mode: ${params.mock_mode ? 'MOCK (testing)' : 'LIVE (CryoSPARC)'}
    ====================================================================
    """.stripIndent()

    // Create input channel
    ch_movies = Channel.fromPath(params.movies_path ?: "${baseDir}/test_data/*.tif")
        .ifEmpty {
            // Create dummy movie files for testing
            def dummy_dir = file("${params.outdir}/test_movies")
            dummy_dir.mkdirs()
            (1..20).collect { i ->
                def f = file("${dummy_dir}/movie_${String.format('%05d', i)}.tif")
                f.text = "dummy movie ${i}"
                f
            }
        }
        .collect()

    // Run workflow
    CRYOSPARC_STANDARD_SPA(ch_movies)

    // Print results
    CRYOSPARC_STANDARD_SPA.out.summary.view { summary_file ->
        def summary = new groovy.json.JsonSlurper().parse(summary_file)
        """

        Workflow Summary:
        - Steps completed: ${summary.steps_completed}/23
        - Final map: ${summary.outputs.final_map}
        - Local resolution map: ${summary.outputs.local_resolution_map}
        - FSC validation: ${summary.outputs.fsc_validation}

        Results directory: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info """
    ====================================================================
    Workflow completed: ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Duration: ${workflow.duration}
    ====================================================================
    """.stripIndent()
}
