nextflow.enable.dsl = 2

// DEEPEMHANCER — Post-processing map enhancement
// Replaces simple B-factor sharpening with learned deep-learning enhancement
// Implements P2-priority gap from BioMate cryo-EM skill framework
//
// Container: biomate/cryo-em-tools:1.0 (GPU optional)
// Paper reference: Sanchez-Garcia et al. (2021) Commun Biol 4:874

process DEEPEMHANCER {
    tag "deepemhancer"
    publishDir "${params.outdir}/post_processing/deepemhancer", mode: 'copy'

    container 'biomate/cryo-em-tools:1.0'

    input:
    path sharpened_map
    path halfmap1
    path halfmap2
    val  resolution_A

    output:
    path "deepemhancer_enhanced.mrc",   emit: enhanced_map
    path "deepemhancer_report.json",    emit: report

    script:
    def res_flag = resolution_A ? "--resolution ${resolution_A}" : ''
    def hm_flag = (halfmap1 && halfmap2) ? "--halfmap1 ${halfmap1} --halfmap2 ${halfmap2}" : ''

    // Auto-select model based on resolution
    def model_type = 'tight'
    if (resolution_A) {
        def res = resolution_A as Float
        if (res < 3.0) model_type = 'highRes'
        else if (res > 4.5) model_type = 'wide'
    }

    """
    python3 /opt/biomate_cryo_em/scripts/deepemhancer_postprocess.py \\
        --input ${sharpened_map} \\
        --output deepemhancer_enhanced.mrc \\
        ${hm_flag} \\
        ${res_flag} \\
        --model ${model_type} \\
        --report deepemhancer_report.json
    """


    stub:
    """
    echo '{"tool": "deepemhancer", "mock": true, "model": "tight"}' > deepemhancer_report.json
    cp ${sharpened_map} deepemhancer_enhanced.mrc 2>/dev/null || \\
        python3 -c "
import mrcfile, numpy as np
with mrcfile.new('deepemhancer_enhanced.mrc', overwrite=True) as mrc:
    mrc.set_data(np.zeros((64,64,64), dtype=np.float32))
    mrc.voxel_size = ${params.pixel_size ?: 0.83}
"
    """
}
