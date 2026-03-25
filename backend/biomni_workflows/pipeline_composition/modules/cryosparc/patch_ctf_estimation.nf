nextflow.enable.dsl = 2

// PATCH_CTF_ESTIMATION — Step 3 of CryoSPARC Standard SPA
// Shared with helical_spa_pipeline

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
    def use_phase_plate = params.phase_plate ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    mics_data = json.load(open('${micrographs_cs}'))
    micrographs = mics_data.get('micrographs', [])
    use_phase_plate = ${use_phase_plate}

    # Simulate CTF estimation
    ctf_data = []
    diagnostics = []
    phase_shifts = []

    for mic in micrographs:
        # VPP data: lower defocus (1000-5000 Å) and near-focus collection
        if use_phase_plate:
            defocus_u = round(random.uniform(1000, 5000), 1)
        else:
            defocus_u = round(random.uniform(10000, 35000), 1)
        defocus_v = round(random.uniform(defocus_u * 0.9, defocus_u * 1.1), 1)
        astigmatism = abs(defocus_u - defocus_v)
        astigmatism_angle = round(random.uniform(0, 180), 1)
        fit_resolution = round(random.uniform(3.5, 8.0), 2)
        cross_correlation = round(random.uniform(0.05, 0.20), 4)

        entry = {
            **mic,
            'defocus_u_angstroms': defocus_u,
            'defocus_v_angstroms': defocus_v,
            'astigmatism_angstroms': astigmatism,
            'astigmatism_angle_degrees': astigmatism_angle,
            'ctf_fit_resolution_angstroms': fit_resolution,
            'ctf_cross_correlation': cross_correlation,
        }

        # Volta Phase Plate: simulate phase shift accumulation per micrograph
        # Optimal VPP phase shift: 0.4-0.8π rad (≈ 1.26-2.51 rad);
        # practical productive range: 0.2-1.5 rad
        if use_phase_plate:
            phase_shift = round(random.gauss(0.75, 0.2), 4)  # centred on productive range
            entry['phase_shift_rad'] = phase_shift
            phase_shifts.append(phase_shift)

        ctf_data.append(entry)

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
        'phase_plate': use_phase_plate,
        'mock_mode': ${mock}
    }

    # Include phase plate aggregate when VPP data
    if use_phase_plate and phase_shifts:
        report['avg_phase_shift_rad'] = round(sum(phase_shifts) / len(phase_shifts), 4)
        report['min_phase_shift_rad'] = round(min(phase_shifts), 4)
        report['max_phase_shift_rad'] = round(max(phase_shifts), 4)

    with open('micrographs_ctf.cs', 'w') as f:
        json.dump({'micrographs': ctf_data}, f, indent=2)

    with open('ctf_diagnostics.json', 'w') as f:
        json.dump({'diagnostics': diagnostics}, f, indent=2)

    with open('ctf_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ CTF estimated for {len(micrographs)} micrographs")
    if use_phase_plate and phase_shifts:
        print(f"  Volta Phase Plate: avg phase shift = {report['avg_phase_shift_rad']:.3f} rad")
    print(f"  Average defocus: {report['avg_defocus_angstroms']} Å")
    print(f"  Average fit resolution: {report['avg_fit_resolution_angstroms']} Å")
    """
}
