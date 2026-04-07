nextflow.enable.dsl = 2

// INSPECT_PICKS — Steps 7 and 12 of CryoSPARC Standard SPA
// Contains both round 1 (INSPECT_PICKS) and round 2 (INSPECT_PICKS_R2) inspection processes
// These are nearly identical processes for round 1 and round 2 inspection

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

    particles_data = json.load(open('${filtered_cs}'))

    report = {
        'step': '07_inspect_picks_round1',
        'timestamp': datetime.now().isoformat(),
        'num_particles': len(particles_data.get('particles', [])),
        'inspection_mode': 'auto_pass'
    }

    # Pass through
    with open('particles_inspected.cs', 'w') as f:
        json.dump(particles_data, f, indent=2)

    with open('inspect_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"✓ Inspection complete: {report['num_particles']} particles")
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
