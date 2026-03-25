nextflow.enable.dsl = 2

// PATCH_MOTION_CORRECTION — Step 2 of CryoSPARC Standard SPA
// Shared with helical_spa_pipeline

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
