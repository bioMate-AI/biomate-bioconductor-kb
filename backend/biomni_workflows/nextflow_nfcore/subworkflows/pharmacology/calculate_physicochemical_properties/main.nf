#!/usr/bin/env nextflow
/*
 * pharmacology/calculate_physicochemical_properties
 * Calculate key physicochemical properties of a drug candidate molecule.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Aspirin SMILES for physicochemical property calculation
params.smiles_string = 'CC(=O)OC1=CC=CC=C1C(=O)O'

process CALCULATE_PHYSICOCHEMICAL_PROPERTIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("calculate_physicochemical_properties_results.json"), emit: results
    tuple val(meta), path("calculate_physicochemical_properties_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SMILES_STRING="${params.smiles_string?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def calculate_physicochemical_properties(smiles_string):
    '''Calculate key physicochemical properties of a drug candidate molecule.

    Parameters
    ----------
    smiles_string : str
        The molecular structure in SMILES format

    Returns
    -------
    str
        A research log summarizing the calculated physicochemical properties and
        indicating where the detailed results are saved

    '''
    import csv
    import os

    from rdkit import Chem
    from rdkit.Chem import Crippen, Descriptors, Lipinski
    from rdkit.Chem.MolStandardize import rdMolStandardize

    # Create RDKit molecule from SMILES
    try:
        mol = Chem.MolFromSmiles(smiles_string)
        if mol is None:
            return "ERROR: Invalid SMILES string provided."
    except Exception as e:
        return f"ERROR: Failed to process SMILES string: {str(e)}"

    # Calculate basic properties
    properties = {
        "SMILES": smiles_string,
        "Molecular Weight": round(Descriptors.MolWt(mol), 2),
        "cLogP": round(Descriptors.MolLogP(mol), 2),
        "TPSA": round(Descriptors.TPSA(mol), 2),
        "H-Bond Donors": Lipinski.NumHDonors(mol),
        "H-Bond Acceptors": Lipinski.NumHAcceptors(mol),
        "Rotatable Bonds": Descriptors.NumRotatableBonds(mol),
        "Heavy Atoms": mol.GetNumHeavyAtoms(),
        "Ring Count": Descriptors.RingCount(mol),
    }

    # Estimate pKa (simplified approach - in practice would use specialized tools)
    # This is a simplification as accurate pKa prediction requires specialized tools
    uncharger = rdMolStandardize.Uncharger()
    uncharger.uncharge(mol)
    acidic_groups = sum(
        1
        for atom in mol.GetAtoms()
        if atom.GetSymbol() == "O"
        and any(neigh.GetSymbol() == "C" and neigh.GetDegree() == 3 for neigh in atom.GetNeighbors())
    )
    basic_groups = sum(1 for atom in mol.GetAtoms() if atom.GetSymbol() == "N" and atom.GetDegree() < 4)
    properties["Estimated Acidic Groups"] = acidic_groups
    properties["Estimated Basic Groups"] = basic_groups

    # Calculate drug-likeness score (using Crippen approach)
    properties["Drug-likeness Score"] = round(Crippen.MolMR(mol), 2)

    # Calculate logD (simplified as logP - pKa adjustment would need specialized tools)
    properties["Estimated logD7.4"] = properties["cLogP"]

    # Save results to CSV
    csv_filename = "physicochemical_properties.csv"
    with open(csv_filename, "w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Property", "Value"])
        for prop, value in properties.items():
            writer.writerow([prop, value])

    # Generate research log
    log = f'''Physicochemical Property Calculation Research Log:

Analyzed compound with SMILES: {smiles_string}

Key properties:
- Molecular Weight: {properties["Molecular Weight"]} g/mol
- cLogP: {properties["cLogP"]}
- Topological Polar Surface Area: {properties["TPSA"]} Å²
- H-Bond Donors: {properties["H-Bond Donors"]}
- H-Bond Acceptors: {properties["H-Bond Acceptors"]}
- Rotatable Bonds: {properties["Rotatable Bonds"]}
- Estimated logD (at pH 7.4): {properties["Estimated logD7.4"]}
- Estimated Acidic Groups: {properties["Estimated Acidic Groups"]}
- Estimated Basic Groups: {properties["Estimated Basic Groups"]}

Complete results saved to: {os.path.abspath(csv_filename)}
'''

    return log

# Execute the function
try:
    result = calculate_physicochemical_properties(
        smiles_string=auto_convert(os.environ.get("PARAM_SMILES_STRING", "")),
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
    "function": "calculate_physicochemical_properties",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("calculate_physicochemical_properties_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("calculate_physicochemical_properties_output.txt", "w") as f:
    f.write("Biomni: Calculate Physicochemical Properties" + NL)
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
        biomni_function: "calculate_physicochemical_properties"
    END_VERSIONS
    """
}

workflow CALCULATE_PHYSICOCHEMICAL_PROPERTIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CALCULATE_PHYSICOCHEMICAL_PROPERTIES(ch_input)

    emit:
    results = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.results
    output = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.output
    versions = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CALCULATE_PHYSICOCHEMICAL_PROPERTIES_WORKFLOW(ch_input)

    CALCULATE_PHYSICOCHEMICAL_PROPERTIES_WORKFLOW.out.output.view { "Output: $it" }
}
