nextflow.enable.dsl = 2

// DRUG_DIFFERENCE_MAP — Subtract apo from drug-bound map
// Identifies ligand binding density and conformational changes
// P0-priority gap — implements CaV1.2 / D1R PAM workflow from skill docs
//
// Container: biomate/cryo-em-tools:1.0
// Reference: Yan lab Cell 2023 multi-drug atlas; Xu lab D1R PAM preprint 2025

process DRUG_DIFFERENCE_MAP {
    tag "diff_map_${drug_label}"
    publishDir "${params.outdir}/drug_analysis/difference_maps/${drug_label}", mode: 'copy'

    container 'biomate/cryo-em-tools:1.0'

    input:
    path  drug_map
    path  apo_map
    val   drug_label
    val   threshold_sigma

    output:
    path  "difference_${drug_label}.mrc",      emit: diff_map
    path  "diff_map_report_${drug_label}.json", emit: report

    script:
    def sigma = threshold_sigma ?: 3.0
    """
    python3 /opt/biomate_cryo_em/scripts/drug_difference_map.py \\
        --drug_map ${drug_map} \\
        --apo_map ${apo_map} \\
        --output difference_${drug_label}.mrc \\
        --threshold ${sigma} \\
        --report diff_map_report_${drug_label}.json
    """

    stub:
    """
    python3 -c "
import json
report = {
    'tool': 'drug_difference_map',
    'drug_label': '${drug_label}',
    'mock': True,
    'results': {
        'drug_density_detected': True,
        'positive_volume_A3': 420.0,
        'qc_status': 'pass',
        'qc_message': 'Volume 420 A3 consistent with small molecule'
    }
}
json.dump(report, open('diff_map_report_${drug_label}.json', 'w'), indent=2)
"
    # Create empty mrc placeholder
    python3 -c "
import mrcfile, numpy as np
with mrcfile.new('difference_${drug_label}.mrc', overwrite=True) as mrc:
    data = np.random.normal(0, 0.1, (64, 64, 64)).astype(np.float32)
    mrc.set_data(data)
    mrc.voxel_size = ${params.pixel_size ?: 0.83}
" 2>/dev/null || touch difference_${drug_label}.mrc
    """
}


// MULTI_DRUG_DIFFERENCE_MAPS — Run difference maps for N drugs vs one apo
// Implements the full CaV1.2-style atlas workflow

workflow MULTI_DRUG_ATLAS {
    take:
    drug_maps_ch   // channel of [drug_label, drug_map_path]
    apo_map        // single reference map

    main:
    // Combine each drug map with the apo reference
    drug_maps_ch
        .map { label, drug_map -> tuple(drug_map, apo_map, label, params.diff_map_sigma ?: 3.0) }
        | DRUG_DIFFERENCE_MAP

    emit:
    diff_maps = DRUG_DIFFERENCE_MAP.out.diff_map
    reports   = DRUG_DIFFERENCE_MAP.out.report
}
