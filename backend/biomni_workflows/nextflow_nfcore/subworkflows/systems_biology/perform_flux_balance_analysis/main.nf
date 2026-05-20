#!/usr/bin/env nextflow
/*
 * systems_biology/perform_flux_balance_analysis
 * Perform Flux Balance Analysis (FBA) on a genome-scale metabolic network model.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Use COBRApy built-in textbook model (E. coli core)
params.model_file = 'textbook'
params.constraints = null
params.objective_reaction = null
params.output_file = 'fba_results.csv'

process PERFORM_FLUX_BALANCE_ANALYSIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_flux_balance_analysis_results.json"), emit: results
    tuple val(meta), path("perform_flux_balance_analysis_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_MODEL_FILE="${params.model_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONSTRAINTS="${params.constraints?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OBJECTIVE_REACTION="${params.objective_reaction?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Set cache directory to current working directory
    export XDG_CACHE_HOME=\$(pwd)/.cache
    export HOME=\$(pwd)
    mkdir -p \$XDG_CACHE_HOME

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



def perform_flux_balance_analysis(model_file, constraints=None, objective_reaction=None, output_file="fba_results.csv"):
    '''
    Perform Flux Balance Analysis (FBA) on a genome-scale metabolic network model.

    FBA is a computational technique that predicts metabolic flux distributions
    by formulating and solving a linear optimization problem.

    Parameters:
    -----------
    model_file : str
        Path to the metabolic model file (SBML or JSON format)
    constraints : dict, optional
        Dictionary of reaction constraints where keys are reaction IDs and
        values are tuples of (lower_bound, upper_bound)
    objective_reaction : str, optional
        Reaction ID to use as the objective function (e.g., biomass reaction)
        If None, uses the model's default objective
    output_file : str, optional
        File name to save the flux distribution results

    Returns:
    --------
    str
        Research log summarizing the FBA process and results
    '''

    import cobra
    import pandas as pd

    # Initialize research log
    log = "# Flux Balance Analysis (FBA) Research Log\\n\\n"

    # Step 1: Load the metabolic network model
    log += "## Step 1: Loading metabolic model\\n"
    try:
        if model_file.endswith(".xml") or model_file.endswith(".sbml"):
            model = cobra.io.read_sbml_model(model_file)
        elif model_file.endswith(".json"):
            model = cobra.io.load_json_model(model_file)
        else:
            model = cobra.io.load_model(model_file)
        log += f"- Successfully loaded model from {model_file}\\n"
        log += f"- Model contains {len(model.reactions)} reactions and {len(model.metabolites)} metabolites\\n\\n"
    except Exception as e:
        log += f"- Error loading model: {str(e)}\\n"
        return log

    # Step 2: Set constraints
    log += "## Step 2: Setting constraints\\n"
    if constraints:
        log += "- Applied the following constraints:\\n"
        for reaction_id, (lb, ub) in constraints.items():
            try:
                reaction = model.reactions.get_by_id(reaction_id)
                reaction.bounds = (lb, ub)
                log += f"  * {reaction_id}: lower_bound={lb}, upper_bound={ub}\\n"
            except Exception as e:
                log += f"  * Error setting constraint for {reaction_id}: {str(e)}\\n"
    else:
        log += "- No additional constraints specified, using model defaults\\n"
    log += "\\n"

    # Step 3: Set objective function
    log += "## Step 3: Setting objective function\\n"
    if objective_reaction:
        try:
            model.objective = objective_reaction
            log += f"- Set objective function to maximize {objective_reaction}\\n\\n"
        except Exception as e:
            log += f"- Error setting objective function: {str(e)}\\n"
            log += "- Using model's default objective function\\n\\n"
    else:
        log += f"- Using model's default objective function: {model.objective.expression}\\n\\n"

    # Step 4: Solve the FBA problem
    log += "## Step 4: Solving FBA optimization problem\\n"
    try:
        solution = model.optimize()
        log += f"- Optimization status: {solution.status}\\n"
        log += f"- Objective value: {solution.objective_value:.6f}\\n\\n"
    except Exception as e:
        log += f"- Error during optimization: {str(e)}\\n"
        return log

    # Step 5: Save and report results
    log += "## Step 5: Analyzing flux distribution\\n"

    # Create a dataframe with the flux distribution
    flux_distribution = pd.DataFrame(
        {
            "reaction_id": [r.id for r in model.reactions],
            "reaction_name": [r.name for r in model.reactions],
            "flux": [solution.fluxes[r.id] for r in model.reactions],
            "lower_bound": [r.lower_bound for r in model.reactions],
            "upper_bound": [r.upper_bound for r in model.reactions],
        }
    )

    # Save to file
    flux_distribution.to_csv(output_file, index=False)
    log += f"- Flux distribution saved to {output_file}\\n"

    # Report active reactions (non-zero flux)
    active_reactions = flux_distribution[abs(flux_distribution["flux"]) > 1e-6]
    log += f"- Number of active reactions (flux > 1e-6): {len(active_reactions)}\\n"

    # Report top reactions by absolute flux
    top_reactions = flux_distribution.iloc[abs(flux_distribution["flux"]).argsort()[::-1]].head(10)
    log += "- Top 10 reactions by absolute flux magnitude:\\n"
    for _, row in top_reactions.iterrows():
        log += f"  * {row['reaction_id']} ({row['reaction_name']}): {row['flux']:.6f}\\n"

    log += f"\\nFBA analysis complete. Full results available in {output_file}\\n"

    return log

# Execute the function
try:
    result = perform_flux_balance_analysis(
        model_file=auto_convert(os.environ.get("PARAM_MODEL_FILE", "")),
        constraints=auto_convert(os.environ.get("PARAM_CONSTRAINTS", "")),
        objective_reaction=auto_convert(os.environ.get("PARAM_OBJECTIVE_REACTION", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "fba_results.csv")),
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
    "function": "perform_flux_balance_analysis",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_flux_balance_analysis_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_flux_balance_analysis_output.txt", "w") as f:
    f.write("Biomni: Perform Flux Balance Analysis" + NL)
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
        biomni_function: "perform_flux_balance_analysis"
    END_VERSIONS
    """
}

workflow PERFORM_FLUX_BALANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_FLUX_BALANCE_ANALYSIS(ch_input)

    emit:
    results = PERFORM_FLUX_BALANCE_ANALYSIS.out.results
    output = PERFORM_FLUX_BALANCE_ANALYSIS.out.output
    versions = PERFORM_FLUX_BALANCE_ANALYSIS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_FLUX_BALANCE_ANALYSIS_WORKFLOW(ch_input)

    PERFORM_FLUX_BALANCE_ANALYSIS_WORKFLOW.out.output.view { "Output: $it" }
}
