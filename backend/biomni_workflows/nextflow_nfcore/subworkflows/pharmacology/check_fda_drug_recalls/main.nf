#!/usr/bin/env nextflow
/*
 * pharmacology/check_fda_drug_recalls
 * Check for FDA drug recalls and enforcement actions.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_name = 'aspirin'
params.classification = null
params.date_range = null

process CHECK_FDA_DRUG_RECALLS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("check_fda_drug_recalls_results.json"), emit: results
    tuple val(meta), path("check_fda_drug_recalls_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DRUG_NAME="${params.drug_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLASSIFICATION="${params.classification?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATE_RANGE="${params.date_range?.toString()?.replace('"', '\\"') ?: 'null'}"

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

def _standardize_drug_name_fda(drug_name: str) -> str:
    '''Standardize drug names for FDA API queries.'''
    # Handle None/empty values
    if not drug_name:
        return ""

    # Remove common suffixes
    suffixes = ["sodium", "hydrochloride", "sulfate", "phosphate", "acetate", "citrate"]

    # Clean and standardize
    name = drug_name.strip().lower()

    for suffix in suffixes:
        if name.endswith(f" {suffix}"):
            name = name[: -len(f" {suffix}")]

    return name

def _format_recall_summary(response_data: dict, drug_name: str, include_details: bool = True) -> str:
    '''Format recall information into structured output.'''
    if not response_data.get("results"):
        return f"No drug recalls found for {drug_name} in the FDA database."

    summary = "OpenFDA Drug Recall Information\\n"
    summary += "=" * 31 + "\\n"
    summary += f"Drug: {drug_name}\\n"
    summary += f"Total recalls found: {len(response_data['results'])}\\n\\n"

    if include_details:
        summary += "Recall Details:\\n"

        for i, recall in enumerate(response_data["results"][:5], 1):  # Show top 5
            summary += f"{i}. Recall Number: {recall.get('recall_number', 'N/A')}\\n"
            summary += f"   - Product: {recall.get('product_description', 'N/A')}\\n"
            summary += f"   - Classification: {recall.get('classification', 'N/A')}\\n"
            summary += f"   - Reason: {recall.get('reason_for_recall', 'N/A')}\\n"
            summary += f"   - Date: {recall.get('recall_initiation_date', 'N/A')}\\n"
            summary += f"   - Status: {recall.get('status', 'N/A')}\\n"
            summary += f"   - Distribution: {recall.get('distribution_pattern', 'N/A')}\\n\\n"

        if len(response_data["results"]) > 5:
            summary += f"... and {len(response_data['results']) - 5} additional recalls\\n"

    return summary

def check_fda_drug_recalls(
    drug_name: str, classification: list[str] | None = None, date_range: tuple[str, str] | None = None
) -> str:
    '''
    Check for FDA drug recalls and enforcement actions.

    Args:
        drug_name: Name of the drug to check
        classification: Optional filter by recall class ["Class I", "Class II", "Class III"]
        date_range: Optional date range for recalls

    Returns:
        Formatted string with recall information
    '''
    try:
        # Validate input
        if not drug_name or not drug_name.strip():
            return "Error: Drug name cannot be empty"

        client = OpenFDAClient()

        # Standardize drug name
        standardized_name = _standardize_drug_name_fda(drug_name)
        if not standardized_name:
            return f"Error: Unable to standardize drug name '{drug_name}'"

        # Query drug recalls
        response = client.query_drug_recalls(standardized_name, classification=classification)

        # Format results with filter information
        formatted_result = _format_recall_summary(response, drug_name, include_details=True)

        # Add filter information to the output
        if classification:
            formatted_result = formatted_result.replace(
                f"Drug: {drug_name}\\n", f"Drug: {drug_name}\\nClassification filter: {', '.join(classification)}\\n"
            )

        if date_range:
            formatted_result = formatted_result.replace(
                f"Drug: {drug_name}\\n", f"Drug: {drug_name}\\nDate range: {date_range[0]} to {date_range[1]}\\n"
            )

        return formatted_result

    except Exception as e:
        return f"Error checking FDA drug recalls for {drug_name}: {str(e)}"

# Execute the function
try:
    result = check_fda_drug_recalls(
        drug_name=auto_convert(os.environ.get("PARAM_DRUG_NAME", "")),
        classification=auto_convert(os.environ.get("PARAM_CLASSIFICATION", "")),
        date_range=auto_convert(os.environ.get("PARAM_DATE_RANGE", "")),
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
    "function": "check_fda_drug_recalls",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("check_fda_drug_recalls_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("check_fda_drug_recalls_output.txt", "w") as f:
    f.write("Biomni: Check Fda Drug Recalls" + NL)
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
        biomni_function: "check_fda_drug_recalls"
    END_VERSIONS
    """
}

workflow CHECK_FDA_DRUG_RECALLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CHECK_FDA_DRUG_RECALLS(ch_input)

    emit:
    results = CHECK_FDA_DRUG_RECALLS.out.results
    output = CHECK_FDA_DRUG_RECALLS.out.output
    versions = CHECK_FDA_DRUG_RECALLS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CHECK_FDA_DRUG_RECALLS_WORKFLOW(ch_input)

    CHECK_FDA_DRUG_RECALLS_WORKFLOW.out.output.view { "Output: $it" }
}
