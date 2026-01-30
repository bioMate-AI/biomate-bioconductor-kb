#!/usr/bin/env nextflow
/*
 * pharmacology/check_drug_combination_safety
 * Analyze safety of a drug combination for potential interactions.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Check safety of common cardiovascular drug combination
params.drug_list = '["aspirin", "warfarin", "metoprolol"]'
params.include_mechanisms = 'True'
params.include_management = 'True'
params.data_lake_path = './schema_db'

process CHECK_DRUG_COMBINATION_SAFETY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("check_drug_combination_safety_results.json"), emit: results
    tuple val(meta), path("check_drug_combination_safety_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DRUG_LIST="${params.drug_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INCLUDE_MECHANISMS="${params.include_mechanisms?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INCLUDE_MANAGEMENT="${params.include_management?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_LAKE_PATH="${params.data_lake_path?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pickle
from difflib import get_close_matches
import pandas as pd
import os
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

def _load_ddinter_data(data_lake_path):
    '''
    Load DDInter datasets from pickle files, processing if needed.

    Parameters
    ----------
    data_lake_path : str
        Path to data lake directory containing DDInter pickle files

    Returns
    -------
    tuple
        (drug_info, interaction_matrix, name_mapping) dictionaries
    '''
    import os
    import pickle

    # Define schema directory (following established pattern)
    schema_dir = os.path.join(os.path.dirname(__file__), "schema_db")

    # Define paths to DDInter pickle files
    drug_info_path = os.path.join(schema_dir, "ddinter_drugs.pkl")
    interaction_path = os.path.join(schema_dir, "ddinter_interactions.pkl")
    mapping_path = os.path.join(schema_dir, "ddinter_name_mapping.pkl")

    # Check if processing is needed (lazy loading pattern)
    pkl_files = [drug_info_path, interaction_path, mapping_path]
    if not all(os.path.exists(f) for f in pkl_files):
        _process_ddinter_data_inline(data_lake_path, schema_dir)

    # Load data
    try:
        with open(drug_info_path, "rb") as f:
            drug_info = pickle.load(f)

        with open(interaction_path, "rb") as f:
            interaction_matrix = pickle.load(f)

        with open(mapping_path, "rb") as f:
            name_mapping = pickle.load(f)

        return drug_info, interaction_matrix, name_mapping

    except Exception as e:
        raise FileNotFoundError(f"Error loading DDInter data: {e}") from e

def _process_ddinter_data_inline(data_lake_path, output_dir):
    '''
    Process DDInter CSV files into standardized pickle files.

    This function processes raw DDInter 2.0 CSV files and creates standardized
    data structures for use in Biomni drug-drug interaction analysis.

    Parameters
    ----------
    data_lake_path : str
        Path to data lake directory containing raw DDInter CSV files
    output_dir : str
        Directory to save processed pickle files
    '''
    import os
    import pickle
    from pathlib import Path

    import pandas as pd

    # Create output directory
    Path(output_dir).mkdir(exist_ok=True)

    # Define CSV files to process
    csv_files = [
        "ddinter_alimentary_tract_metabolism.csv",
        "ddinter_antineoplastic.csv",
        "ddinter_antiparasitic.csv",
        "ddinter_blood_organs.csv",
        "ddinter_dermatological.csv",
        "ddinter_hormonal.csv",
        "ddinter_respiratory.csv",
        "ddinter_various.csv",
    ]

    # Load and combine all CSV files
    dataframes = []
    for csv_file in csv_files:
        file_path = os.path.join(data_lake_path, csv_file)
        if os.path.exists(file_path):
            df = pd.read_csv(file_path)
            # Add source category
            category = csv_file.replace("ddinter_", "").replace(".csv", "")
            df["category"] = category
            dataframes.append(df)

    if not dataframes:
        raise FileNotFoundError("No DDInter CSV files found in data lake")

    # Process data
    drug_info = _build_drug_registry_inline(dataframes)
    interaction_matrix = _create_interaction_matrix_inline(dataframes)
    name_mapping = _create_name_mapping_inline(drug_info)

    # Save processed data
    with open(os.path.join(output_dir, "ddinter_drugs.pkl"), "wb") as f:
        pickle.dump(drug_info, f)

    with open(os.path.join(output_dir, "ddinter_interactions.pkl"), "wb") as f:
        pickle.dump(interaction_matrix, f)

    with open(os.path.join(output_dir, "ddinter_name_mapping.pkl"), "wb") as f:
        pickle.dump(name_mapping, f)

    # Generate and save statistics
    stats = _generate_ddinter_statistics_inline(drug_info, interaction_matrix)
    with open(os.path.join(output_dir, "ddinter_statistics.pkl"), "wb") as f:
        pickle.dump(stats, f)

def _standardize_drug_name_processing(drug_name):
    '''Standardize drug names for consistent matching during processing.'''
    import pandas as pd

    if pd.isna(drug_name):
        return ""

    # Convert to lowercase and strip whitespace
    standardized = str(drug_name).strip().lower()

    # Remove common suffixes and prefixes
    standardized = standardized.replace(" hydrochloride", "")
    standardized = standardized.replace(" sulfate", "")
    standardized = standardized.replace(" sodium", "")
    standardized = standardized.replace(" potassium", "")
    standardized = standardized.replace(" calcium", "")
    standardized = standardized.replace(" magnesium", "")

    return standardized

def _build_drug_registry_inline(dataframes):
    '''Build comprehensive drug registry from all interactions.'''

    drug_registry = {}

    for df in dataframes:
        for _, row in df.iterrows():
            drug_a_id = row["DDInterID_A"]
            drug_a_name = row["Drug_A"]
            drug_b_id = row["DDInterID_B"]
            drug_b_name = row["Drug_B"]

            # Add Drug A
            if drug_a_id not in drug_registry:
                drug_registry[drug_a_id] = {
                    "name": drug_a_name,
                    "standardized_name": _standardize_drug_name_processing(drug_a_name),
                    "categories": set(),
                    "interactions": set(),
                }
            drug_registry[drug_a_id]["categories"].add(row["category"])

            # Add Drug B
            if drug_b_id not in drug_registry:
                drug_registry[drug_b_id] = {
                    "name": drug_b_name,
                    "standardized_name": _standardize_drug_name_processing(drug_b_name),
                    "categories": set(),
                    "interactions": set(),
                }
            drug_registry[drug_b_id]["categories"].add(row["category"])

            # Record interactions
            drug_registry[drug_a_id]["interactions"].add(drug_b_id)
            drug_registry[drug_b_id]["interactions"].add(drug_a_id)

    # Convert sets to lists for pickle serialization
    for drug_id in drug_registry:
        drug_registry[drug_id]["categories"] = list(drug_registry[drug_id]["categories"])
        drug_registry[drug_id]["interactions"] = list(drug_registry[drug_id]["interactions"])

    return drug_registry

def _create_interaction_matrix_inline(dataframes):
    '''Create interaction matrix for fast lookups using standardized drug names.'''
    from collections import defaultdict

    import pandas as pd

    combined_df = pd.concat(dataframes, ignore_index=True)
    interaction_matrix = defaultdict(lambda: defaultdict(list))

    # Create bidirectional interaction matrix using standardized names
    for _, row in combined_df.iterrows():
        drug_a_std = _standardize_drug_name_processing(row["Drug_A"])
        drug_b_std = _standardize_drug_name_processing(row["Drug_B"])
        level = row["Level"]
        category = row["category"]

        interaction_data = {
            "level": level,
            "category": category,
            "drug_a_id": row["DDInterID_A"],
            "drug_b_id": row["DDInterID_B"],
            "drug_a_name": row["Drug_A"],
            "drug_b_name": row["Drug_B"],
        }

        # Add both directions using standardized names as keys
        interaction_matrix[drug_a_std][drug_b_std].append(interaction_data)
        interaction_matrix[drug_b_std][drug_a_std].append(interaction_data)

    # Convert to regular dict for pickle
    interaction_matrix = dict(interaction_matrix)
    for drug in interaction_matrix:
        interaction_matrix[drug] = dict(interaction_matrix[drug])

    return interaction_matrix

def _create_name_mapping_inline(drug_info):
    '''Create drug name to ID mapping for fuzzy matching.'''
    name_mapping = {}

    for drug_id, drug_data in drug_info.items():
        original_name = drug_data["name"]
        standardized_name = drug_data["standardized_name"]

        # Map both original and standardized names
        name_mapping[original_name.lower()] = drug_id
        name_mapping[standardized_name] = drug_id

    return name_mapping

def _generate_ddinter_statistics_inline(drug_info, interaction_matrix):
    '''Generate statistics about the processed data.'''
    from collections import defaultdict

    stats = {
        "total_drugs": len(drug_info),
        "total_interactions": 0,
        "interaction_levels": defaultdict(int),
        "drug_categories": defaultdict(int),
        "most_connected_drugs": [],
    }

    # Count interactions and levels
    for drug_a in interaction_matrix:
        for drug_b in interaction_matrix[drug_a]:
            interactions = interaction_matrix[drug_a][drug_b]
            stats["total_interactions"] += len(interactions)

            for interaction in interactions:
                stats["interaction_levels"][interaction["level"]] += 1

    # Count drug categories
    for drug_data in drug_info.values():
        for category in drug_data["categories"]:
            stats["drug_categories"][category] += 1

    # Find most connected drugs
    connection_counts = []
    for drug_id, drug_data in drug_info.items():
        connection_counts.append(
            {"drug_id": drug_id, "name": drug_data["name"], "connections": len(drug_data["interactions"])}
        )

    connection_counts.sort(key=lambda x: x["connections"], reverse=True)
    stats["most_connected_drugs"] = connection_counts[:10]

    return stats

def _standardize_drug_name(drug_name, name_mapping):
    '''
    Standardize drug names using fuzzy matching against DDInter database.

    Parameters
    ----------
    drug_name : str
        Original drug name
    name_mapping : dict
        Drug name to ID mapping dictionary

    Returns
    -------
    str or None
        Standardized drug name or None if not found
    '''
    from difflib import get_close_matches

    # Direct match
    if drug_name.lower() in name_mapping:
        return drug_name.lower()

    # Fuzzy match
    matches = get_close_matches(drug_name.lower(), name_mapping.keys(), n=1, cutoff=0.8)
    if matches:
        return matches[0]

    return None

def _format_interaction_result(interaction_data, drug_name_a, drug_name_b, include_mechanisms=True):
    '''
    Format interaction results for research log.

    Parameters
    ----------
    interaction_data : list
        List of interaction data dictionaries
    drug_name_a : str
        First drug name
    drug_name_b : str
        Second drug name
    include_mechanisms : bool
        Whether to include detailed mechanism information

    Returns
    -------
    str
        Formatted interaction description
    '''
    if not interaction_data:
        return f"No interactions found between {drug_name_a} and {drug_name_b}"

    result = f"Interaction between {drug_name_a} and {drug_name_b}:\\n"

    for i, interaction in enumerate(interaction_data, 1):
        level = interaction.get("level", "Unknown")
        category = interaction.get("category", "Unknown")

        result += f"  {i}. Severity: {level}\\n"
        result += f"     Category: {category.replace('_', ' ').title()}\\n"

        if include_mechanisms:
            result += f"     Clinical significance: {level} interaction requiring appropriate monitoring\\n"

    return result

def check_drug_combination_safety(drug_list, include_mechanisms=True, include_management=True, data_lake_path=None):
    '''
    Analyze safety of a drug combination for potential interactions.

    Parameters
    ----------
    drug_list : list of str
        List of drugs to analyze for combination safety
    include_mechanisms : bool, default True
        Include interaction mechanism descriptions
    include_management : bool, default True
        Include management recommendations
    data_lake_path : str, optional
        Path to data lake directory containing DDInter data

    Returns
    -------
    str
        Research log with safety analysis and recommendations
    '''
    from datetime import datetime

    # Initialize research log
    log = "Drug Combination Safety Analysis\\n"
    log += "=" * 35 + "\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Handle default data lake path
    if data_lake_path is None:
        data_lake_path = os.path.join(os.path.dirname(__file__), "schema_db")

    log += "Safety Analysis Parameters:\\n"
    log += f"- Drug combination: {', '.join(drug_list)}\\n"
    log += f"- Include mechanisms: {include_mechanisms}\\n"
    log += f"- Include management: {include_management}\\n\\n"

    try:
        # Load DDInter data
        drug_info, interaction_matrix, name_mapping = _load_ddinter_data(data_lake_path)
        log += "Successfully loaded DDInter database\\n\\n"

        # Standardize drug names
        standardized_drugs = []
        missing_drugs = []

        for drug in drug_list:
            standardized = _standardize_drug_name(drug, name_mapping)
            if standardized:
                standardized_drugs.append(standardized)
            else:
                missing_drugs.append(drug)

        if missing_drugs:
            log += "Warning: The following drugs were not found in DDInter database:\\n"
            for drug in missing_drugs:
                log += f"- {drug}\\n"
            log += "\\n"

        if len(standardized_drugs) < 2:
            log += "Error: At least 2 valid drugs required for combination analysis\\n"
            return log

        # Analyze all pairwise interactions
        interactions_found = []
        major_interactions = 0
        moderate_interactions = 0
        minor_interactions = 0

        for i, drug_a in enumerate(standardized_drugs):
            for j, drug_b in enumerate(standardized_drugs):
                if i >= j:  # Avoid duplicate pairs
                    continue

                if drug_a in interaction_matrix and drug_b in interaction_matrix[drug_a]:
                    interactions = interaction_matrix[drug_a][drug_b]

                    for interaction in interactions:
                        level = interaction.get("level", "Unknown")
                        if level == "Major":
                            major_interactions += 1
                        elif level == "Moderate":
                            moderate_interactions += 1
                        elif level == "Minor":
                            minor_interactions += 1

                    interactions_found.append({"drug_a": drug_a, "drug_b": drug_b, "interactions": interactions})

        # Overall safety assessment
        log += "Overall Safety Assessment:\\n"

        safety_score = 100
        safety_level = "Safe"

        if major_interactions > 0:
            safety_score -= major_interactions * 30
            safety_level = "High Risk"
        elif moderate_interactions > 2:
            safety_score -= moderate_interactions * 15
            safety_level = "Moderate Risk"
        elif moderate_interactions > 0:
            safety_score -= moderate_interactions * 10
            safety_level = "Low to Moderate Risk"
        elif minor_interactions > 0:
            safety_score -= minor_interactions * 5
            safety_level = "Low Risk"

        safety_score = max(0, safety_score)

        log += f"- Safety Level: {safety_level}\\n"
        log += f"- Safety Score: {safety_score}/100\\n"
        log += f"- Major interactions: {major_interactions}\\n"
        log += f"- Moderate interactions: {moderate_interactions}\\n"
        log += f"- Minor interactions: {minor_interactions}\\n\\n"

        # Detailed interaction analysis
        if interactions_found:
            log += "Detailed Interaction Analysis:\\n"
            log += "-" * 30 + "\\n"

            for pair in interactions_found:
                log += _format_interaction_result(
                    pair["interactions"],
                    pair["drug_a"].title(),
                    pair["drug_b"].title(),
                    include_mechanisms=include_mechanisms,
                )
                log += "\\n"

        # Clinical recommendations
        log += "Clinical Recommendations:\\n"
        log += "-" * 25 + "\\n"

        if major_interactions > 0:
            log += "- CONTRAINDICATED: This combination contains major interactions\\n"
            log += "- Consider alternative medications or consult specialist\\n"
            log += "- If combination is necessary, intensive monitoring required\\n"
        elif moderate_interactions > 2:
            log += "- CAUTION: Multiple moderate interactions detected\\n"
            log += "- Monitor patient closely for adverse effects\\n"
            log += "- Consider dose adjustments or alternative agents\\n"
        elif moderate_interactions > 0:
            log += "- MONITOR: Moderate interactions present\\n"
            log += "- Regular patient monitoring recommended\\n"
            log += "- Be aware of potential side effects\\n"
        elif minor_interactions > 0:
            log += "- AWARENESS: Minor interactions detected\\n"
            log += "- Standard monitoring sufficient\\n"
            log += "- Educate patient about potential minor effects\\n"
        else:
            log += "- SAFE: No significant interactions detected\\n"
            log += "- Standard clinical monitoring appropriate\\n"

        if include_management:
            log += "\\nGeneral Management Strategies:\\n"
            log += "- Separate administration times when possible\\n"
            log += "- Monitor for signs of toxicity or reduced efficacy\\n"
            log += "- Consider therapeutic drug monitoring if available\\n"
            log += "- Educate patient about potential interaction symptoms\\n"

    except Exception as e:
        log += f"Error during safety analysis: {str(e)}\\n"

    return log

# Execute the function
try:
    result = check_drug_combination_safety(
        drug_list=auto_convert(os.environ.get("PARAM_DRUG_LIST", "")),
        include_mechanisms=auto_convert(os.environ.get("PARAM_INCLUDE_MECHANISMS", "True")),
        include_management=auto_convert(os.environ.get("PARAM_INCLUDE_MANAGEMENT", "True")),
        data_lake_path=auto_convert(os.environ.get("PARAM_DATA_LAKE_PATH", "")),
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
    "function": "check_drug_combination_safety",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("check_drug_combination_safety_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("check_drug_combination_safety_output.txt", "w") as f:
    f.write("Biomni: Check Drug Combination Safety" + NL)
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
        biomni_function: "check_drug_combination_safety"
    END_VERSIONS
    """
}

workflow CHECK_DRUG_COMBINATION_SAFETY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CHECK_DRUG_COMBINATION_SAFETY(ch_input)

    emit:
    results = CHECK_DRUG_COMBINATION_SAFETY.out.results
    output = CHECK_DRUG_COMBINATION_SAFETY.out.output
    versions = CHECK_DRUG_COMBINATION_SAFETY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CHECK_DRUG_COMBINATION_SAFETY_WORKFLOW(ch_input)

    CHECK_DRUG_COMBINATION_SAFETY_WORKFLOW.out.output.view { "Output: $it" }
}
