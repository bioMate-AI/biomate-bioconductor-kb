#!/usr/bin/env nextflow
/*
 * pharmacology/run_3d_chondrogenic_aggregate_assay
 * Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Chondrogenic assay parameters
params.chondrocyte_cells = '{"source": "Human articular cartilage", "passage_number": 2, "cell_density": 250000}'
params.test_compounds = '[{"name": "Dexamethasone", "concentration": "100 nM", "vehicle": "DMSO"}, {"name": "TGF-beta3", "concentration": "10 ng/mL", "vehicle": "PBS"}]'
params.culture_duration_days = '21'
params.measurement_intervals = '7'

process RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("run_3d_chondrogenic_aggregate_assay_results.json"), emit: results
    tuple val(meta), path("run_3d_chondrogenic_aggregate_assay_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CHONDROCYTE_CELLS="${params.chondrocyte_cells?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TEST_COMPOUNDS="${params.test_compounds?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CULTURE_DURATION_DAYS="${params.culture_duration_days?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MEASUREMENT_INTERVALS="${params.measurement_intervals?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from datetime import datetime
import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def run_3d_chondrogenic_aggregate_assay(
    chondrocyte_cells, test_compounds, culture_duration_days=21, measurement_intervals=7
):
    '''Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.

    Parameters
    ----------
    chondrocyte_cells : dict
        Dictionary with cell information including 'source', 'passage_number', and 'cell_density'
    test_compounds : list of dict
        List of compounds to test, each with 'name', 'concentration', and 'vehicle' keys
    culture_duration_days : int
        Total duration of the culture period in days (default: 21)
    measurement_intervals : int
        Interval in days between measurements (default: 7)

    Returns
    -------
    str
        Detailed protocol document for the 3D chondrogenic aggregate culture assay

    '''
    from datetime import datetime

    # Create experiment ID
    experiment_id = f"CHOND3D_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    # Create time points for measurements
    timepoints = list(range(0, culture_duration_days + 1, measurement_intervals))
    if timepoints[-1] != culture_duration_days:
        timepoints.append(culture_duration_days)

    # Generate the protocol document
    protocol = f"# 3D Chondrogenic Aggregate Culture Assay Protocol - {experiment_id}\\n\\n"

    protocol += "## 1. Materials and Reagents\\n\\n"
    protocol += "- Chondrocyte cells\\n"
    protocol += "- Chondrogenic differentiation medium\\n"
    protocol += "- Transforming growth factor-β3 (TGF-β3)\\n"
    protocol += "- Dexamethasone\\n"
    protocol += "- Ascorbate-2-phosphate\\n"
    protocol += "- 96-well V-bottom plates\\n"
    protocol += "- Gaussia luciferase reporter assay kit\\n"
    protocol += "- Luminometer\\n"
    protocol += "- Test compounds with respective vehicles\\n"
    protocol += "- Centrifuge\\n"
    protocol += "- CO2 incubator\\n"
    protocol += "- Sterile pipettes and tips\\n\\n"

    protocol += "## 2. Experimental Information\\n\\n"
    protocol += "### Cell Information:\\n"
    protocol += f"- Cell source: {chondrocyte_cells['source']}\\n"
    protocol += f"- Passage number: {chondrocyte_cells['passage_number']}\\n"
    protocol += f"- Cell density: {chondrocyte_cells['cell_density']} cells/mL\\n\\n"

    protocol += "### Experimental Design:\\n"
    protocol += f"- Culture duration: {culture_duration_days} days\\n"
    protocol += f"- Measurement timepoints: {', '.join(map(str, timepoints))} days\\n\\n"

    protocol += "### Test Compounds:\\n"
    for i, compound in enumerate(test_compounds):
        protocol += f"- Compound {i + 1}: {compound['name']} at {compound['concentration']} in {compound['vehicle']}\\n"
    protocol += "- Control: Vehicle only\\n\\n"

    protocol += "## 3. Detailed Procedure\\n\\n"
    protocol += "### Day 0: Setup\\n\\n"
    protocol += "1. Prepare chondrogenic differentiation medium containing:\\n"
    protocol += "   - High-glucose DMEM\\n"
    protocol += "   - 10 ng/mL TGF-β3\\n"
    protocol += "   - 100 nM Dexamethasone\\n"
    protocol += "   - 50 μg/mL Ascorbate-2-phosphate\\n"
    protocol += "   - 1% ITS+ premix (insulin, transferrin, selenium)\\n"
    protocol += "   - 1 mM Sodium pyruvate\\n"
    protocol += "   - 100 U/mL Penicillin/Streptomycin\\n\\n"

    protocol += "2. Harvest and count chondrocyte cells\\n\\n"

    protocol += "3. Prepare cell suspension at the specified density:\\n"
    protocol += f"   - {chondrocyte_cells['cell_density']} cells/mL\\n\\n"

    protocol += "4. Form 3D cell aggregates:\\n"
    protocol += "   - Aliquot 2.5×10^5 cells per well in 96-well V-bottom plates\\n"
    protocol += "   - Centrifuge plates at 500g for 5 minutes to pellet cells\\n\\n"

    protocol += "5. Add test compounds to respective wells:\\n"
    for _, compound in enumerate(test_compounds):
        protocol += f"   - Add {compound['name']} at {compound['concentration']} in {compound['vehicle']}\\n"
    protocol += "   - Add vehicle only to control wells\\n\\n"

    protocol += "6. Incubate the plates at 37°C, 5% CO2\\n\\n"

    protocol += "### Day 1 to Day " + str(culture_duration_days) + ":\\n\\n"
    protocol += "1. Change medium every 2-3 days:\\n"
    protocol += "   - Carefully remove 50% of the medium without disturbing the aggregates\\n"
    protocol += "   - Replace with fresh medium containing test compounds at the same concentrations\\n\\n"

    protocol += f"2. At days {', '.join(map(str, timepoints))}, collect samples for analysis:\\n"
    protocol += (
        "   - Take medium samples for Gaussia luciferase activity measurement (if using COL2A1-GLuc reporter cells)\\n"
    )
    protocol += "   - Fix aggregates in 4% paraformaldehyde for histological analysis\\n\\n"

    return protocol

# Execute the function
try:
    result = run_3d_chondrogenic_aggregate_assay(
        chondrocyte_cells=auto_convert(os.environ.get("PARAM_CHONDROCYTE_CELLS", "")),
        test_compounds=auto_convert(os.environ.get("PARAM_TEST_COMPOUNDS", "")),
        culture_duration_days=auto_convert(os.environ.get("PARAM_CULTURE_DURATION_DAYS", "21")),
        measurement_intervals=auto_convert(os.environ.get("PARAM_MEASUREMENT_INTERVALS", "7")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "run_3d_chondrogenic_aggregate_assay",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("run_3d_chondrogenic_aggregate_assay_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("run_3d_chondrogenic_aggregate_assay_output.txt", "w") as f:
    f.write("Biomni: Run 3D Chondrogenic Aggregate Assay" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "run_3d_chondrogenic_aggregate_assay"
    END_VERSIONS
    """
}

workflow RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY(ch_input)

    emit:
    results = RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY.out.results
    output = RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY.out.output
    versions = RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY_WORKFLOW(ch_input)

    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY_WORKFLOW.out.output.view { "Output: $it" }
}
