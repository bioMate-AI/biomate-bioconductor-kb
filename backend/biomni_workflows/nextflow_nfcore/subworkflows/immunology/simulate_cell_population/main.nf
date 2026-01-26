#!/usr/bin/env nextflow
/*
 * immunology/simulate_cell_population
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_count = null
params.growth_rate = null
params.death_rate = null
params.time_points = null

process SIMULATE_CELL_POPULATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_cell_population_results.json"), emit: results
    tuple val(meta), path("simulate_cell_population_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_INITIAL_COUNT="${params.initial_count?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROWTH_RATE="${params.growth_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DEATH_RATE="${params.death_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import numpy as np
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



def simulate_cell_population(initial_count, growth_rate, death_rate, time_points):
    '''Simulate: dN/dt = (growth - death) * N
    Args: initial_count, growth_rate, death_rate, time_points (comma-separated)
    '''
    if isinstance(time_points, str):
        time_points = [float(x.strip()) for x in time_points.split(',')]
    
    net_rate = growth_rate - death_rate
    populations = [initial_count * np.exp(net_rate * t) for t in time_points]
    return {"time_points": time_points, "populations": populations, "net_growth_rate": net_rate}

# Execute the function
try:
    result = simulate_cell_population(
        initial_count=auto_convert(os.environ.get("PARAM_INITIAL_COUNT", "")),
        growth_rate=auto_convert(os.environ.get("PARAM_GROWTH_RATE", "")),
        death_rate=auto_convert(os.environ.get("PARAM_DEATH_RATE", "")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
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
    "function": "simulate_cell_population",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_cell_population_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_cell_population_output.txt", "w") as f:
    f.write("Biomni: Simulate Cell Population" + NL)
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
        biomni_function: "simulate_cell_population"
    END_VERSIONS
    """
}

workflow SIMULATE_CELL_POPULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_CELL_POPULATION(ch_input)

    emit:
    results = SIMULATE_CELL_POPULATION.out.results
    output = SIMULATE_CELL_POPULATION.out.output
    versions = SIMULATE_CELL_POPULATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_CELL_POPULATION_WORKFLOW(ch_input)

    SIMULATE_CELL_POPULATION_WORKFLOW.out.output.view { "Output: $it" }
}
