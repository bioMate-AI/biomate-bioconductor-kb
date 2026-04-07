#!/usr/bin/env nextflow
/*
 * Topaz Train -- Custom Neural Network Particle Picker Training
 *
 * Trains a Topaz neural network particle picker on YOUR micrographs using
 * positive examples from a prior picking round (blob picker, template picker,
 * or manual picks).  The trained model encodes sample-specific signal,
 * yielding higher sensitivity and lower false-positive rate than generic
 * picking when subsequently applied to the full dataset.
 *
 * Architecture options:
 *   resnet8   -- lightweight, suitable for small training sets
 *   resnet16  -- default; better for diverse particle appearances
 *
 * References:
 *   Bepler et al. 2019 Nat Methods 16:1153  (Topaz)
 *   Bepler et al. 2020 Nat Commun 11:5529   (Topaz-Denoise)
 *
 * Domain: Cryo-EM / Topaz
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.num_training_micrographs           = 50    // micrographs sampled for training
params.expected_particles_per_micrograph  = 300   // used for radius / normalization
params.train_epochs                       = 10    // training iterations
params.model_architecture                 = 'resnet16'  // 'resnet8' or 'resnet16'
params.use_cryosparc                      = false
params.outdir                             = './results/topaz_train'

// ============================================================================
// Process Definition
// ============================================================================

process TOPAZ_TRAIN {
    tag "topaz_train"
    label 'process_gpu'
    publishDir "${params.outdir}/topaz_train", mode: 'copy'

    input:
    path micrographs_cs
    path particles_cs

    output:
    path "topaz_model.pth",          emit: topaz_model
    path "topaz_train_report.json",  emit: report

    script:
    """
    #!/usr/bin/env python3
    import json
    import subprocess
    import sys
    import os
    from pathlib import Path
    from datetime import datetime

    architecture   = '${params.model_architecture}'
    num_train_mics = ${params.num_training_micrographs}
    exp_ppm        = ${params.expected_particles_per_micrograph}
    train_epochs   = ${params.train_epochs}

    mics_data  = json.load(open('${micrographs_cs}'))
    parts_data = json.load(open('${particles_cs}'))

    micrographs  = mics_data.get('micrographs', [])
    particles    = parts_data.get('particles', parts_data.get('picks', []))

    # Subsample micrographs for training
    actual_train_mics = min(num_train_mics, len(micrographs))
    train_mics = micrographs[:actual_train_mics]

    # Write training micrograph list
    mic_list_path = Path('train_micrographs.txt')
    with open(mic_list_path, 'w') as fh:
        for mic in train_mics:
            fh.write(mic.get('filename', mic.get('micrograph_path', '')) + '\\n')

    # Write positive coordinates file (topaz format: image_name x y)
    coords_path = Path('train_particles.txt')
    mic_idx_to_name = {
        mic.get('micrograph_idx', i): Path(mic.get('filename', mic.get('micrograph_path', ''))).stem
        for i, mic in enumerate(train_mics)
    }
    with open(coords_path, 'w') as fh:
        fh.write('image_name\\tx_coord\\ty_coord\\n')
        for p in particles:
            mic_idx = p.get('micrograph_idx', 0)
            mic_name = mic_idx_to_name.get(mic_idx, f'mic_{mic_idx:05d}')
            x = p.get('x_coord', p.get('x', 0))
            y = p.get('y_coord', p.get('y', 0))
            fh.write(f'{mic_name}\\t{x}\\t{y}\\n')

    # Run topaz train
    cmd = [
        'topaz', 'train',
        '--train-images', str(mic_list_path),
        '--train-targets', str(coords_path),
        '--model', architecture,
        '--num-particles', str(exp_ppm),
        '--num-epochs', str(train_epochs),
        '--save-prefix', 'topaz_model',
        '--output', 'topaz_train_log.txt',
        '--num-workers', str(min(os.cpu_count() or 4, 8))
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"topaz train stderr: {result.stderr}", file=sys.stderr)
        raise RuntimeError(f"topaz train failed with exit code {result.returncode}")

    # topaz saves model as topaz_model_epoch{N}.sav; find the final one
    model_files = sorted(Path('.').glob('topaz_model*.sav')) + sorted(Path('.').glob('topaz_model*.pth'))
    if not model_files:
        raise RuntimeError("topaz train completed but no model file found")
    final_model = model_files[-1]

    # Rename to expected output name
    import shutil
    shutil.copy(str(final_model), 'topaz_model.pth')

    # Parse training log for loss values
    final_train_loss = 0.0
    final_val_loss   = 0.0
    if Path('topaz_train_log.txt').exists():
        with open('topaz_train_log.txt') as fh:
            for line in fh:
                if 'loss' in line.lower():
                    parts_line = line.strip().split()
                    for i, tok in enumerate(parts_line):
                        if tok.lower() in ('loss', 'train_loss') and i + 1 < len(parts_line):
                            try:
                                final_train_loss = float(parts_line[i + 1])
                            except ValueError:
                                pass

    # Write model metadata alongside the binary
    model_meta = {
        'model_path':    'topaz_model.pth',
        'architecture':  architecture,
        'train_epochs':  train_epochs,
        'training_mics': actual_train_mics,
        'expected_ppm':  exp_ppm,
        'threshold':     -6.0,
        'trained_at':    datetime.now().isoformat()
    }
    with open('topaz_model_meta.json', 'w') as f:
        json.dump(model_meta, f, indent=2)

    report = {
        'step':                              'topaz_train',
        'timestamp':                         datetime.now().isoformat(),
        'architecture':                      architecture,
        'training_micrographs':              actual_train_mics,
        'training_particles_available':      len(particles),
        'train_epochs':                      train_epochs,
        'final_train_loss':                  final_train_loss,
        'final_val_loss':                    final_val_loss,
        'particles_per_micrograph_expected': exp_ppm,
        'model_file':                        'topaz_model.pth'
    }

    with open('topaz_train_report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f"Topaz training complete ({architecture})")
    print(f"  Training micrographs : {actual_train_mics}")
    print(f"  Train epochs         : {train_epochs}")
    print(f"  Model saved          : topaz_model.pth")
    """
}

// ============================================================================
// Workflow (standalone execution)
// ============================================================================

workflow {
    log.info """
    ====================================================================
    Topaz Train -- Custom Particle Picker Training
    ====================================================================
    Architecture  : ${params.model_architecture}
    Train mics    : ${params.num_training_micrographs}
    Expected PPM  : ${params.expected_particles_per_micrograph}
    Train epochs  : ${params.train_epochs}
    Output        : ${params.outdir}
    ====================================================================
    """.stripIndent()

    ch_mics = Channel.fromPath(
        params.micrographs_cs ?: 'micrographs_ctf.cs',
        checkIfExists: true
    )

    ch_parts = Channel.fromPath(
        params.particles_cs ?: 'particles.cs',
        checkIfExists: true
    )

    TOPAZ_TRAIN(ch_mics, ch_parts)

    TOPAZ_TRAIN.out.report.view { report_file ->
        def r = new groovy.json.JsonSlurper().parse(report_file)
        """
        Topaz Train Results:
          Architecture : ${r.architecture}
          Train epochs : ${r.train_epochs}
          Model file   : ${r.model_file}
        Results in: ${params.outdir}
        """
    }
}

workflow.onComplete {
    log.info "Topaz Train completed: ${workflow.success ? 'SUCCESS' : 'FAILED'} (${workflow.duration})"
}
