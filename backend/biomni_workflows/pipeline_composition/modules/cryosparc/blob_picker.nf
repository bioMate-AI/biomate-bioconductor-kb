nextflow.enable.dsl = 2

// BLOB_PICKER — Step 5 of CryoSPARC Standard SPA
// Round 1 picking using blob detection

def estimate_particle_diameter(mw_kda) {
    // Empirical formula: diameter (Å) ≈ 6.8 × (MW in kDa)^(1/3)
    if (mw_kda == null) return null
    return (6.8 * Math.pow(mw_kda, 1.0/3.0)).round(1)
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
        'particle_diameter_angstroms': ${diameter}
    }

    with open('particles_blob.cs', 'w') as f:
        json.dump({'particles': all_particles}, f, indent=2)

    with open('picking_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Picked {len(all_particles)} particles using blob picker")
    print(f"  Average per micrograph: {report['avg_particles_per_micrograph']}")
    """
}
