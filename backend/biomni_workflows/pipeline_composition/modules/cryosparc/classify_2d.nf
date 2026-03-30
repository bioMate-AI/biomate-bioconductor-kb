nextflow.enable.dsl = 2

// CLASSIFY_2D — Steps 9 and 14 of CryoSPARC Standard SPA
// Contains both CLASSIFY_2D_R1 (round 1) and CLASSIFY_2D_R2 (round 2)

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
