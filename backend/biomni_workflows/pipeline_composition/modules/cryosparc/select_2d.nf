nextflow.enable.dsl = 2

// SELECT_2D — Steps 10 and 15 of CryoSPARC Standard SPA
// Contains both SELECT_2D_R1 (round 1) and SELECT_2D_R2 (round 2)

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
