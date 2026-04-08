#!/usr/bin/env nextflow
/*
 * pharmacology/find_alternative_drugs_ddinter
 * Find alternative drugs that don't interact with contraindicated drugs.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Find alternatives to aspirin that don't interact with warfarin
params.target_drug = 'aspirin'
params.contraindicated_drugs = '["warfarin", "heparin"]'
params.therapeutic_class = 'analgesic'
params.data_lake_path = null

process FIND_ALTERNATIVE_DRUGS_DDINTER {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_alternative_drugs_ddinter_results.json"), emit: results
    tuple val(meta), path("find_alternative_drugs_ddinter_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TARGET_DRUG="${params.target_drug?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONTRAINDICATED_DRUGS="${params.contraindicated_drugs?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THERAPEUTIC_CLASS="${params.therapeutic_class?.toString()?.replace('"', '\\"') ?: 'null'}"
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

def find_alternative_drugs_ddinter(target_drug, contraindicated_drugs, therapeutic_class=None, data_lake_path=None):
    '''
    Find alternative drugs that don't interact with contraindicated drugs.

    Parameters
    ----------
    target_drug : str
        Drug to find alternatives for
    contraindicated_drugs : list of str
        List of drugs to avoid interactions with
    therapeutic_class : str, optional
        Limit search to specific therapeutic class
    data_lake_path : str, optional
        Path to data lake directory containing DDInter data

    Returns
    -------
    str
        Research log with alternative drug recommendations
    '''
    from datetime import datetime

    # Initialize research log
    log = "Alternative Drug Finder (DDInter)\\n"
    log += "=" * 32 + "\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Handle default data lake path
    if data_lake_path is None:
        data_lake_path = os.path.join(os.path.dirname(__file__), "schema_db")

    log += "Alternative Drug Search Parameters:\\n"
    log += f"- Target drug: {target_drug}\\n"
    log += f"- Contraindicated drugs: {', '.join(contraindicated_drugs)}\\n"
    log += f"- Therapeutic class filter: {therapeutic_class if therapeutic_class else 'All classes'}\\n\\n"

    try:
        # Load DDInter data
        drug_info, interaction_matrix, name_mapping = _load_ddinter_data(data_lake_path)
        log += f"Successfully loaded DDInter database with {len(drug_info)} drugs\\n\\n"

        # Standardize target drug name
        std_target = _standardize_drug_name(target_drug, name_mapping)
        if not std_target:
            log += f"Error: Target drug '{target_drug}' not found in DDInter database\\n"
            return log

        # Standardize contraindicated drug names
        std_contraindicated = []
        missing_contraindicated = []

        for drug in contraindicated_drugs:
            std_drug = _standardize_drug_name(drug, name_mapping)
            if std_drug:
                std_contraindicated.append(std_drug)
            else:
                missing_contraindicated.append(drug)

        if missing_contraindicated:
            log += "Warning: The following contraindicated drugs were not found:\\n"
            for drug in missing_contraindicated:
                log += f"- {drug}\\n"
            log += "\\n"

        # Get target drug information
        target_id = name_mapping[std_target]
        target_info = drug_info.get(target_id, {})
        target_categories = target_info.get("categories", [])

        log += "Target Drug Profile:\\n"
        log += f"- Drug: {target_drug}\\n"
        log += f"- Categories: {', '.join(target_categories)}\\n"
        log += f"- Total interactions: {len(target_info.get('interactions', []))}\\n\\n"

        # Find alternative drugs
        alternatives = []

        for drug_id, drug_data in drug_info.items():
            drug_name = drug_data["name"]
            drug_categories = drug_data.get("categories", [])

            # Skip the target drug itself
            if drug_id == target_id:
                continue

            # Apply therapeutic class filter
            if therapeutic_class:
                if not any(therapeutic_class.lower() in cat.lower() for cat in drug_categories):
                    continue
            else:
                # Look for drugs in similar categories as target
                if not any(cat in target_categories for cat in drug_categories):
                    continue

            # Check if this drug interacts with any contraindicated drugs
            has_contraindicated_interactions = False
            interaction_count = 0
            major_interactions = 0

            std_drug_name = drug_data["standardized_name"]

            for contraindicated in std_contraindicated:
                if std_drug_name in interaction_matrix and contraindicated in interaction_matrix[std_drug_name]:
                    interactions = interaction_matrix[std_drug_name][contraindicated]
                    interaction_count += len(interactions)

                    # Check for major interactions
                    for interaction in interactions:
                        if interaction.get("level") == "Major":
                            major_interactions += 1
                            has_contraindicated_interactions = True
                            break

                    if has_contraindicated_interactions:
                        break

            # Add to alternatives if no major contraindicated interactions
            if not has_contraindicated_interactions:
                alternatives.append(
                    {
                        "name": drug_name,
                        "categories": drug_categories,
                        "interaction_count": interaction_count,
                        "total_interactions": len(drug_data.get("interactions", [])),
                    }
                )

        # Sort alternatives by interaction count (fewer is better)
        alternatives.sort(key=lambda x: x["interaction_count"])

        # Present results
        log += "Alternative Drug Analysis:\\n"
        log += "-" * 25 + "\\n"

        if alternatives:
            log += f"Found {len(alternatives)} potential alternatives:\\n\\n"

            # Show top 10 alternatives
            top_alternatives = alternatives[:10]

            for i, alt in enumerate(top_alternatives, 1):
                log += f"{i}. {alt['name']}\\n"
                log += f"   - Categories: {', '.join(alt['categories'])}\\n"
                log += f"   - Interactions with contraindicated drugs: {alt['interaction_count']}\\n"
                log += f"   - Total known interactions: {alt['total_interactions']}\\n"

                # Risk assessment
                if alt["interaction_count"] == 0:
                    risk = "No known interactions"
                elif alt["interaction_count"] <= 2:
                    risk = "Low interaction risk"
                elif alt["interaction_count"] <= 5:
                    risk = "Moderate interaction risk"
                else:
                    risk = "Higher interaction risk"

                log += f"   - Risk assessment: {risk}\\n\\n"

            if len(alternatives) > 10:
                log += f"... and {len(alternatives) - 10} additional alternatives\\n\\n"
        else:
            log += "No suitable alternatives found in the DDInter database\\n"
            log += "Consider:\\n"
            log += "- Expanding therapeutic class search criteria\\n"
            log += "- Consulting additional drug databases\\n"
            log += "- Seeking specialist pharmacological advice\\n\\n"

        # Recommendations
        log += "Clinical Recommendations:\\n"
        log += "-" * 22 + "\\n"

        if alternatives:
            best_alternative = alternatives[0]
            log += f"- Primary recommendation: {best_alternative['name']}\\n"
            log += "- Rationale: Lowest interaction risk with contraindicated drugs\\n"

            if best_alternative["interaction_count"] == 0:
                log += "- Safety profile: No known interactions with specified drugs\\n"
            else:
                log += f"- Safety profile: {best_alternative['interaction_count']} minor interactions detected\\n"

            log += "- Next steps: Verify therapeutic equivalence and dosing\\n"
            log += "- Monitoring: Standard clinical monitoring recommended\\n"
        else:
            log += "- No direct alternatives identified\\n"
            log += "- Consider non-pharmacological approaches\\n"
            log += "- Consult clinical pharmacist or specialist\\n"
            log += "- Review patient's complete medication profile\\n"

        log += "\\nImportant Notes:\\n"
        log += "- This analysis is based on DDInter 2.0 data only\\n"
        log += "- Always verify therapeutic equivalence before substitution\\n"
        log += "- Consider patient-specific factors (allergies, comorbidities)\\n"
        log += "- Monitor patient response after any medication changes\\n"

    except Exception as e:
        log += f"Error during alternative drug search: {str(e)}\\n"

    return log

# Execute the function
try:
    result = find_alternative_drugs_ddinter(
        target_drug=auto_convert(os.environ.get("PARAM_TARGET_DRUG", "")),
        contraindicated_drugs=auto_convert(os.environ.get("PARAM_CONTRAINDICATED_DRUGS", "")),
        therapeutic_class=auto_convert(os.environ.get("PARAM_THERAPEUTIC_CLASS", "")),
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
    "function": "find_alternative_drugs_ddinter",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_alternative_drugs_ddinter_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_alternative_drugs_ddinter_output.txt", "w") as f:
    f.write("Biomni: Find Alternative Drugs Ddinter" + NL)
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
        biomni_function: "find_alternative_drugs_ddinter"
    END_VERSIONS
    """
}

workflow FIND_ALTERNATIVE_DRUGS_DDINTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_ALTERNATIVE_DRUGS_DDINTER(ch_input)

    emit:
    results = FIND_ALTERNATIVE_DRUGS_DDINTER.out.results
    output = FIND_ALTERNATIVE_DRUGS_DDINTER.out.output
    versions = FIND_ALTERNATIVE_DRUGS_DDINTER.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_ALTERNATIVE_DRUGS_DDINTER_WORKFLOW(ch_input)

    FIND_ALTERNATIVE_DRUGS_DDINTER_WORKFLOW.out.output.view { "Output: $it" }
}
