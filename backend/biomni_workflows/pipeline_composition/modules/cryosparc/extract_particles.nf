nextflow.enable.dsl = 2

// EXTRACT_PARTICLES — Steps 8 and 13 of CryoSPARC Standard SPA
// Contains both EXTRACT_PARTICLES_R1 (round 1) and EXTRACT_PARTICLES_R2 (round 2)

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
