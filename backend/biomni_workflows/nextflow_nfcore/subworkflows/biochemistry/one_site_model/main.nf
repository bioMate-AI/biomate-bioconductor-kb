#!/usr/bin/env nextflow
/*
 * biochemistry/one_site_model
 * One-site binding model for ITC data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null
params.Kd = null
params.dH = null
params.n = null

process ONE_SITE_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("one_site_model_results.json"), emit: results
    tuple val(meta), path("one_site_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_X="${params.x?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KD="${params.Kd?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DH="${params.dH?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N="${params.n?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def one_site_model(x, kd, dh, n):
    '''One-site binding model for ITC data.

    Args:
        x: Molar ratio [ligand]/[protein]
        kd: Dissociation constant (M)
        dh: Enthalpy change (cal/mol)
        n: Stoichiometry

    Returns:
        Binding parameters and calculated heat
    '''
    # Validate inputs - use defaults if None
    if x is None:
        x = 1.0
    if kd is None:
        kd = 1e-6  # 1 uM default
    if dh is None:
        dh = -10000.0  # -10 kcal/mol default
    if n is None:
        n = 1.0
    x, kd, dh, n = float(x), float(kd), float(dh), float(n)

    ka = 1 / kd if kd != 0 else 0  # Association constant
    # Simplified binding calculation
    theta = (ka * x) / (1 + ka * x) if (1 + ka * x) != 0 else 0  # Fraction bound
    q = n * dh * theta  # Heat
    return {"heat": float(q), "fraction_bound": float(theta), "x": x, "kd": kd, "dh": dh, "n": n}

# Execute the function
try:
    result = one_site_model(
        x=auto_convert(os.environ.get("PARAM_X", "")),
        kd=auto_convert(os.environ.get("PARAM_KD", "")),
        dh=auto_convert(os.environ.get("PARAM_DH", "")),
        n=auto_convert(os.environ.get("PARAM_N", "")),
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
    "function": "one_site_model",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("one_site_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("one_site_model_output.txt", "w") as f:
    f.write("Biomni: One Site Model" + NL)
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
        biomni_function: "one_site_model"
    END_VERSIONS
    """
}

workflow ONE_SITE_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ONE_SITE_MODEL(ch_input)

    emit:
    results = ONE_SITE_MODEL.out.results
    output = ONE_SITE_MODEL.out.output
    versions = ONE_SITE_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ONE_SITE_MODEL_WORKFLOW(ch_input)

    ONE_SITE_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
