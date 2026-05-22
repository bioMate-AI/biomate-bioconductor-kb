#!/usr/bin/env nextflow
/*
 * pharmacology/get_fda_drug_label_info
 * Retrieve FDA drug label information.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Aspirin FDA drug label lookup
params.drug_name = 'aspirin'
params.sections = '["indications_and_usage", "contraindications", "warnings"]'

process GET_FDA_DRUG_LABEL_INFO {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_fda_drug_label_info_results.json"), emit: results
    tuple val(meta), path("get_fda_drug_label_info_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DRUG_NAME="${params.drug_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SECTIONS="${params.sections?.toString()?.replace('"', '\\"') ?: 'null'}"

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

def _format_drug_label_summary(response_data: dict, drug_name: str, sections: list[str] | None = None) -> str:
    '''Format drug label information into readable summary.'''
    if not response_data.get("results"):
        return f"No drug label information found for {drug_name} in the FDA database."

    result = response_data["results"][0]  # Use first result

    summary = "OpenFDA Drug Label Information\\n"
    summary += "=" * 29 + "\\n"
    summary += f"Drug: {drug_name}\\n"

    # Extract key information
    if "effective_time" in result:
        summary += f"Effective Date: {result['effective_time']}\\n"

    if "openfda" in result:
        openfda = result["openfda"]
        if "brand_name" in openfda:
            summary += f"Brand Name: {', '.join(openfda['brand_name'])}\\n"
        if "generic_name" in openfda:
            summary += f"Generic Name: {', '.join(openfda['generic_name'])}\\n"
        if "manufacturer_name" in openfda:
            summary += f"Manufacturer: {', '.join(openfda['manufacturer_name'])}\\n"

    summary += "\\n"

    # Display specific sections
    section_mapping = {
        "indications_and_usage": "Indications and Usage",
        "contraindications": "Contraindications",
        "warnings": "Warnings",
        "dosage_and_administration": "Dosage and Administration",
        "adverse_reactions": "Adverse Reactions",
        "clinical_pharmacology": "Clinical Pharmacology",
    }

    sections_to_show = sections if sections else section_mapping.keys()

    for section_key in sections_to_show:
        if section_key in result:
            section_title = section_mapping.get(section_key, section_key.title())
            summary += f"{section_title}:\\n"

            content = result[section_key]
            if isinstance(content, list):
                content = " ".join(content)

            # Truncate long content
            if len(content) > 500:
                content = content[:500] + "..."

            summary += f"{content}\\n\\n"

    return summary

def get_fda_drug_label_info(drug_name: str, sections: list[str] | None = None) -> str:
    '''
    Retrieve FDA drug label information.

    Args:
        drug_name: Name of the drug to query
        sections: Optional list of specific sections to retrieve
                 ["indications_and_usage", "contraindications", "warnings", "dosage_and_administration"]

    Returns:
        Formatted string with drug label information
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

        # Query drug labels
        response = client.query_drug_labels(standardized_name, sections=sections)

        # Check if we got results
        if not response.get("results"):
            return f"No label information found for drug: {drug_name}"

        # Format results
        return _format_drug_label_summary(response, drug_name, sections=sections)

    except Exception as e:
        return f"Error retrieving FDA drug label for {drug_name}: {str(e)}"

# Execute the function
try:
    result = get_fda_drug_label_info(
        drug_name=auto_convert(os.environ.get("PARAM_DRUG_NAME", "")),
        sections=auto_convert(os.environ.get("PARAM_SECTIONS", "")),
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
    "function": "get_fda_drug_label_info",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_fda_drug_label_info_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_fda_drug_label_info_output.txt", "w") as f:
    f.write("Biomni: Get Fda Drug Label Info" + NL)
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
        biomni_function: "get_fda_drug_label_info"
    END_VERSIONS
    """
}

workflow GET_FDA_DRUG_LABEL_INFO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_FDA_DRUG_LABEL_INFO(ch_input)

    emit:
    results = GET_FDA_DRUG_LABEL_INFO.out.results
    output = GET_FDA_DRUG_LABEL_INFO.out.output
    versions = GET_FDA_DRUG_LABEL_INFO.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_FDA_DRUG_LABEL_INFO_WORKFLOW(ch_input)

    GET_FDA_DRUG_LABEL_INFO_WORKFLOW.out.output.view { "Output: $it" }
}
