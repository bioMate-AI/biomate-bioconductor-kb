#!/usr/bin/env nextflow
/*
 * immunology/isolate_purify_immune_cells
 * Simulates the isolation and purification of immune cells from tissue samples.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: immune cell isolation parameters
params.tissue_type = 'spleen'
params.target_cell_type = 'macrophages'
params.enzyme_type = 'collagenase'
params.macs_antibody = 'CD11b'
params.digestion_time_min = '45'

process ISOLATE_PURIFY_IMMUNE_CELLS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("isolate_purify_immune_cells_results.json"), emit: results
    tuple val(meta), path("isolate_purify_immune_cells_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TISSUE_TYPE="${params.tissue_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_CELL_TYPE="${params.target_cell_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_TYPE="${params.enzyme_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MACS_ANTIBODY="${params.macs_antibody?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DIGESTION_TIME_MIN="${params.digestion_time_min?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

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



def isolate_purify_immune_cells(
    tissue_type,
    target_cell_type,
    enzyme_type="collagenase",
    macs_antibody=None,
    digestion_time_min=45,
):
    '''Simulates the isolation and purification of immune cells from tissue samples.

    Parameters
    ----------
    tissue_type : str
        The type of tissue sample (e.g., 'adipose', 'kidney', 'liver', 'lung', 'spleen')
    target_cell_type : str
        The immune cell population to isolate (e.g., 'macrophages', 'leukocytes', 'T cells')
    enzyme_type : str, optional
        The enzyme used for tissue digestion (default: 'collagenase')
    macs_antibody : str, optional
        Specific antibody for magnetic-assisted cell sorting (default: None, will be set based on target cell type)
    digestion_time_min : int, optional
        Digestion time in minutes (default: 45)

    Returns
    -------
    str
        A research log describing the cell isolation and purification process

    '''
    from datetime import datetime

    import numpy as np
    import pandas as pd

    # Initialize research log
    log = []
    log.append(f"CELL ISOLATION AND PURIFICATION LOG - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append(f"Tissue type: {tissue_type}")
    log.append(f"Target cell population: {target_cell_type}")
    log.append("-" * 50)

    # Set default MACS antibody if not provided
    if macs_antibody is None:
        if target_cell_type.lower() == "macrophages":
            macs_antibody = "CD11b"
        elif target_cell_type.lower() == "t cells":
            macs_antibody = "CD3"
        elif target_cell_type.lower() == "b cells":
            macs_antibody = "CD19"
        else:
            macs_antibody = "CD45"  # General leukocyte marker

    # Step 1: Tissue preparation
    log.append("1. TISSUE PREPARATION")
    log.append(f"   - {tissue_type.capitalize()} tissue was collected and placed in cold PBS")
    log.append("   - Tissue was minced into small pieces (1-2 mm) using sterile scissors")

    # Step 2: Enzymatic digestion
    log.append("\\n2. ENZYMATIC DIGESTION")
    log.append(
        f"   - Tissue fragments were incubated in {enzyme_type} solution at 37°C for {digestion_time_min} minutes"
    )
    log.append("   - Gentle agitation was applied every 15 minutes to enhance digestion")

    # Simulate cell count after digestion
    initial_cell_count = np.random.randint(1e6, 1e7)
    log.append(f"   - Cell count after digestion: {initial_cell_count:,} cells")

    # Step 3: Filtration/Cell straining
    log.append("\\n3. FILTRATION/CELL STRAINING")
    log.append("   - Cell suspension was filtered through a 70 μm cell strainer")
    log.append("   - Additional washing with PBS was performed to maximize cell recovery")

    # Simulate cell count after filtration
    post_filtration_count = int(initial_cell_count * np.random.uniform(0.7, 0.9))
    log.append(f"   - Cell count after filtration: {post_filtration_count:,} cells")

    # Step 4: Density gradient centrifugation
    log.append("\\n4. DENSITY GRADIENT CENTRIFUGATION")
    log.append("   - Cell suspension was carefully layered over Ficoll-Paque medium")
    log.append("   - Centrifugation was performed at 400 × g for 30 minutes at room temperature")
    log.append("   - The interface layer containing mononuclear cells was collected")

    # Simulate cell count after density gradient
    post_gradient_count = int(post_filtration_count * np.random.uniform(0.3, 0.6))
    log.append(f"   - Cell count after density gradient: {post_gradient_count:,} cells")

    # Step 5: Magnetic-assisted cell sorting (MACS)
    log.append("\\n5. MAGNETIC-ASSISTED CELL SORTING (MACS)")
    log.append(f"   - Cells were labeled with anti-{macs_antibody} magnetic microbeads")
    log.append("   - Labeled cell suspension was passed through a MACS column in a magnetic field")
    log.append(f"   - {target_cell_type.capitalize()} were collected based on their binding to the magnetic beads")

    # Simulate final purified cell count
    final_cell_count = int(post_gradient_count * np.random.uniform(0.1, 0.3))
    purity = np.random.uniform(0.85, 0.98)
    log.append(f"   - Final cell count: {final_cell_count:,} {target_cell_type}")
    log.append(f"   - Estimated purity: {purity:.1%}")

    # Step 6: Quality assessment
    log.append("\\n6. QUALITY ASSESSMENT")
    log.append("   - Cell viability was assessed using trypan blue exclusion")
    viability = np.random.uniform(0.85, 0.98)
    log.append(f"   - Cell viability: {viability:.1%}")
    log.append("   - Purity was confirmed by flow cytometry analysis")

    # Create a summary table and save as CSV
    cell_data = {
        "Process Step": [
            "Initial",
            "Post-Filtration",
            "Post-Gradient",
            "Final Purified",
        ],
        "Cell Count": [
            initial_cell_count,
            post_filtration_count,
            post_gradient_count,
            final_cell_count,
        ],
        "Viability (%)": [
            np.random.uniform(0.7, 0.9) * 100,
            np.random.uniform(0.75, 0.92) * 100,
            np.random.uniform(0.8, 0.95) * 100,
            viability * 100,
        ],
    }

    df = pd.DataFrame(cell_data)
    csv_filename = f"{tissue_type}_{target_cell_type}_isolation_data.csv"
    df.to_csv(csv_filename, index=False)

    log.append(f"\\nCell count data saved to: {csv_filename}")
    log.append("\\nPURIFICATION COMPLETE")

    return "\\n".join(log)

# Execute the function
try:
    result = isolate_purify_immune_cells(
        tissue_type=auto_convert(os.environ.get("PARAM_TISSUE_TYPE", "")),
        target_cell_type=auto_convert(os.environ.get("PARAM_TARGET_CELL_TYPE", "")),
        enzyme_type=auto_convert(os.environ.get("PARAM_ENZYME_TYPE", "collagenase")),
        macs_antibody=auto_convert(os.environ.get("PARAM_MACS_ANTIBODY", "")),
        digestion_time_min=auto_convert(os.environ.get("PARAM_DIGESTION_TIME_MIN", "45")),
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
    "function": "isolate_purify_immune_cells",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("isolate_purify_immune_cells_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("isolate_purify_immune_cells_output.txt", "w") as f:
    f.write("Biomni: Isolate Purify Immune Cells" + NL)
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
        biomni_function: "isolate_purify_immune_cells"
    END_VERSIONS
    """
}

workflow ISOLATE_PURIFY_IMMUNE_CELLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ISOLATE_PURIFY_IMMUNE_CELLS(ch_input)

    emit:
    results = ISOLATE_PURIFY_IMMUNE_CELLS.out.results
    output = ISOLATE_PURIFY_IMMUNE_CELLS.out.output
    versions = ISOLATE_PURIFY_IMMUNE_CELLS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ISOLATE_PURIFY_IMMUNE_CELLS_WORKFLOW(ch_input)

    ISOLATE_PURIFY_IMMUNE_CELLS_WORKFLOW.out.output.view { "Output: $it" }
}
