#!/usr/bin/env nextflow
/*
 * Topaz Extract -- Apply Trained Neural Network Picker to Full Dataset
 *
 * Applies a pre-trained Topaz model to the complete micrograph set for
 * highly sensitive particle detection.  The log-likelihood threshold controls
 * the sensitivity / precision trade-off: lower values are more permissive and
 * recover more particles (useful for small or heterogeneous assemblies); higher
 * values reduce false positives.
 *
 * References:
 *   Bepler et al. 2019 Nat Methods 16:1153  (Topaz particle detection)
 *
 * Domain: Cryo-EM / Topaz
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.topaz_threshold                    = -6.0   // log-likelihood threshold; lower = more sensitive
params.expected_particles_per_micrograph  = 300    // used for output statistics
params.use_cryosparc                      = false
params.outdir                             = './results/topaz_extract'

// ============================================================================
// Process Definition
// ============================================================================

process TOPAZ_EXTRACT {
    tag "topaz_extract"
    label 'process_gpu'
    publishDir "${params.outdir}/topaz_extract", mode: 'copy'

    input:
    path micrographs_cs
    path topaz_model

    output:
    path "topaz_picks.cs",           emit: topaz_picks_cs
    path "topaz_extract_report.json", emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    import os
    from pathlib import Path
    from datetime import datetime

    threshold = ${params.topaz_threshold}
    exp_ppm   = ${params.expected_particles_per_micrograph}

    mics_data  = json.load(open('${micrographs_cs}'))
    model_meta = json.load(open('${topaz_model}'))

    micrographs = mics_data.get('micrographs', [])
    num_mics    = len(micrographs)
    model_path  = model_meta.get('model_path', '${topaz_model}')
    architecture = model_meta.get('architecture', 'resnet16')

    # Write micrograph list file for topaz
    mic_list = Path('micrographs_for_extract.txt')
    with open(mic_list, 'w') as fh:
        for mic in micrographs:
            fh.write(mic.get('filename', mic.get('micrograph_path', '')) + '\\n')

    # Run topaz extract
    cmd = [
        'topaz', 'extract',
        '--model', model_path,
        '--threshold', str(threshold),
        '--output', 'topaz_picks_raw.tsv',
        '--num-workers', str(os.cpu_count() or 4)
    ]
    # Append micrograph paths
    for mic in micrographs:
        mic_path = mic.get('filename', mic.get('micrograph_path', ''))
        if mic_path:
            cmd.append(mic_path)

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"topaz extract stderr: {result.stderr}", file=sys.stderr)
        raise RuntimeError(f"topaz extract failed with exit code {result.returncode}")

    # Parse topaz TSV output: image_name, x_coord, y_coord, score
    all_picks   = []
    total_picks = 0
    mic_name_to_idx = {
        Path(mic.get('filename', mic.get('micrograph_path', ''))).stem: mic.get('micrograph_idx', i)
        for i, mic in enumerate(micrographs)
    }

    if Path('topaz_picks_raw.tsv').exists():
        with open('topaz_picks_raw.tsv') as fh:
            header = fh.readline()  # skip header
            for line in fh:
                parts = line.strip().split('\\t')
                if len(parts) >= 4:
                    img_name, x, y, score = parts[0], parts[1], parts[2], parts[3]
                    mic_idx = mic_name_to_idx.get(Path(img_name).stem, 0)
                    all_picks.append({
                        'micrograph_idx':   mic_idx,
                        'x':                float(x),
                        'y':                float(y),
                        'score':            float(score),
                        'passed_threshold': float(score) >= threshold
                    })
                    total_picks += 1

    passing_picks = [p for p in all_picks if p['passed_threshold']]
    avg_picks_per_mic = round(len(passing_picks) / num_mics, 1) if num_mics > 0 else 0.0

    cs_data = {
        'picks':           all_picks,
        'num_picks':       len(passing_picks),
        'num_micrographs': num_mics
    }

    report = {
        'step':                    'topaz_extract',
        'timestamp':               datetime.now().isoformat(),
        'num_micrographs':         num_mics,
        'total_picks':             len(passing_picks),
        'total_candidates':        total_picks,
        'avg_picks_per_micrograph': avg_picks_per_mic,
        'threshold_used':          threshold,
        'model_architecture':      architecture
    }

    with open('topaz_picks.cs', 'w') as f:
        json.dump(cs_data, f, indent=2)

    with open('topaz_extract_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Topaz extraction complete")
    print(f"  Micrographs processed : {num_mics}")
    print(f"  Picks passing threshold ({threshold}): {len(passing_picks)}")
    print(f"  Avg picks per micrograph : {avg_picks_per_mic}")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    Topaz Extract -- Apply Trained Picker to Full Dataset
    ====================================================================
    Threshold     : ${params.topaz_threshold}
    Expected PPM  : ${params.expected_particles_per_micrograph}
    Output        : ${params.outdir}
    ====================================================================
    """.stripIndent()

    ch_mics = Channel.fromPath(
        params.micrographs_cs ?: 'micrographs_ctf.cs',
        checkIfExists: true
    )

    ch_model = Channel.fromPath(
        params.topaz_model ?: 'topaz_model.pth',
        checkIfExists: true
    )

    TOPAZ_EXTRACT(ch_mics, ch_model)

    TOPAZ_EXTRACT.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Topaz Extract Results:
          Micrographs       : ${r.num_micrographs}
          Total picks       : ${r.total_picks}
          Avg picks/mic     : ${r.avg_picks_per_micrograph}
          Threshold used    : ${r.threshold_used}
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Topaz Extract completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
