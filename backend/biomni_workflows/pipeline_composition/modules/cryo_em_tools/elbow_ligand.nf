/*
 * BioMate -- eLBOW / GRADE CIF restraint generation
 *
 * ELBOW_CIF_GENERATION  : uses PHENIX eLBOW to produce a .cif restraint file
 *                          for a small-molecule ligand supplied as SDF, MOL2,
 *                          or a SMILES string.
 * GRADE_CIF_GENERATION  : alternative using Global Phasing Grade.
 *
 * NOTE: all Python blocks use single-quote heredoc << 'PYEOF' and ''' for
 *       Python multiline strings to avoid Groovy/Nextflow heredoc conflicts.
 */

// ---------------------------------------------------------------------------
// ELBOW_CIF_GENERATION
// ---------------------------------------------------------------------------

process ELBOW_CIF_GENERATION {
    tag "$ligand_name"
    label 'process_low'

    container 'phenix/phenix:dev'

    input:
    tuple val(ligand_name), path(ligand_file)

    output:
    path "${ligand_name}.cif"      , emit: cif
    path "elbow_report.json"       , emit: report

    stub:
    """
    cat > ${ligand_name}.cif << 'CIFEOF'
data_${ligand_name}
#
_chem_comp.id                     ${ligand_name}
_chem_comp.name                   '${ligand_name}'
_chem_comp.type                   NON-POLYMER
_chem_comp.formula                'C10 H12 N2 O3'
_chem_comp.formula_weight         208.21
#
CIFEOF

    python3 << 'PYEOF'
import json, sys
report = {
    'ligand_name': '${ligand_name}',
    'input_format': 'stub',
    'output_cif': '${ligand_name}.cif',
    'atom_count': 0,
    'bond_count': 0,
    'torsion_count': 0,
    'status': 'stub',
}
with open('elbow_report.json', 'w') as fh:
    json.dump(report, fh, indent=2)
print('stub: elbow_report.json written')
PYEOF
    """

    script:
    // Detect input format
    def ext = ligand_file.extension.toLowerCase()
    def is_smiles = (ext == '' || ext == 'smi' || ext == 'smiles' ||
                     !(ligand_file.name =~ /\.(sdf|mol2|mol|pdb)$/))
    """
    set -euo pipefail

    INPUT_EXT="${ext}"
    if [ "${is_smiles}" = "true" ]; then
        SMILES_STR=\$(cat ${ligand_file} | head -1 | awk '{print \$1}')
        phenix.elbow \
            --smiles="\${SMILES_STR}" \
            --output="${ligand_name}" \
            --quiet
    else
        phenix.elbow \
            ${ligand_file} \
            --output="${ligand_name}" \
            --quiet
    fi

    python3 << 'PYEOF'
import json, re, os

ligand_name = '${ligand_name}'
cif_path    = ligand_name + '.cif'

atom_count     = 0
bond_count     = 0
torsion_count  = 0

if os.path.exists(cif_path):
    text = open(cif_path).read()
    atom_count    = len(re.findall(r'^' + ligand_name + r'\s+\w+\s+[A-Z]', text, re.M))
    bond_count    = len(re.findall(r'^' + ligand_name + r'\s+\w+\s+\w+\s+(SING|DOUB|TRIP|AROM)', text, re.M))
    torsion_count = len(re.findall(r'_chem_comp_tor', text))

report = {
    'ligand_name': ligand_name,
    'input_format': '${ext}' or 'smiles',
    'output_cif': cif_path,
    'atom_count': atom_count,
    'bond_count': bond_count,
    'torsion_count': torsion_count,
    'status': 'success',
}
with open('elbow_report.json', 'w') as fh:
    json.dump(report, fh, indent=2)
print('eLBOW report written')
PYEOF
    """
}


// ---------------------------------------------------------------------------
// GRADE_CIF_GENERATION (Global Phasing Grade -- alternative)
// ---------------------------------------------------------------------------

process GRADE_CIF_GENERATION {
    tag "$ligand_name"
    label 'process_low'

    container 'globalphasing/grade:2.0'

    input:
    tuple val(ligand_name), path(ligand_file)

    output:
    path "${ligand_name}.cif"      , emit: cif
    path "grade_report.json"       , emit: report

    stub:
    """
    cat > ${ligand_name}.cif << 'CIFEOF'
data_${ligand_name}
#
_chem_comp.id                     ${ligand_name}
_chem_comp.name                   '${ligand_name}'
_chem_comp.type                   NON-POLYMER
_chem_comp.formula                'C10 H12 N2 O3'
_chem_comp.formula_weight         208.21
#
CIFEOF

    python3 << 'PYEOF'
import json
report = {
    'ligand_name': '${ligand_name}',
    'tool': 'grade',
    'input_format': 'stub',
    'output_cif': '${ligand_name}.cif',
    'atom_count': 0,
    'bond_count': 0,
    'torsion_count': 0,
    'status': 'stub',
}
with open('grade_report.json', 'w') as fh:
    json.dump(report, fh, indent=2)
PYEOF
    """

    script:
    def ext = ligand_file.extension.toLowerCase()
    """
    set -euo pipefail

    # Real Grade execution
    grade \
        -resname ${ligand_name} \
        -smiles \$(cat ${ligand_file} | head -1 | awk '{print \$1}') \
        -lout ${ligand_name}

    # Grade outputs <ligand_name>.cif
    python3 << 'PYEOF'
import json, re, os

ligand_name = '${ligand_name}'
cif_path    = ligand_name + '.cif'

atom_count     = 0
bond_count     = 0
torsion_count  = 0

if os.path.exists(cif_path):
    text = open(cif_path).read()
    atom_count    = len(re.findall(r'_chem_comp_atom\.', text))
    bond_count    = len(re.findall(r'_chem_comp_bond\.', text))
    torsion_count = len(re.findall(r'_chem_comp_tor\.', text))

report = {
    'ligand_name': ligand_name,
    'tool': 'grade',
    'input_format': '${ext}' or 'smiles',
    'output_cif': cif_path,
    'atom_count': atom_count,
    'bond_count': bond_count,
    'torsion_count': torsion_count,
    'status': 'success',
}
with open('grade_report.json', 'w') as fh:
    json.dump(report, fh, indent=2)
print('Grade report written')
PYEOF
    """
}
