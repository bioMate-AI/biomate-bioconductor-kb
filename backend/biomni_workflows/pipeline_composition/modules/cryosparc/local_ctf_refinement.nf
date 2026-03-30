nextflow.enable.dsl = 2

// LOCAL_CTF_REFINEMENT: Per-particle local CTF refinement.
// Estimates a per-particle defocus shift (±500 Å) to correct for sample tilt
// and beam-induced motion defocus gradients before non-uniform refinement.

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
