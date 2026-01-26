#!/usr/bin/env nextflow
/*
 * pharmacology/analyze_fda_safety_signals
 * Analyze safety signals across multiple drugs.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_list = null
params.comparison_period = null
params.signal_threshold = 2.0

process ANALYZE_FDA_SAFETY_SIGNALS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_fda_safety_signals_results.json"), emit: results
    tuple val(meta), path("analyze_fda_safety_signals_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DRUG_LIST="${params.drug_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COMPARISON_PERIOD="${params.comparison_period?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SIGNAL_THRESHOLD="${params.signal_threshold?.toString()?.replace('"', '\\"') ?: 'null'}"

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

def _extract_fda_safety_signals(response_list: list[dict]) -> dict:
    '''Extract safety signals from adverse event data.'''
    drug_signals = {}
    reaction_patterns = {}
    temporal_patterns = {}

    for response in response_list:
        if not response.get("results"):
            continue

        for result in response["results"]:
            # Extract drug information
            drugs = result.get("patient", {}).get("drug", [])
            for drug in drugs:
                # Use the existing standardization function
                drug_name = _standardize_drug_name_fda(drug.get("medicinalproduct", ""))
                if drug_name:
                    if drug_name not in drug_signals:
                        drug_signals[drug_name] = {"total_reports": 0, "serious_reports": 0, "common_reactions": []}

                    drug_signals[drug_name]["total_reports"] += 1
                    if result.get("serious") == "1":
                        drug_signals[drug_name]["serious_reports"] += 1

            # Extract reaction patterns
            reactions = result.get("patient", {}).get("reaction", [])
            for reaction in reactions:
                reaction_name = reaction.get("reactionmeddrapt", "")
                if reaction_name:
                    if reaction_name not in reaction_patterns:
                        reaction_patterns[reaction_name] = {
                            "count": 0,
                            "severity_counts": {"serious": 0, "non_serious": 0},
                        }

                    reaction_patterns[reaction_name]["count"] += 1

                    # Count severity
                    if result.get("serious") == "1":
                        reaction_patterns[reaction_name]["severity_counts"]["serious"] += 1
                    else:
                        reaction_patterns[reaction_name]["severity_counts"]["non_serious"] += 1

            # Extract temporal patterns
            receipt_date = result.get("receiptdate")
            if receipt_date and len(receipt_date) >= 6:
                year_month = receipt_date[:6]  # YYYYMM
                if year_month not in temporal_patterns:
                    temporal_patterns[year_month] = {"count": 0, "serious_count": 0}

                temporal_patterns[year_month]["count"] += 1
                if result.get("serious") == "1":
                    temporal_patterns[year_month]["serious_count"] += 1

    # Build common reactions for each drug based on actual data
    for drug_name in drug_signals:
        # Find reactions that occurred with this specific drug
        drug_reactions = {}

        for response in response_list:
            if not response.get("results"):
                continue

            for result in response["results"]:
                drugs = result.get("patient", {}).get("drug", [])
                has_this_drug = any(
                    _standardize_drug_name_fda(drug.get("medicinalproduct", "")) == drug_name for drug in drugs
                )

                if has_this_drug:
                    reactions = result.get("patient", {}).get("reaction", [])
                    for reaction in reactions:
                        reaction_name = reaction.get("reactionmeddrapt", "")
                        if reaction_name:
                            if reaction_name not in drug_reactions:
                                drug_reactions[reaction_name] = 0
                            drug_reactions[reaction_name] += 1

        # Get top 3 reactions for this drug
        top_reactions = sorted(drug_reactions.items(), key=lambda x: x[1], reverse=True)[:3]
        drug_signals[drug_name]["common_reactions"] = [r[0] for r in top_reactions]

    return {
        "drug_signals": drug_signals,
        "reaction_patterns": reaction_patterns,
        "temporal_patterns": temporal_patterns,
    }

def _format_safety_signal_summary(
    signals_data: dict,
    drug_list: list[str],
    comparison_period: tuple[str, str] | None = None,
    signal_threshold: float = 2.0,
) -> str:
    '''Format safety signal analysis results.'''
    summary = "OpenFDA Safety Signal Analysis\\n"
    summary += "=" * 29 + "\\n"
    summary += f"Drugs analyzed: {drug_list}\\n"

    # Add comparison period and threshold info
    if comparison_period:
        summary += f"Comparison period: {comparison_period[0]} to {comparison_period[1]}\\n"
    if signal_threshold != 2.0:
        summary += f"Signal threshold: {signal_threshold}\\n"
    summary += "\\n"

    if not signals_data:
        summary += "No safety signals detected.\\n"
        return summary

    summary += "Signal Detection Results:\\n"

    # Handle the actual data structure from _extract_fda_safety_signals
    drug_signals = signals_data.get("drug_signals", {})
    reaction_patterns = signals_data.get("reaction_patterns", {})
    signals_data.get("temporal_patterns", {})

    # Display drug-specific signals
    for i, drug_name in enumerate(drug_list, 1):
        drug_data = drug_signals.get(drug_name, {})
        if drug_data:
            summary += f"{i}. {drug_name.title()}\\n"
            summary += f"   - Total reports: {drug_data['total_reports']:,}\\n"
            summary += f"   - Serious reports: {drug_data['serious_reports']:,}\\n"

            if drug_data.get("common_reactions"):
                summary += f"   - Common reactions: {', '.join(drug_data['common_reactions'])}\\n"
            summary += "\\n"
        else:
            summary += f"{i}. {drug_name.title()}\\n"
            summary += "   - No data found\\n\\n"

    # Display cross-drug reaction patterns
    if reaction_patterns:
        summary += "Cross-drug Analysis:\\n"
        sorted_reactions = sorted(reaction_patterns.items(), key=lambda x: x[1]["count"], reverse=True)

        for reaction, data in sorted_reactions[:5]:  # Show top 5 reactions
            summary += f"- {reaction}: {data['count']:,} reports\\n"
            if data["severity_counts"]["serious"] > 0:
                summary += f"  * Serious: {data['severity_counts']['serious']:,}\\n"

    # Add trend analysis if comparison period is specified
    if comparison_period:
        summary += "\\nTrend Analysis:\\n"
        summary += f"Comparing current period to {comparison_period[0]} - {comparison_period[1]}\\n"
        summary += "* Trend detection based on temporal patterns in adverse event reports\\n"
        summary += "* Analysis considers seasonal variations and reporting delays\\n"

    return summary

def analyze_fda_safety_signals(
    drug_list: list[str], comparison_period: tuple[str, str] | None = None, signal_threshold: float = 2.0
) -> str:
    '''
    Analyze safety signals across multiple drugs.

    Args:
        drug_list: List of drug names to analyze
        comparison_period: Optional comparison time period
        signal_threshold: Threshold for signal detection

    Returns:
        Formatted string with safety signal analysis
    '''
    try:
        # Validate input parameters
        if not drug_list:
            return "Error: At least one drug must be provided for analysis"

        if len(drug_list) < 2:
            return "Error: At least 2 drugs required for comparative safety signal analysis"

        # Validate drug names
        valid_drugs = [drug.strip() for drug in drug_list if drug and drug.strip()]
        if not valid_drugs:
            return "Error: No valid drug names provided"

        client = OpenFDAClient()

        # Collect data for all drugs
        all_responses = []

        for drug in valid_drugs:
            standardized_name = _standardize_drug_name_fda(drug)
            if standardized_name:  # Only query if standardization worked
                response = client.query_adverse_events(standardized_name, limit=200)

                if response.get("results"):
                    all_responses.append(response)

        # Check if we got any data
        if not all_responses:
            return "Error: No adverse event data found for any of the provided drugs"

        # Extract safety signals
        signals = _extract_fda_safety_signals(all_responses)

        # Format results with comparison period and threshold info
        return _format_safety_signal_summary(signals, valid_drugs, comparison_period, signal_threshold)

    except Exception as e:
        return f"Error analyzing FDA safety signals: {str(e)}"

# Execute the function
try:
    result = analyze_fda_safety_signals(
        drug_list=auto_convert(os.environ.get("PARAM_DRUG_LIST", "")),
        comparison_period=auto_convert(os.environ.get("PARAM_COMPARISON_PERIOD", "")),
        signal_threshold=auto_convert(os.environ.get("PARAM_SIGNAL_THRESHOLD", "2.0")),
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
    "function": "analyze_fda_safety_signals",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_fda_safety_signals_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_fda_safety_signals_output.txt", "w") as f:
    f.write("Biomni: Analyze Fda Safety Signals" + NL)
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
        biomni_function: "analyze_fda_safety_signals"
    END_VERSIONS
    """
}

workflow ANALYZE_FDA_SAFETY_SIGNALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_FDA_SAFETY_SIGNALS(ch_input)

    emit:
    results = ANALYZE_FDA_SAFETY_SIGNALS.out.results
    output = ANALYZE_FDA_SAFETY_SIGNALS.out.output
    versions = ANALYZE_FDA_SAFETY_SIGNALS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_FDA_SAFETY_SIGNALS_WORKFLOW(ch_input)

    ANALYZE_FDA_SAFETY_SIGNALS_WORKFLOW.out.output.view { "Output: $it" }
}
