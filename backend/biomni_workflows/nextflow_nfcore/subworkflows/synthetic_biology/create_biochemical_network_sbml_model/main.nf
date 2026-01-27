#!/usr/bin/env nextflow
/*
 * synthetic_biology/create_biochemical_network_sbml_model
 * Generate a mathematical model of a biochemical network in SBML format.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Simple enzymatic reaction network (A + E <-> AE -> P + E)
params.reaction_network = '[{"id": "binding", "name": "Substrate Binding", "reactants": {"A": 1, "E": 1}, "products": {"AE": 1}, "reversible": true}, {"id": "catalysis", "name": "Catalysis", "reactants": {"AE": 1}, "products": {"P": 1, "E": 1}, "reversible": false}]'
params.kinetic_parameters = '{"binding": {"law_type": "mass_action", "parameters": {"k_on": 0.1, "k_off": 0.01}}, "catalysis": {"law_type": "mass_action", "parameters": {"k_cat": 0.5}}}'
params.output_file = 'biochemical_model.xml'

process CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_biochemical_network_sbml_model_results.json"), emit: results
    tuple val(meta), path("create_biochemical_network_sbml_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_REACTION_NETWORK="${params.reaction_network?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KINETIC_PARAMETERS="${params.kinetic_parameters?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def create_biochemical_network_sbml_model(reaction_network, kinetic_parameters, output_file="biochemical_model.xml"):
    '''Generate a mathematical model of a biochemical network in SBML format.

    Parameters
    ----------
    reaction_network : list of dict
        List of dictionaries, each representing a reaction with keys:
        - 'id': Reaction identifier
        - 'name': Reaction name
        - 'reactants': Dict of reactant species IDs and their stoichiometry
        - 'products': Dict of product species IDs and their stoichiometry
        - 'reversible': Boolean indicating if reaction is reversible

    kinetic_parameters : dict
        Dictionary mapping reaction IDs to their kinetic law parameters.
        Each entry should contain:
        - 'law_type': Type of kinetic law (e.g., 'mass_action', 'michaelis_menten')
        - 'parameters': Dict of parameter names and values

    output_file : str, optional
        File path to save the SBML model (default: "biochemical_model.xml")

    Returns
    -------
    str
        Research log summarizing the model creation process

    '''
    import os

    import libsbml

    log = "# Biochemical Network SBML Model Creation Log\\n\\n"

    # Step 1: Create an SBML document
    log += "## Step 1: Creating SBML document\\n"
    sbml_ns = libsbml.SBMLNamespaces(3, 2)  # SBML Level 3 Version 2
    document = libsbml.SBMLDocument(sbml_ns)
    model = document.createModel()
    model.setId("biochemical_network_model")
    model.setName("Biochemical Network Model")
    log += "- Created SBML Level 3 Version 2 document\\n"
    log += "- Created model with ID 'biochemical_network_model'\\n\\n"

    # Step 2: Create default compartment
    log += "## Step 2: Creating default compartment\\n"
    compartment = model.createCompartment()
    compartment.setId("default")
    compartment.setConstant(True)
    compartment.setSize(1.0)
    compartment.setSpatialDimensions(3)
    log += "- Created default compartment\\n\\n"

    # Step 3: Create species
    log += "## Step 3: Creating species\\n"
    species_set = set()

    # Collect all unique species from reactions
    for reaction in reaction_network:
        for species_id in list(reaction["reactants"].keys()) + list(reaction["products"].keys()):
            species_set.add(species_id)

    # Create species in the model
    for species_id in species_set:
        species = model.createSpecies()
        species.setId(species_id)
        species.setCompartment("default")
        species.setInitialConcentration(0.0)  # Default initial concentration
        species.setHasOnlySubstanceUnits(False)
        species.setBoundaryCondition(False)
        species.setConstant(False)
        log += f"- Created species '{species_id}'\\n"
    log += "\\n"

    # Step 4: Create reactions
    log += "## Step 4: Creating reactions and kinetic laws\\n"
    for reaction_data in reaction_network:
        reaction = model.createReaction()
        reaction.setId(reaction_data["id"])
        reaction.setName(reaction_data["name"])
        reaction.setReversible(reaction_data["reversible"])
        reaction.setFast(False)

        # Add reactants
        for reactant_id, stoichiometry in reaction_data["reactants"].items():
            species_ref = reaction.createReactant()
            species_ref.setSpecies(reactant_id)
            species_ref.setStoichiometry(stoichiometry)
            species_ref.setConstant(True)

        # Add products
        for product_id, stoichiometry in reaction_data["products"].items():
            species_ref = reaction.createProduct()
            species_ref.setSpecies(product_id)
            species_ref.setStoichiometry(stoichiometry)
            species_ref.setConstant(True)

        # Create kinetic law
        if reaction_data["id"] in kinetic_parameters:
            kinetic_data = kinetic_parameters[reaction_data["id"]]
            kinetic_law = reaction.createKineticLaw()

            # Add parameters to kinetic law
            for param_name, param_value in kinetic_data["parameters"].items():
                parameter = kinetic_law.createParameter()
                parameter.setId(param_name)
                parameter.setValue(param_value)

            # Set the appropriate formula based on the law type
            if kinetic_data["law_type"] == "mass_action":
                # Simple mass action kinetics
                reactants_formula = " * ".join([f"{reactant_id}" for reactant_id in reaction_data["reactants"]])
                formula = f"k * {reactants_formula}" if reactants_formula else "k"
                kinetic_law.setMath(libsbml.parseL3Formula(formula))
            elif kinetic_data["law_type"] == "michaelis_menten":
                # Michaelis-Menten kinetics (assuming single substrate)
                substrate = list(reaction_data["reactants"].keys())[0] if reaction_data["reactants"] else "S"
                formula = f"Vmax * {substrate} / (Km + {substrate})"
                kinetic_law.setMath(libsbml.parseL3Formula(formula))
            # Custom formula provided in the parameters
            elif "formula" in kinetic_data:
                kinetic_law.setMath(libsbml.parseL3Formula(kinetic_data["formula"]))

        log += f"- Created reaction '{reaction_data['id']}' ({reaction_data['name']})\\n"
        if reaction_data["id"] in kinetic_parameters:
            log += f"  - Added kinetic law of type '{kinetic_parameters[reaction_data['id']]['law_type']}'\\n"
    log += "\\n"

    # Step 5: Validate the model
    log += "## Step 5: Validating the SBML model\\n"
    document.setConsistencyChecks(libsbml.LIBSBML_CAT_UNITS_CONSISTENCY, False)
    consistent = document.checkConsistency()
    if consistent == 0:
        log += "- Model passed consistency check\\n"
    else:
        log += "- Model has consistency issues:\\n"
        for i in range(document.getNumErrors()):
            error = document.getError(i)
            log += f"  - {error.getMessage()}\\n"
    log += "\\n"

    # Step 6: Write model to file
    log += "## Step 6: Saving the SBML model\\n"
    libsbml.writeSBMLToFile(document, output_file)
    log += f"- Model saved to '{os.path.abspath(output_file)}'\\n\\n"

    # Step 7: Summary
    log += "## Summary\\n"
    log += f"- Created SBML model with {len(species_set)} species and {len(reaction_network)} reactions\\n"
    log += f"- Model saved as '{output_file}'\\n"

    return log

# Execute the function
try:
    result = create_biochemical_network_sbml_model(
        reaction_network=auto_convert(os.environ.get("PARAM_REACTION_NETWORK", "")),
        kinetic_parameters=auto_convert(os.environ.get("PARAM_KINETIC_PARAMETERS", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "biochemical_model.xml")),
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
    "function": "create_biochemical_network_sbml_model",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_biochemical_network_sbml_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_biochemical_network_sbml_model_output.txt", "w") as f:
    f.write("Biomni: Create Biochemical Network Sbml Model" + NL)
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
        biomni_function: "create_biochemical_network_sbml_model"
    END_VERSIONS
    """
}

workflow CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL(ch_input)

    emit:
    results = CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL.out.results
    output = CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL.out.output
    versions = CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL_WORKFLOW(ch_input)

    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
