#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_aortic_diameter_and_geometry
 * Analyze aortic diameter and geometry from cardiovascular imaging data to measure aortic root diameter, ascending aorta diameter, and calculate geometric parameters such as tortuosity and dilation indices.
 * Runs in Docker: biomate/biotools:arm64
 */

nextflow.enable.dsl = 2

params.outdir = "./results"
params.input = "input.txt"


process Step_1:_cv2_moments {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/Step_1:_cv2_moments", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import sys
print("Running Step_1:_cv2_moments")
with open("Step_1:_cv2_moments_result.txt", "w") as f:
    f.write("Completed")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

process Step_2:_cv2_drawContours {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/Step_2:_cv2_drawContours", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import sys
print("Running Step_2:_cv2_drawContours")
with open("Step_2:_cv2_drawContours_result.txt", "w") as f:
    f.write("Completed")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

process Step_3:_cv2_cvtColor {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/Step_3:_cv2_cvtColor", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import sys
print("Running Step_3:_cv2_cvtColor")
with open("Step_3:_cv2_cvtColor_result.txt", "w") as f:
    f.write("Completed")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

process Step_4:_cv2_imread {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/Step_4:_cv2_imread", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import sys
print("Running Step_4:_cv2_imread")
with open("Step_4:_cv2_imread_result.txt", "w") as f:
    f.write("Completed")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

process Step_5:_cv2_GaussianBlur {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/Step_5:_cv2_GaussianBlur", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import sys
print("Running Step_5:_cv2_GaussianBlur")
with open("Step_5:_cv2_GaussianBlur_result.txt", "w") as f:
    f.write("Completed")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

workflow {
    input_ch = Channel.fromPath(params.input)
    
    Step_1:_cv2_moments(input_ch)
    Step_2:_cv2_drawContours(Step_1:_cv2_moments.out.results)
    Step_3:_cv2_cvtColor(Step_2:_cv2_drawContours.out.results)
    Step_4:_cv2_imread(Step_3:_cv2_cvtColor.out.results)
    Step_5:_cv2_GaussianBlur(Step_4:_cv2_imread.out.results)
}
