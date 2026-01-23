#!/usr/bin/env nextflow
/*
 * biomni_lab_automation_test_pylabrobot_script
 * Test a PyLabRobot script using simulation and validation.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.script_input = null
params.enable_tracking = false
params.timeout_seconds = 60
params.save_test_report = false
params.test_report_dir = null

// Main process
process TEST_PYLABROBOT_SCRIPT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("test_pylabrobot_script_results.json"), emit: results
    path("test_pylabrobot_script_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.lab_automation import test_pylabrobot_script

# Run the tool
try:
    result = test_pylabrobot_script(
    script_input="${params.script_input}",
    enable_tracking=${params.enable_tracking ? "True" : "False"},
    timeout_seconds=${params.timeout_seconds},
    save_test_report=${params.save_test_report ? "True" : "False"},
    test_report_dir="${params.test_report_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("test_pylabrobot_script_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("test_pylabrobot_script_output.txt", "w") as f:
    f.write("Biomni: Test Pylabrobot Script Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("test_pylabrobot_script completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LAB_AUTOMATION_TEST_PYLABROBOT_SCRIPT {
    take:
    // No file inputs

    main:
    TEST_PYLABROBOT_SCRIPT()

    emit:
    results = TEST_PYLABROBOT_SCRIPT.out.results
    output = TEST_PYLABROBOT_SCRIPT.out.output
}

// Entry workflow
workflow {
    if (!params.script_input) {
        error "Please provide --script_input parameter"
    }


    BIOMNI_LAB_AUTOMATION_TEST_PYLABROBOT_SCRIPT()
}
