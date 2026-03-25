nextflow.enable.dsl = 2

// AB_INITIO: Ab-initio 3D reconstruction producing initial volume classes
// from selected particles. Number of classes controlled by params.num_ab_initio_classes.

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
