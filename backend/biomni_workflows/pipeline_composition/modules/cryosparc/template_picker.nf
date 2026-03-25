nextflow.enable.dsl = 2

// TEMPLATE_PICKER — Step 11 of CryoSPARC Standard SPA
// Uses good 2D class averages from Round 1 as templates to pick
// a much larger, higher-confidence particle set across all micrographs.

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
