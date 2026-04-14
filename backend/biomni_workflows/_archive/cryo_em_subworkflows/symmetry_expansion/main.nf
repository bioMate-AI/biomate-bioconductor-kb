#!/usr/bin/env nextflow
/*
 * CryoSPARC Symmetry Expansion
 *
 * Expands a particle set by the symmetry operators of the assembly.  Each
 * particle generates N copies, one per symmetry operator, each rotated into
 * the asymmetric unit.  The output contains expansion_factor × input_count
 * particles, all oriented as if from a C1 assembly.
 *
 * This is the prerequisite for focused classification / local refinement of
 * individual asymmetric subunits starting from a symmetrized reconstruction.
 *
 * Standard CryoSPARC job type: "sym_expand"
 *
 * Expansion factors by symmetry group:
 *   Cn  → n operators
 *   Dn  → 2n operators
 *   T   → 12 operators
 *   O   → 24 operators
 *   I   → 60 operators
 *
 * References:
 *   Ilca et al. 2015 Nat Commun 6:8843 (original strategy)
 *   Punjani et al. 2017 Nat Methods 14:290 (CryoSPARC)
 *
 * Domain: Cryo-EM / CryoSPARC
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.symmetry         = 'C4'   // input assembly symmetry (C1-C12, D2-D8, T, O, I)
params.expand_symmetry  = true   // set false to skip expansion (pass-through)
params.mock_mode        = true   // use mock mode for testing
params.use_cryosparc    = false  // use live CryoSPARC API
params.outdir           = './results/symmetry_expansion'

// ============================================================================
// Helper — number of symmetry operators per group
// ============================================================================

def get_num_operators(symmetry_str) {
    def sym = symmetry_str.toUpperCase().trim()
    if (sym == 'C1')                 return 1
    if (sym == 'T')                  return 12
    if (sym == 'O')                  return 24
    if (sym == 'I')                  return 60
    def cn_match = sym =~ /^C(\d+)$/
    if (cn_match) return cn_match[0][1].toInteger()
    def dn_match = sym =~ /^D(\d+)$/
    if (dn_match) return dn_match[0][1].toInteger() * 2
    return 1  // unknown symmetry — no expansion
}

// ============================================================================
// Process Definition
// ============================================================================

process SYMMETRY_EXPANSION {
    tag "symmetry_expansion"
    publishDir "${params.outdir}/symmetry_expansion", mode: 'copy'

    input:
    path particles_cs
    path volume_cs

    output:
    path "symmetry_expanded_particles.cs",  emit: expanded_particles_cs
    path "symmetry_expansion_report.json",  emit: report

    script:
    def mock            = params.mock_mode        ? 'True' : 'False'
    def do_expand       = params.expand_symmetry  ? 'True' : 'False'
    def num_operators   = get_num_operators(params.symmetry)
    """
    #!/usr/bin/env python3
    import json
    import random
    import math
    from datetime import datetime

    random.seed(None)

    mock_mode      = ${mock}
    do_expand      = ${do_expand}
    symmetry       = '${params.symmetry}'
    num_operators  = ${num_operators}

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles          = particles_data.get('particles', [])
    original_count     = len(particles)
    volume             = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.0)

    if not do_expand or num_operators <= 1:
        # Pass-through: just annotate particles, no duplication
        expanded = []
        for p in particles:
            entry = dict(p)
            entry['symmetry_operator_idx'] = 0
            entry['expansion_copy']        = False
            expanded.append(entry)
        expansion_factor = 1
    else:
        # For each particle, generate one copy per symmetry operator.
        # Each copy is rotated by the corresponding symmetry operator
        # such that the asymmetric unit is standardized.
        expanded = []
        new_idx  = 0

        # Pre-generate rotation angles for each operator
        # (uniformly spaced around the symmetry axis in mock mode)
        operator_angles = []
        sym_upper = symmetry.upper()
        if sym_upper.startswith('C') and sym_upper[1:].isdigit():
            n = int(sym_upper[1:])
            operator_angles = [(360.0 / n) * i for i in range(n)]
        elif sym_upper.startswith('D') and sym_upper[1:].isdigit():
            n = int(sym_upper[1:])
            c_angles = [(360.0 / n) * i for i in range(n)]
            d_angles = [a + 180.0 for a in c_angles]
            operator_angles = c_angles + d_angles
        elif sym_upper == 'T':
            operator_angles = [i * (360.0 / 12) for i in range(12)]
        elif sym_upper == 'O':
            operator_angles = [i * (360.0 / 24) for i in range(24)]
        elif sym_upper == 'I':
            operator_angles = [i * (360.0 / 60) for i in range(60)]
        else:
            operator_angles = [0.0]  # fallback C1

        for p in particles:
            for op_idx, rotation_angle in enumerate(operator_angles):
                entry = dict(p)
                entry['particle_idx']          = new_idx
                entry['original_particle_idx'] = p.get('particle_idx', new_idx)
                entry['symmetry_operator_idx'] = op_idx
                entry['sym_rotation_angle_deg'] = round(rotation_angle, 3)
                # Perturb coordinates slightly to simulate sub-pixel repositioning
                entry['x_coord'] = p.get('x_coord', 2000) + round(random.gauss(0, 2), 1)
                entry['y_coord'] = p.get('y_coord', 2000) + round(random.gauss(0, 2), 1)
                entry['expansion_copy'] = (op_idx > 0)
                expanded.append(entry)
                new_idx += 1

        expansion_factor = num_operators

    expanded_count = len(expanded)

    cs_data = {
        'particles':              expanded,
        'symmetry_operators_used': num_operators,
        'original_count':         original_count,
        'expanded_count':         expanded_count
    }

    report = {
        'step':                   'symmetry_expansion',
        'timestamp':              datetime.now().isoformat(),
        'input_symmetry':         symmetry,
        'num_symmetry_operators': num_operators,
        'original_particle_count': original_count,
        'expanded_particle_count': expanded_count,
        'expansion_factor':       expansion_factor,
        'expand_symmetry':        do_expand,
        'resolution_angstroms':   resolution_angstroms,
        'mock_mode':              mock_mode
    }

    with open('symmetry_expanded_particles.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('symmetry_expansion_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Symmetry expansion complete")
    print(f"  Symmetry         : {symmetry}  ({num_operators} operators)")
    print(f"  Original count   : {original_count}")
    print(f"  Expanded count   : {expanded_count}")
    print(f"  Expansion factor : {expansion_factor}x")
    """

    stub:
    """
    touch symmetry_expanded_particles.cs symmetry_expansion_report.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    def num_ops = get_num_operators(params.symmetry)
    log.info """
    ====================================================================
    CryoSPARC Symmetry Expansion
    ====================================================================
    Input symmetry       : ${params.symmetry}
    Symmetry operators   : ${num_ops}
    Expansion factor     : ${num_ops}x
    Expand symmetry      : ${params.expand_symmetry}
    Mode                 : ${params.mock_mode ? 'MOCK (testing)' : 'LIVE (CryoSPARC)'}
    ====================================================================
    """.stripIndent()

    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/particles.cs")
        f.parent.mkdirs()
        f.text = '{"particles": [' +
            (1..300).collect { i ->
                """{"particle_idx": ${i}, "micrograph_idx": ${i % 60}, """ +
                """"x_coord": ${(int)(Math.random() * 3800) + 100}, """ +
                """"y_coord": ${(int)(Math.random() * 3800) + 100}, """ +
                """"pick_score": 0.92, "pick_method": "template"}"""
            }.join(',') + ']}'
        f
    }

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: false
    ).ifEmpty {
        def f = file("${params.outdir}/test_inputs/volume.cs")
        f.parent.mkdirs()
        f.text = '{"volume": {"resolution_angstroms": 3.2, "symmetry": "' + params.symmetry + '", "num_particles": 300}}'
        f
    }

    SYMMETRY_EXPANSION(ch_particles, ch_volume)

    SYMMETRY_EXPANSION.out.report.view { report_file ->
        def report = new groovy.json.JsonSlurper().parse(report_file)
        """
        Symmetry Expansion Summary:
          - Symmetry           : ${report.input_symmetry}
          - Operators          : ${report.num_symmetry_operators}
          - Original particles : ${report.original_particle_count}
          - Expanded particles : ${report.expanded_particle_count}
          - Expansion factor   : ${report.expansion_factor}x
        """
    }
}
