#!/usr/bin/env nextflow
/*
 * CryoSPARC Symmetry Expansion
 *
 * Expands a particle set by the symmetry operators of the assembly.  Each
 * particle generates N copies, one per symmetry operator, each rotated into
 * the asymmetric unit.  The output contains expansion_factor x input_count
 * particles, all oriented as if from a C1 assembly.
 *
 * This is the prerequisite for focused classification / local refinement of
 * individual asymmetric subunits starting from a symmetrized reconstruction.
 *
 * Standard CryoSPARC job type: "sym_expand"
 *
 * Expansion factors by symmetry group:
 *   Cn  -> n operators
 *   Dn  -> 2n operators
 *   T   -> 12 operators
 *   O   -> 24 operators
 *   I   -> 60 operators
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
params.use_cryosparc    = false  // use live CryoSPARC API
params.outdir           = './results/symmetry_expansion'

// ============================================================================
// Helper -- number of symmetry operators per group
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
    return 1  // unknown symmetry -- no expansion
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
    def do_expand       = params.expand_symmetry  ? 'True' : 'False'
    def num_operators   = get_num_operators(params.symmetry)
    """
    #!/usr/bin/env python3
    import json
    from datetime import datetime

    do_expand     = ${do_expand}
    symmetry      = '${params.symmetry}'
    num_operators = ${num_operators}

    particles_data = json.load(open('${particles_cs}'))
    volume_data    = json.load(open('${volume_cs}'))

    particles          = particles_data.get('particles', [])
    original_count     = len(particles)
    volume             = volume_data.get('volume', {})
    resolution_angstroms = volume.get('resolution_angstroms', 4.0)

    use_cryosparc = ${params.use_cryosparc ? 'True' : 'False'}

    if use_cryosparc:
        from cryosparc.tools import CryoSPARC
        cs = CryoSPARC(
            host='${params.cryosparc_host ?: "localhost"}',
            port=${params.cryosparc_port ?: 39000},
            email='${params.cryosparc_email ?: ""}',
            password='${params.cryosparc_password ?: ""}'
        )
        project   = cs.find_project('${params.cryosparc_project_uid ?: ""}')
        workspace = project.find_workspace('${params.cryosparc_workspace_uid ?: ""}')

        job = workspace.create_job('sym_expand', connections={
            'particles': ('${params.cryosparc_particles_job_uid ?: ""}', 'particles'),
            'volume':    ('${params.cryosparc_volume_job_uid ?: ""}', 'volume')
        }, params={
            'symmetry':   symmetry,
            'do_expand':  do_expand
        })
        job.queue()
        job.wait_for_done()

        expanded_out   = list(job.load_output('particles'))
        expanded_count = len(expanded_out)
        expansion_factor = expanded_count // original_count if original_count > 0 else 1

        cs_data = {
            'particles':              expanded_out,
            'symmetry_operators_used': num_operators,
            'original_count':         original_count,
            'expanded_count':         expanded_count
        }
        with open('symmetry_expanded_particles.cs', 'w') as f:
            json.dump(cs_data, f, indent=2)
    else:
        raise RuntimeError(
            "CryoSPARC connection required. Set --use_cryosparc true and provide "
            "CryoSPARC connection params."
        )

    report = {
        'step':                   'symmetry_expansion',
        'timestamp':              datetime.now().isoformat(),
        'input_symmetry':         symmetry,
        'num_symmetry_operators': num_operators,
        'original_particle_count': original_count,
        'expanded_particle_count': expanded_count,
        'expansion_factor':       expansion_factor,
        'expand_symmetry':        do_expand,
        'resolution_angstroms':   resolution_angstroms
    }

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
    ====================================================================
    """.stripIndent()

    ch_particles = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: true
    )

    ch_volume = Channel.fromPath(
        params.volume_cs ?: 'volume.cs',
        checkIfExists: true
    )

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
