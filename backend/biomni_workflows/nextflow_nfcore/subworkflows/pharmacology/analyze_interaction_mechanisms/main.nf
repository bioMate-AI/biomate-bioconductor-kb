#!/usr/bin/env nextflow
/*
 * pharmacology/analyze_interaction_mechanisms
 * Analyze interaction mechanisms between two specific drugs.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Aspirin-Warfarin interaction (well-documented clinically significant interaction)
params.drug_pair = '["Aspirin", "Warfarin"]'
params.detailed_analysis = 'True'
params.data_lake_path = './schema_db'

process ANALYZE_INTERACTION_MECHANISMS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_interaction_mechanisms_results.json"), emit: results
    tuple val(meta), path("analyze_interaction_mechanisms_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DRUG_PAIR="${params.drug_pair?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DETAILED_ANALYSIS="${params.detailed_analysis?.toString()?.replace('"', '\\"') ?: 'null'}"
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

def analyze_interaction_mechanisms(drug_pair, detailed_analysis=True, data_lake_path=None):
    '''
    Analyze interaction mechanisms between two specific drugs.

    Parameters
    ----------
    drug_pair : tuple of str
        Pair of drug names to analyze (drug1, drug2)
    detailed_analysis : bool, default True
        Include detailed mechanistic information
    data_lake_path : str, optional
        Path to data lake directory containing DDInter data

    Returns
    -------
    str
        Research log with mechanism analysis
    '''
    from datetime import datetime

    # Initialize research log
    log = "Drug Interaction Mechanism Analysis\\n"
    log += "=" * 37 + "\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Handle default data lake path
    if data_lake_path is None:
        data_lake_path = os.path.join(os.path.dirname(__file__), "schema_db")

    drug_a, drug_b = drug_pair
    log += "Mechanism Analysis Parameters:\\n"
    log += f"- Drug A: {drug_a}\\n"
    log += f"- Drug B: {drug_b}\\n"
    log += f"- Detailed analysis: {detailed_analysis}\\n\\n"

    try:
        # Load DDInter data
        drug_info, interaction_matrix, name_mapping = _load_ddinter_data(data_lake_path)
        log += "Successfully loaded DDInter database\\n\\n"

        # Standardize drug names
        std_drug_a = _standardize_drug_name(drug_a, name_mapping)
        std_drug_b = _standardize_drug_name(drug_b, name_mapping)

        if not std_drug_a:
            log += f"Error: Drug '{drug_a}' not found in DDInter database\\n"
            return log
        if not std_drug_b:
            log += f"Error: Drug '{drug_b}' not found in DDInter database\\n"
            return log

        # Query interactions
        interactions = []
        if std_drug_a in interaction_matrix and std_drug_b in interaction_matrix[std_drug_a]:
            interactions = interaction_matrix[std_drug_a][std_drug_b]

        if not interactions:
            log += f"No interactions found between {drug_a} and {drug_b}\\n"
            return log

        # Get drug information
        drug_a_id = name_mapping[std_drug_a]
        drug_b_id = name_mapping[std_drug_b]
        drug_a_info = drug_info.get(drug_a_id, {})
        drug_b_info = drug_info.get(drug_b_id, {})

        log += "Drug Profile Analysis:\\n"
        log += "-" * 20 + "\\n"
        log += f"{drug_a.title()}:\\n"
        log += f"- Categories: {', '.join(drug_a_info.get('categories', ['Unknown']))}\\n"
        log += f"- Total known interactions: {len(drug_a_info.get('interactions', []))}\\n\\n"

        log += f"{drug_b.title()}:\\n"
        log += f"- Categories: {', '.join(drug_b_info.get('categories', ['Unknown']))}\\n"
        log += f"- Total known interactions: {len(drug_b_info.get('interactions', []))}\\n\\n"

        # Analyze interaction mechanisms
        log += "Interaction Mechanism Analysis:\\n"
        log += "-" * 30 + "\\n"

        for i, interaction in enumerate(interactions, 1):
            level = interaction.get("level", "Unknown")
            category = interaction.get("category", "Unknown")

            log += f"Interaction {i}:\\n"
            log += f"- Severity: {level}\\n"
            log += f"- Category: {category.replace('_', ' ').title()}\\n"

            if detailed_analysis:
                # Provide mechanism insights based on severity and category
                if level == "Major":
                    log += "- Clinical Impact: High risk interaction requiring immediate attention\\n"
                    log += "- Mechanism: Likely involves significant pharmacokinetic or pharmacodynamic effects\\n"
                    log += "- Management: Avoid combination or use with extreme caution\\n"
                elif level == "Moderate":
                    log += "- Clinical Impact: Moderate risk requiring monitoring\\n"
                    log += "- Mechanism: May involve enzyme induction/inhibition or receptor competition\\n"
                    log += "- Management: Monitor closely, consider dose adjustment\\n"
                elif level == "Minor":
                    log += "- Clinical Impact: Low risk, usually manageable\\n"
                    log += "- Mechanism: Minor pharmacokinetic or pharmacodynamic effects\\n"
                    log += "- Management: Standard monitoring sufficient\\n"

                # Category-specific mechanism insights
                category_mechanisms = {
                    "alimentary_tract_metabolism": "Gastrointestinal absorption or metabolic interactions",
                    "antineoplastic": "Bone marrow suppression or tumor resistance mechanisms",
                    "blood_organs": "Hematological effects or coagulation pathway interactions",
                    "hormonal": "Endocrine system interactions or hormone receptor effects",
                    "respiratory": "Pulmonary function or bronchodilation interactions",
                    "dermatological": "Skin absorption or topical application interactions",
                    "antiparasitic": "Antimicrobial resistance or metabolic pathway interactions",
                    "various": "Multiple potential interaction pathways",
                }

                mechanism = category_mechanisms.get(category, "Unknown mechanism")
                log += f"- Category-specific mechanism: {mechanism}\\n"

            log += "\\n"

        # Summary and recommendations
        log += "Summary and Recommendations:\\n"
        log += "-" * 28 + "\\n"

        severity_counts = {}
        for interaction in interactions:
            level = interaction.get("level", "Unknown")
            severity_counts[level] = severity_counts.get(level, 0) + 1

        log += f"- Total interactions analyzed: {len(interactions)}\\n"
        log += f"- Severity distribution: {dict(severity_counts)}\\n"

        # Overall recommendation
        if any(int_data.get("level") == "Major" for int_data in interactions):
            log += "- Overall recommendation: AVOID - Major interaction detected\\n"
            log += "- Consider alternative medications\\n"
        elif any(int_data.get("level") == "Moderate" for int_data in interactions):
            log += "- Overall recommendation: MONITOR - Moderate interaction present\\n"
            log += "- Close patient monitoring required\\n"
        else:
            log += "- Overall recommendation: AWARENESS - Minor interactions only\\n"
            log += "- Standard monitoring appropriate\\n"

        if detailed_analysis:
            log += "\\nMechanistic Considerations:\\n"
            log += f"- Monitor for additive effects in the {category.replace('_', ' ')} system\\n"
            log += "- Consider potential for altered drug metabolism\\n"
            log += "- Be aware of possible changes in drug efficacy or toxicity\\n"
            log += "- Timing of administration may be important\\n"

    except Exception as e:
        log += f"Error during mechanism analysis: {str(e)}\\n"

    return log

# Execute the function
try:
    result = analyze_interaction_mechanisms(
        drug_pair=auto_convert(os.environ.get("PARAM_DRUG_PAIR", "")),
        detailed_analysis=auto_convert(os.environ.get("PARAM_DETAILED_ANALYSIS", "True")),
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
    "function": "analyze_interaction_mechanisms",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_interaction_mechanisms_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_interaction_mechanisms_output.txt", "w") as f:
    f.write("Biomni: Analyze Interaction Mechanisms" + NL)
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
        biomni_function: "analyze_interaction_mechanisms"
    END_VERSIONS
    """
}

workflow ANALYZE_INTERACTION_MECHANISMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_INTERACTION_MECHANISMS(ch_input)

    emit:
    results = ANALYZE_INTERACTION_MECHANISMS.out.results
    output = ANALYZE_INTERACTION_MECHANISMS.out.output
    versions = ANALYZE_INTERACTION_MECHANISMS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_INTERACTION_MECHANISMS_WORKFLOW(ch_input)

    ANALYZE_INTERACTION_MECHANISMS_WORKFLOW.out.output.view { "Output: $it" }
}
