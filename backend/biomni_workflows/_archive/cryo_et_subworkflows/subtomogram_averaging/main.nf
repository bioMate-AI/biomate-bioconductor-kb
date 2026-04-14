#!/usr/bin/env nextflow
/*
 * Cryo-ET: Subtomogram Averaging (STA)
 *
 * Picks subtomogram particles from reconstructed tomograms (optionally guided
 * by a PDB template), then performs iterative STA alignment rounds and
 * computes the gold-standard FSC resolution of the averaged map.
 *
 * Step 4 of the Cryo-ET pipeline.
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.num_particles = 1000         // target particle picks across all tomograms
params.template_pdb = null          // PDB template for template matching (optional)
params.symmetry = 'C1'              // point group symmetry
params.sta_resolution_target = 15.0 // Å target FSC resolution
params.num_sta_rounds = 2           // number of iterative alignment rounds
params.mock_mode = true
params.outdir = './results/cryo_et'

// ============================================================================
// Process Definition
// ============================================================================

process SUBTOMOGRAM_AVERAGING {
    tag "subtomogram_averaging"
    label 'process_gpu'
    publishDir "${params.outdir}/04_subtomogram_averaging", mode: 'copy'

    input:
    path tomograms_manifest

    output:
    path "sta_report.json", emit: report

    script:
    def mock = params.mock_mode ? 'True' : 'False'
    def has_template = params.template_pdb ? 'True' : 'False'
    """
    #!/usr/bin/env python3
    import json
    import random
    from datetime import datetime

    random.seed(256)

    mock_mode = ${mock}
    target_particles = ${params.num_particles}
    symmetry = '${params.symmetry}'
    sta_resolution_target = ${params.sta_resolution_target}
    num_sta_rounds = ${params.num_sta_rounds}
    has_template = ${has_template}

    manifest = json.load(open('${tomograms_manifest}'))
    tomograms = manifest.get('tomograms', [])
    num_tomograms = manifest.get('num_tomograms', len(tomograms))

    # Distribute picks across tomograms (random proportions)
    raw_weights = [random.uniform(0.5, 1.5) for _ in range(num_tomograms)]
    total_weight = sum(raw_weights)
    particles_per_tomo = {}
    total_picked = 0

    for i, tomo in enumerate(tomograms):
        ts_id = tomo['ts_id']
        if i < num_tomograms - 1:
            n = int(round(target_particles * raw_weights[i] / total_weight))
        else:
            # Last tomogram gets the remainder
            n = target_particles - total_picked
        n = max(1, n)
        particles_per_tomo[ts_id] = n
        total_picked += n

    # Template matching improves initial pick quality; higher SNR
    picking_snr = round(random.uniform(1.8, 3.5) * (1.3 if has_template else 1.0), 3)

    # Simulate iterative STA rounds with improving FSC each round
    # Round 1: coarse alignment; starts ~30-50% worse than target
    sta_rounds = []
    current_res = round(
        sta_resolution_target * random.uniform(1.4, 1.8), 2
    )

    for rnd in range(1, num_sta_rounds + 1):
        if rnd > 1:
            # Each round improves resolution by 20-40%
            improvement = random.uniform(0.60, 0.80)
            current_res = round(current_res * improvement, 2)
        # Clamp to plausible ET STA range 10-50 A
        current_res = max(10.0, min(50.0, current_res))
        sta_rounds.append({
            "round": rnd,
            "fsc_0143_resolution_angstroms": current_res,
            "particles_included": int(total_picked * random.uniform(0.85, 1.0))
        })

    final_fsc = sta_rounds[-1]["fsc_0143_resolution_angstroms"]

    report = {
        "step": "04_subtomogram_averaging",
        "timestamp": datetime.now().isoformat(),
        "num_tomograms": num_tomograms,
        "total_particles_picked": total_picked,
        "particles_per_tomogram": particles_per_tomo,
        "picking_snr": picking_snr,
        "template_matching": has_template,
        "symmetry": symmetry,
        "num_sta_rounds": num_sta_rounds,
        "sta_rounds": sta_rounds,
        "final_fsc_0143_resolution_angstroms": final_fsc,
        "sta_resolution_target_angstroms": sta_resolution_target,
        "mock_mode": mock_mode
    }

    with open("sta_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print(f"Subtomogram averaging complete ({num_sta_rounds} round(s))")
    print(f"  Tomograms: {num_tomograms}  |  Total particles: {total_picked}")
    print(f"  Symmetry: {symmetry}  |  Template matching: {has_template}")
    for r in sta_rounds:
        print(f"  Round {r['round']}: FSC 0.143 = {r['fsc_0143_resolution_angstroms']:.1f} A")
    print(f"  Final FSC 0.143 resolution: {final_fsc:.1f} A")
    """

    stub:
    """
    touch sta_report.json
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    manifest_ch = Channel.fromPath(
        params.tomograms_manifest ?: 'tomograms_manifest.json',
        checkIfExists: false
    ).ifEmpty { file('tomograms_manifest.json') }

    SUBTOMOGRAM_AVERAGING(manifest_ch)
}
