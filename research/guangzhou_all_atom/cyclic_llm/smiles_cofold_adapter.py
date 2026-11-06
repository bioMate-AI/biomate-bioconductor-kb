"""smiles_cofold_adapter.py — emit a Boltz-2 cofold YAML for receptor + a SMILES ligand.

The cofold half of the physics↔affinity gate for MEASURED macrocycles given as SMILES
(json_to_boltz_yaml only supports CCD ligands + peptide-by-sequence). The MM-GBSA half is
NOT buildable here yet: no small-molecule FF toolchain (antechamber/openff/openmm MISSING)
and the existing MM-GBSA is peptide-CHARMM36m — a SMILES→GAFF param pipeline is required.
"""
def smiles_cofold_yaml(receptor_chains, smiles, lig_id="L1"):
    lines = ["version: 1", "sequences:"]
    for cid, cseq in receptor_chains.items():
        lines += ["  - protein:", f"      id: {cid}", f"      sequence: {cseq}"]
    lines += ["  - ligand:", f"      id: {lig_id}", f"      smiles: {smiles}"]
    return "\n".join(lines) + "\n"
