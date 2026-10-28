# TRAIN task: design_constraint  (416 instances)

## [0] source=multitask_sft_big

**USER:** Design 50 novel, drug-like core scaffolds targeting the ATP-binding pocket of a kinase. The scaffolds must provide a distinct hinge-binding motif (with at least one hydrogen-bond donor and one acceptor) while avoiding common intellectual property overlaps such as 4-anilinoquinazoline and pyrrolopyrimidine chemotypes. Ensure the molecules align with a standard CNS/oral property envelope: MW 300-450 Da, clogP 2.0-4.0, TPSA 60-90 Å², rotatable bonds <= 6, and no PAINS or reactive functionalities.

**ASSISTANT:** {"stage": "generate", "target": "Kinase (ATP-binding pocket)", "scaffold_policy": {"novelty": "distinct from 4-anilinoquinazolines and pyrrolopyrimidines", "pharmacophore": "hinge-binding motif with >= 1 H-bond donor and >= 1 H-bond acceptor", "alerts_filter": "exclude PAINS and reactive functionalities"}, "property_envelope": {"molecular_weight": [300, 450], "clogP": [2.0, 4.0], "tpsa": [60.0, 90.0], "rotatable_bonds": "<= 6"}, "count": 50}

---

## [1] source=multitask_sft_big

**USER:** Design 20 de-novo CDR-H3 loops targeting the SARS-CoV-2 Omicron XBB.1.5 receptor-binding domain (PDB: 8WPO). Use the trastuzumab heavy chain (VH) framework (IGHV3-23/IGHJ4), grafting and replacing CDR-H3 residues 95-102 (Chothia numbering). Target loop length between 12 and 16 residues. Designs must avoid sequence liabilities (no glycosylation NxS/T, no DG/DS isomerization, no NG deamidation, and no free cysteines), maintain a net CDR-H3 charge between -1 and +2 at pH 7.4, and exhibit low hydrophobic patch area (CDR-H3 GRAVY < 0.0).

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Omicron XBB.1.5 RBD", "structure_source": "PDB: 8WPO", "target_chain": "A"}, "scaffold_policy": {"framework": "Trastuzumab VH (IGHV3-23/IGHJ4)", "redesign_region": "CDR-H3 (Chothia 95-102)", "fixed_regions": ["VH FR1-FR4", "CDR-H1", "CDR-H2"], "loop_length_range": [12, 16]}, "property_envelope": {"net_charge_range": [-1.0, 2.0], "max_gravy_score": 0.0, "excluded_motifs": ["N[^P][ST]", "DG", "DS", "NG", "C"]}, "count": 20}

---

## [2] source=multitask_sft_big

**USER:** Generate 50 novel small-molecule candidates targeting the 5-HT2A receptor that minimize hERG cardiotoxicity liability (hERG IC50 > 10 µM) while maintaining an optimal lipophilicity profile (logP between 1.5 and 3.0). Compounds should have molecular weight below 450 Da and TPSA between 40 and 90 Å².

**ASSISTANT:** {"stage": "generate", "target": "5-HT2A receptor", "scaffold_policy": "unconstrained", "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "TPSA": {"min": 40.0, "max": 90.0}}, "count": 50}

---

## [3] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops targeting the SARS-CoV-2 Omicron RBD (PDB: 7T9L, Chain A). Use the human germline IGHV3-23*01 / IGHJ4*01 framework with fixed CDR-H1 and CDR-H2. The CDR-H3 loop length should range from 12 to 16 amino acids. Filter designs for predicted binding affinity (Rosetta dG_separated < -35 REU), CamSol intrinsic solubility score > 1.0, and zero sequence liabilities (exclude N-glycosylation motifs N-X-[S/T], deamidation NG/NN, and Asp cleavage DP).

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Omicron RBD", "pdb_id": "7T9L", "chain": "A"}, "scaffold_policy": {"framework": "IGHV3-23*01/IGHJ4*01", "fixed_regions": ["CDR-H1", "CDR-H2", "FR1", "FR2", "FR3", "FR4", "VL"], "design_region": "CDR-H3", "loop_length_range": [12, 16]}, "property_envelope": {"binding_affinity_dG": "< -35.0 REU", "camsol_score": "> 1.0", "sequence_liabilities": {"excluded_motifs": ["N[^P][ST]", "NG", "NN", "DP"]}}, "count": 50}

---

## [4] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptides that bind the p53-binding hydrophobic groove of human MDM2 (PDB: 1YCR) to disrupt the p53-MDM2 protein-protein interaction. The macrocycles should be 8 to 12 amino acids in length, cyclized via head-to-tail backbone cyclization or an intramolecular disulfide staple. Key interactions must preserve hydrophobic contact mimicking the p53 triad (Phe19, Trp23, Leu26). Maintain molecular weight between 900 and 1500 Da, cLogP between 0.5 and 4.5, topological polar surface area (tPSA) between 220 and 380 Å², and at least 2 hydrogen bond donors.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 p53-interaction pocket (PDB: 1YCR)", "scaffold_policy": "8-12 amino acid macrocyclic peptides cyclized via head-to-tail backbone amide bond or intramolecular disulfide staple, containing p53 triad pharmacophore mimetics (Phe/Trp/Leu)", "property_envelope": {"length": "8-12 amino acids", "molecular_weight": "900 - 1500 Da", "clogP": "0.5 - 4.5", "tPSA": "220 - 380 \u00c5\u00b2", "h_bond_donors": ">= 2"}, "count": 20}

---

## [5] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops for the human IGHV3-23/IGHJ4 framework targeting the receptor-binding domain (RBD) of SARS-CoV-2 Omicron XBB.1.5 (PDB: 8W9E). CDR-H3 loop length should be constrained to 10–15 amino acids (Chothia definitions H95–H102). Maintain the rest of the heavy and light chain frameworks constant. Filter candidates for developability: avoid N-glycosylation motifs (NxS/T, x≠P), unpaired cysteines, and poly-tryptophan stretches (>2 consecutive Trp). Net CDR-H3 charge at pH 7.4 must fall between -1.5 and +2.0, with average GRAVY score < 0.0 to prevent non-specific aggregation. Candidates must exhibit predicted interface pLDDT > 80 and ipTM > 0.75.

**ASSISTANT:** {"stage": "generate", "target": "SARS-CoV-2 Omicron XBB.1.5 RBD (PDB: 8W9E)", "scaffold_policy": {"framework": "Human IGHV3-23/IGHJ4", "fixed_regions": ["VH FR1-FR4", "CDR-H1", "CDR-H2", "VL (full)"], "design_region": "CDR-H3 (Chothia H95-H102)", "loop_length_range": [10, 15]}, "property_envelope": {"ipTM": ">= 0.75", "pLDDT": ">= 80", "net_charge_pH7_4": [-1.5, 2.0], "gravy_score": "< 0.0", "motif_exclusions": ["N[^P][ST]", "C", "W{3,}"]}, "count": 50}

---

## [6] source=multitask_sft_big

**USER:** Please design 8 de novo RNA aptamer sequences targeting human VEGF-165 (UniProt: P15692). The sequences should be 40 to 50 nucleotides long, use standard ribonucleotides (A, C, G, U), exhibit predicted binding affinity Kd < 50 nM, have a minimum free energy (dG) of folding between -18.0 and -8.0 kcal/mol to support stable secondary structure without misfolding, and maintain a GC content between 45% and 60%.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 40, "max": 50, "unit": "nt"}, "affinity_kd": {"max": 50, "unit": "nM"}, "minimum_free_energy_dg": {"min": -18.0, "max": -8.0, "unit": "kcal/mol"}, "gc_content_pct": {"min": 45.0, "max": 60.0, "unit": "%"}}, "count": 8}

---

## [7] source=multitask_sft_big

**USER:** Generate 25 novel, structurally diverse small-molecule scaffolds for inhibiting the kinase LRRK2 at the ATP-binding site. The designs must provide viable hinge-binding motifs (1-2 hydrogen bonds) while strictly avoiding established kinase cores such as quinazolines, indazoles, and 2,4-diaminopyrimidines. Target a property profile of MW 350-480 Da, cLogP 2.0-4.5, TPSA 60-90 Å², HBD <= 2, HBA 4-8, and rotatable bonds <= 6.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 (ATP-binding site)", "scaffold_policy": {"action": "novel", "required_motifs": ["hinge-binding donor/acceptor pair"], "excluded_cores": ["quinazoline", "indazole", "2,4-diaminopyrimidine"]}, "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "clogp": {"min": 2.0, "max": 4.5}, "tpsa": {"min": 60, "max": 90}, "hbd": {"max": 2}, "hba": {"min": 4, "max": 8}, "rotatable_bonds": {"max": 6}}, "count": 25}

---

## [8] source=multitask_sft_big

**USER:** Design 20 novel bifunctional PROTAC linkers connecting an AR antagonist warhead (attached via an aliphatic amine handle) and a VHL E3 ligase ligand (VH032 derivative attached at the terminal benzylic carbon). Linkers should incorporate semi-rigid motifs such as piperazines, fused bicyclics, or alkynes to reduce conformational entropy, avoiding simple long polyethylene glycol (PEG) chains or plain aliphatic chains. The linker fragment itself should have a molecular weight between 100 and 300 Da, cLogP between 0.5 and 3.0, and TPSA < 80 Å² to support reasonable cell permeability and ternary complex formation.

**ASSISTANT:** {"stage": "generate", "target": "AR / VHL ternary complex", "scaffold_policy": "link two predefined exit vectors (AR warhead amine and VH032 benzylic position) while keeping warhead and E3 binders strictly fixed", "property_envelope": {"linker_mw": [100, 300], "linker_clogp": [0.5, 3.0], "linker_tpsa": [0, 80], "preferred_motifs": ["piperazine", "bicyclic rings", "alkyne", "rigidified heterocycles"], "unwanted_motifs": ["pure polymethylene chains > 6 carbons", "unbranched PEG > 3 units"]}, "count": 20}

---

## [9] source=multitask_sft_big

**USER:** Design 20 novel drug-like small molecules targeting the Dopamine D2 receptor with optimized lipophilicity (logP between 2.0 and 3.5), minimal cardiotoxicity liability (hERG pIC50 < 5.0 / IC50 > 10 uM), and molecular weight under 450 Da.

**ASSISTANT:** {"stage": "generate", "target": "Dopamine D2 receptor", "scaffold_policy": "novel", "property_envelope": {"logP": {"min": 2.0, "max": 3.5}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450}}, "count": 20}

---

## [10] source=multitask_sft_big

**USER:** We need to design novel bifunctional degraders targeting BRD4 using VHL as the E3 ligase. Please generate 25 diverse PROTAC linkers to connect our JQ1-derived warhead (terminal carboxylate exit vector) with a VH032-derived ligand (terminal alkylamine exit vector). The linkers should feature 8 to 14 linker atoms, incorporate semi-rigid elements such as piperazines, spirocycles, or alkynes to avoid floppy polymethylene/poly-PEG chains (limit contiguous PEG units to <= 2), keep the overall degrader cLogP between 2.0 and 5.0, TPSA below 180 Å², and maintain fewer than 12 rotatable bonds within the linker region.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC", "scaffold_policy": "Bifunctional linker design connecting JQ1 carboxylic acid and VH032 amine exit vectors with rigid/semi-rigid motifs and <= 2 contiguous PEG units", "property_envelope": {"linker_chain_length": [8, 14], "linker_rotatable_bonds": "<= 12", "clogp": [2.0, 5.0], "tpsa": "<= 180", "max_contiguous_peg_units": 2}, "count": 25}

---

## [11] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small molecules targeting LRRK2 with favorable safety profiles. The designs must strictly avoid hERG-mediated cardiotoxicity with a predicted hERG IC50 > 10 uM (pIC50 < 5.0) and maintain an optimal lipophilicity window with LogP between 2.0 and 3.2. Keep molecular weight below 450 Da and TPSA between 60 and 120 A^2.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2", "scaffold_policy": "free", "property_envelope": {"LogP": {"min": 2.0, "max": 3.2}, "hERG_pIC50": {"max": 5.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 50}

---

## [12] source=multitask_sft_big

**USER:** Design 15 de novo CDR-H3 loops targeting the human HER2 extracellular domain (PDB: 1N8Z) grafted into the Trastuzumab VH framework (IGHV3-23 / IGHJ4). The CDR-H3 loop length should be restricted to 11–15 amino acids between anchor residues Cys92 and Trp103 (Chothia numbering). Filter designs for high predicted binding affinity (predicted interface dG < -35.0 REU), net loop charge between -1 and +2 at pH 7.4, and devoid of sequence liabilities including unpaired cysteines, deamidation motifs (NG, NN), and isomerization motifs (DG).

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 extracellular domain (PDB: 1N8Z)", "scaffold_policy": "Trastuzumab heavy chain framework (IGHV3-23/IGHJ4), fixed framework with de novo CDR-H3 loop insertion between Cys92 and Trp103 (Chothia)", "property_envelope": {"cdr_h3_length": [11, 15], "predicted_binding_ddg": "< -35.0 REU", "net_charge_ph7_4": [-1, 2], "exclude_motifs": ["C", "NG", "NN", "DG"]}, "count": 15}

---

## [13] source=multitask_sft_big

**USER:** Generate 30 novel de-novo small molecules optimized for drug-likeness with a logP between 1.5 and 2.5 and minimal hERG liability (predicted hERG IC50 > 10 µM). Ensure molecular weight is below 450 Da and topological polar surface area (TPSA) is between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "none", "property_envelope": {"logP": {"min": 1.5, "max": 2.5}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 110.0}}, "count": 30}

---

## [14] source=multitask_sft_big

**USER:** Design 50 novel, structurally diverse core scaffolds for kinase inhibition targeting the ATP-binding pocket of EGFR. The scaffolds must avoid established kinase chemotypes such as quinazolines, pyrimidines, and pyridopyrimidines to ensure patentability. Ensure the designs satisfy typical drug-like properties: MW between 350 and 500 Da, cLogP 2.0 to 4.0, TPSA <= 120 Å², HBD <= 3, HBA <= 7, and a synthetic accessibility (SA) score below 4.0.

**ASSISTANT:** {"stage": "generate", "target": "EGFR kinase ATP-binding pocket", "scaffold_policy": {"mode": "de_novo", "excluded_cores": ["quinazoline", "pyrimidine", "pyridopyrimidine"], "hinge_binding_capacity": true}, "property_envelope": {"molecular_weight": {"min": 350, "max": 500}, "clogp": {"min": 2.0, "max": 4.0}, "tpsa_max": 120.0, "hbd_max": 3, "hba_max": 7, "sa_score_max": 4.0}, "count": 50}

---

## [15] source=multitask_sft_big

**USER:** Generate 25 de-novo macrocyclic peptide binders targeting the p53-binding pocket of MDM2 to disrupt the MDM2-p53 interaction. The peptides should be 7 to 12 amino acids in length, cyclized via a sidechain-to-sidechain (e.g., hydrocarbon staple or lactam) or head-to-tail architecture to enhance proteolytic stability. Keep molecular weight between 800 and 1600 Da, cLogP between -1.0 and 3.5, with at least 3 hydrophobic contact residues mimicking the p53 Phe19-Trp23-Leu26 triad and predicted binding affinity Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 p53-binding pocket (PPI interface)", "scaffold_policy": "Macrocyclic peptide (7-12 residues, head-to-tail or sidechain cyclized)", "property_envelope": {"molecular_weight": "800 - 1600 Da", "clogP": "-1.0 to 3.5", "sequence_length": "7-12 amino acids", "predicted_kd": "< 50 nM", "pharmacophore_constraints": "Mimicry of p53 hydrophobic triad (Phe19, Trp23, Leu26)", "stability": "Cyclized backbone/sidechains for proteolytic resistance"}, "count": 25}

---

## [16] source=multitask_sft_big

**USER:** Please generate 30 novel de novo scaffolds targeting the ATP-binding site of protein kinases featuring a classic hinge-binding motif (at least one H-bond donor and one H-bond acceptor). Ensure the scaffolds possess freedom-to-operate by avoiding common quinazoline, pyrazolopyrimidine, and indolinone chemotypes. Desired molecular properties: MW between 300 and 450 Da, cLogP 2.0–4.0, TPSA 60–100 Å², HBD 1–3, HBA 3–7, and RotB <= 5.

**ASSISTANT:** {"stage": "generate", "target": "protein kinase ATP-binding pocket", "scaffold_policy": "novel chemotypes avoiding quinazoline, pyrazolopyrimidine, and indolinone cores, requiring a hinge-binding donor-acceptor motif", "property_envelope": {"MW": [300, 450], "cLogP": [2.0, 4.0], "TPSA": [60, 100], "HBD": [1, 3], "HBA": [3, 7], "RotB": {"max": 5}}, "count": 30}

---

## [17] source=multitask_sft_big

**USER:** Design 20 novel, non-covalent core scaffolds targeting the ATP-binding pocket of EGFR T790M/C797S. Avoid classical quinazoline, pyrimidine-2,4-diamine, or indazole hinge-binding motifs, maintaining a maximum Tanimoto similarity of 0.4 to approved kinase inhibitors. Ensure drug-like properties: MW 350–480 Da, cLogP 2.0–4.0, TPSA 60–110 Å², HBD ≤ 3, HBA ≤ 8, rotatable bonds ≤ 6, and eliminate any PAINS or chemically reactive functionalities.

**ASSISTANT:** {"stage": "generate", "target": "EGFR T790M/C797S (kinase domain ATP-binding site)", "scaffold_policy": {"novelty": "high", "max_tanimoto_to_known_drugs": 0.4, "excluded_cores": ["quinazoline", "pyrimidine-2,4-diamine", "indazole"], "binding_mechanism": "reversible/non-covalent hinge-binder"}, "property_envelope": {"molecular_weight": [350, 480], "clogp": [2.0, 4.0], "tpsa": [60, 110], "hbd_max": 3, "hba_max": 8, "rotatable_bonds_max": 6, "structural_alerts": ["pains", "reactive_warheads"]}, "count": 20}

---

## [18] source=multitask_sft_big

**USER:** Generate 25 novel PROTAC linkers connecting an AR antagonist warhead (enzalutamide exit vector at [*]) to the VHL E3 ligase ligand VH032 (terminal amide exit vector at [*]). Please avoid flexible aliphatic or polyethylene glycol (PEG) chains; prioritize semi-rigid elements such as piperazines, spirocycles, and small bicyclic rings to restrict conformational entropy. Linker length should span 8 to 16 heavy atoms. The resulting intact PROTACs should have MW < 1100 Da, cLogP between 2.5 and 5.5, TPSA < 220 Å², and no more than 8 rotatable bonds within the linker portion.

**ASSISTANT:** {"stage": "generate", "target": "Androgen Receptor (AR) / Von Hippel-Lindau (VHL) E3 ubiquitin ligase", "scaffold_policy": {"warhead": "Fixed AR antagonist (enzalutamide derivative) with designated attachment vector [*]", "e3_ligand": "Fixed VHL binder (VH032 derivative) with designated attachment vector [*]", "linker_design": "De-novo linker connection across exit vectors; enforce semi-rigid/heterocyclic motifs (piperazines, spirocycles, bicyclics) and exclude pure linear alkyl or PEG linkers"}, "property_envelope": {"linker_heavy_atom_count": "8 - 16", "linker_rotatable_bonds": "<= 8", "intact_MW": "< 1100", "intact_cLogP": "2.5 - 5.5", "intact_TPSA": "< 220"}, "count": 25}

---

## [19] source=multitask_sft_big

**USER:** Design 20 novel PROTAC linkers connecting the C4-amino nitrogen of a pomalidomide-based cereblon (CRBN) ligand to the terminal piperazine nitrogen of an AR (androgen receptor) antagonist warhead. Linkers should span between 8 and 14 heavy atoms, incorporate rigidifying heterocycles or alkynes alongside flexible alkyl/PEG units to reduce conformational entropy, keep overall PROTAC cLogP below 5.5, and strictly avoid hydrolytically labile bonds such as esters or hydrazones.

**ASSISTANT:** {"stage": "generate", "target": "AR / CRBN", "scaffold_policy": "keep_warhead_and_e3_fixed_link_specified_vectors", "property_envelope": {"linker_heavy_atom_count": [8, 14], "overall_clogp_max": 5.5, "rotatable_bonds_linker_max": 10, "unwanted_substructures": ["ester", "hydrazone", "acyl_halide", "peroxide", "aliphatic_disulfide"]}, "count": 20}

---

## [20] source=multitask_sft_big

**USER:** Generate 50 novel drug-like small molecules with optimized lipophilicity and minimal cardiac toxicity risk. The designs must have a logP between 1.5 and 3.0, predicted hERG pIC50 < 5.0 (IC50 > 10 uM), MW <= 450 Da, and TPSA between 60 and 120 A^2.

**ASSISTANT:** {"stage": "generate", "target": "hERG", "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 50}

---

## [21] source=multitask_sft_big

**USER:** Design 20 novel, rigidified bifunctional linkers to connect our VHL E3 ligase ligand (VH032 derivative, exit vector via terminal amino/alkyl group) to a BRD4-targeting warhead (JQ1 derivative via terminal carboxylic acid). We want to replace flexible PEG or extended alkyl linkers to improve cellular permeability, cooperativity, and metabolic stability. The linkers should have an end-to-end distance between 8.0 and 14.0 Å, incorporate semi-rigid motifs (such as piperazines, spirocycles, bicyclic systems, or alkynes), keep the linker fragment MW between 100 and 260 Da, rotatable bond count <= 7, tPSA < 50 Å², and synthetic accessibility (SA) score <= 3.8. Exclude chemically reactive handles or hydrolytically labile bonds.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex (PROTAC linker)", "scaffold_policy": "Bifunctional linker design connecting specific attachment vectors of VHL (VH032) and BRD4 (JQ1) binders; incorporate rigid/semi-rigid heterocyclic or cycloalkyl cores; avoid unbranched polyether/polymethylene chains", "property_envelope": {"linker_length_angstrom": [8.0, 14.0], "linker_mw": [100.0, 260.0], "linker_rotatable_bonds": "<= 7", "linker_tpsa": "< 50.0", "sa_score": "<= 3.8", "reactive_functional_groups": false}, "count": 20}

---

## [22] source=multitask_sft_big

**USER:** Design 20 diverse, bifunctional linkers to connect a VHL E3 ligase ligand (VH032 exit vector at the phenol) to an AR antagonist warhead terminating in an aliphatic primary amine. The linkers should span 8 to 14 linear connecting bonds, feature semi-rigid motifs (such as piperazines, bicyclic rings, or small spiro rings) to reduce conformational entropy, keep linker molecular weight under 250 Da, maintain linker logP between 0.5 and 2.5, have no more than 2 hydrogen bond donors, and ensure the resulting intact PROTAC maintains a predicted cLogP < 5.0.

**ASSISTANT:** {"stage": "generate", "target": "PROTAC linker (AR warhead to VHL ligase ligand)", "scaffold_policy": "attach via phenol ether to VHL ligand and amide/amine to AR warhead; linear path length of 8-14 bonds; incorporate semi-rigid spiro or saturated heterocycles", "property_envelope": {"linker_mw": "< 250 Da", "linker_logP": "0.5 - 2.5", "linker_hbd": "<= 2", "linker_bond_length": "8-14 bonds", "protac_clogP": "< 5.0"}, "count": 20}

---

## [23] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loop variants grafted onto the human VH3-23/JH4 antibody framework targeting the EGF-A binding domain of human PCSK9 (PDB: 2P4E). The CDR-H3 loop length must be constrained between 12 and 16 amino acids. Exclude canonical sequence liabilities including N-linked glycosylation sites (N-X-S/T, X!=P), deamidation motifs (NG, NN), and unpaired cysteines. The candidate CDR-H3 regions should have a net CDR charge between -1.0 and +2.0 at pH 7.4 and a Spatial Aggregation Propensity (SAP) score below 0.15.

**ASSISTANT:** {"stage": "generate", "target": "Human PCSK9 EGF-A binding domain (PDB: 2P4E)", "scaffold_policy": "Human VH3-23/JH4 framework with fixed CDR-H1 and CDR-H2; CDR-H3 de-novo generation", "property_envelope": {"cdr_h3_length": [12, 16], "net_charge_ph7_4": [-1.0, 2.0], "max_sap_score": 0.15, "forbidden_motifs": ["N[^P][ST]", "NG", "NN", "C"]}, "count": 50}

---

## [24] source=multitask_sft_big

**USER:** Design 50 novel, druglike small molecules generated de novo with optimized lipophilicity (LogP between 1.5 and 3.0) and high cardiac safety, specifically minimizing hERG inhibition with an expected IC50 greater than 10 uM. Ensure standard oral druglikeness (MW < 450 Da, TPSA between 60 and 120 A^2, and <= 5 H-bond donors) while avoiding quaternary amines or extended hydrophobic basic pharmacophores.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": {"type": "de_novo", "constraints": "free generation, disallow flexible basic amine chains and known hERG cardiotoxic pharmacophores"}, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "molecular_weight": {"max": 450.0}, "tpsa": {"min": 60.0, "max": 120.0}, "hbd": {"max": 5}}, "count": 50}

---

## [25] source=multitask_sft_big

**USER:** Generate 50 novel small molecule drug candidates designed to optimize lipophilicity and minimize cardiotoxicity risk. Compounds must have a cLogP between 1.5 and 3.0, hERG IC50 > 30 µM (or pIC50 < 4.5), molecular weight under 450 Da, and TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "unconstrained", "property_envelope": {"cLogP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 30.0}, "molecular_weight": {"max": 450.0}, "tpsa": {"min": 60.0, "max": 110.0}}, "count": 50}

---

## [26] source=multitask_sft_big

**USER:** Design 10 novel de-novo RNA aptamers targeting human VEGF-165 with high binding affinity (predicted Kd < 10 nM). Aptamer sequences must be between 40 and 55 nucleotides in length, have a GC content between 45% and 60%, exhibit a minimum secondary structure folding stability of ΔG < -12.0 kcal/mol at 37°C, and avoid homopolymer tracts greater than 4 consecutive identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor 165 (VEGF-165, UniProt: P15692)", "scaffold_policy": "none", "property_envelope": {"affinity_Kd_nM": "< 10", "sequence_length": {"min": 40, "max": 55}, "gc_content_percent": {"min": 45, "max": 60}, "delta_G_kcal_mol": "< -12.0", "max_homopolymer_run": 4}, "count": 10}

---

## [27] source=multitask_sft_big

**USER:** Design 25 novel linkers to connect a VHL ligand (VH032-derived terminal amine) and a BRD4-binding warhead (JQ1-derived carboxylate). The linkers must span 8 to 14 heavy atoms in path length, possess a linker-specific molecular weight under 250 Da, cLogP between 0.5 and 2.5, at most 3 hydrogen bond donors, and incorporate rigidifying motifs such as piperazine, saturated heterocycles, or alkynes to mitigate conformational entropy.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL PROTAC", "scaffold_policy": "linker_design", "property_envelope": {"linker_heavy_atom_length": [8, 14], "linker_mw": "<=250", "clogp": [0.5, 2.5], "hbd": "<=3"}, "count": 25}

---

## [28] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human thrombin (UniProt: P00734) with high binding affinity (predicted Kd < 50 nM). The aptamers must be 30 to 45 nucleotides in length, possess a GC content between 40% and 60%, and have a secondary structure folding free energy (ΔG) of less than -10 kcal/mol.

**ASSISTANT:** {"stage": "generate", "target": "Human thrombin (UniProt: P00734)", "scaffold_policy": "none", "property_envelope": {"length": {"min": 30, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "folding_mfe_delta_g_kcal_mol": {"max": -10.0}, "predicted_kd_nM": {"max": 50.0}}, "count": 5}

---

## [29] source=multitask_sft_big

**USER:** Design 15 de novo CDR-H3 loops targeting the receptor-binding domain (RBD) of SARS-CoV-2 Spike glycoprotein (PDB ID: 7K8Z, chain A). Graft the loops into a human IGHV3-23/IGHJ4 heavy chain framework while maintaining canonical stem geometry. Constrain the CDR-H3 loop length to 12-16 amino acids, ensure predicted binding affinity with a Kd < 50 nM, maintain a net charge at pH 7.4 between -1.0 and +2.0, limit aromatic residue content to <= 25%, and keep the developability index score below 1.5.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike Receptor-Binding Domain (RBD)", "pdb_id": "7K8Z", "chain": "A", "epitope_region": "ACE2-binding interface (residues 438-506)"}, "scaffold_policy": {"framework": "Human IGHV3-23*01 / IGHJ4*01", "variable_region": "Heavy chain", "design_segment": "CDR-H3", "boundary_definition": "Chothia / IMGT (flanked by Cys92 and Trp103)"}, "property_envelope": {"length_range": [12, 16], "predicted_kd_nM": "<= 50", "net_charge_pH_7_4": [-1.0, 2.0], "max_aromatic_fraction": 0.25, "max_developability_index": 1.5, "avoid_motifs": ["NG", "NS", "DG", "DP", "N-X-S/T"]}, "count": 15}

---

## [30] source=multitask_sft_big

**USER:** Design 50 de novo macrocyclic peptide binders targeting the p53-interaction groove on MDM2. The peptides should be 8-12 amino acids long and cyclized via head-to-tail backbone cyclization or an i, i+4 olefin metathesis staple. The designs should mimic the p53 key interaction triad (Phe19, Trp23, Leu26) using natural or non-canonical amino acids (e.g., 6-Cl-Trp, Aib). Filter candidates for a molecular weight below 1500 Da, topological polar surface area (tPSA) under 350 Å², net charge between -1 and +2 at pH 7.4, and predicted high stability against proteolytic degradation.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-binding cleft, PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptide (length 8-12 residues; backbone head-to-tail or i, i+4 hydrocarbon staple; must present Phe-Trp-Leu mimicking pharmacophore)", "property_envelope": {"molecular_weight": "<= 1500 Da", "sequence_length": "8-12 amino acids", "tpsa": "<= 350 \u00c5\u00b2", "net_charge_ph7_4": [-1, 2], "metabolic_stability": "high proteolysis resistance"}, "count": 50}

---

## [31] source=multitask_sft_big

**USER:** Please design 50 novel, diverse small-molecule core scaffolds for Type I kinase inhibition targeting CDK2. The designs must incorporate a viable hinge-binding motif (at least one hydrogen bond donor and one acceptor) while strictly avoiding established IP spaces including quinazoline, pyrazolopyrimidine, and purine backbones. Candidates must satisfy standard oral drug-likeness criteria: molecular weight between 300 and 450 Da, cLogP 2.0 to 4.0, TPSA between 60 and 100 Å², no more than 2 hydrogen bond donors, no more than 6 hydrogen bond acceptors, and at most 5 rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "CDK2 (ATP-binding site / Type I kinase hinge)", "scaffold_policy": {"novelty": "de_novo", "required_motifs": ["Hinge-binding donor-acceptor pair"], "excluded_scaffolds": ["quinazoline", "pyrazolopyrimidine", "purine"]}, "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "clogp": {"min": 2.0, "max": 4.0}, "tpsa": {"min": 60.0, "max": 100.0}, "hbd": {"min": 1, "max": 2}, "hba": {"min": 1, "max": 6}, "rotatable_bonds": {"max": 5}}, "count": 50}

---

## [32] source=multitask_sft_big

**USER:** Design 10 novel de-novo RNA aptamers targeting the extracellular domain of human epidermal growth factor receptor (EGFR-ECD). The candidates should be 40 to 50 nucleotides in length, demonstrate predicted binding affinity (Kd) under 50 nM, maintain a minimum free energy (MFE) of secondary structure folding between -12 and -25 kcal/mol, have a GC content of 45% to 60%, and contain no homopolymeric runs longer than 4 consecutive nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human EGFR Extracellular Domain (EGFR-ECD)", "scaffold_policy": "de-novo; 40-50 nt linear RNA", "property_envelope": {"length_nt": [40, 50], "predicted_Kd_nM": {"max": 50}, "mfe_kcal_per_mol": {"min": -25.0, "max": -12.0}, "gc_content_pct": {"min": 45.0, "max": 60.0}, "max_homopolymer_length": 4}, "count": 10}

---

## [33] source=multitask_sft_big

**USER:** Generate 20 de novo macrocyclic peptide inhibitors targeting the interaction interface of human MDM2 with p53. The peptides should have a length of 8 to 13 amino acids, constrained by a side-chain to side-chain cyclization (hydrocarbon staple or lactam bridge). Target high predicted binding affinity (Kd < 100 nM), a molecular weight between 1000 and 1600 Da, net formal charge between -1 and +2 at pH 7.4, and fewer than 5 rotatable bonds outside the macrocyclic core to balance metabolic stability and solubility.

**ASSISTANT:** {"stage": "generate", "target": {"protein": "MDM2", "site": "p53 binding cleft", "organism": "Homo sapiens"}, "scaffold_policy": {"modality": "macrocyclic_peptide", "length": [8, 13], "cyclization_type": ["hydrocarbon_staple", "lactam_bridge"]}, "property_envelope": {"molecular_weight": [1000.0, 1600.0], "predicted_kd_nm": "< 100", "formal_charge_ph7_4": [-1, 2], "exocyclic_rotatable_bonds": "<= 5"}, "count": 20}

---

## [34] source=multitask_sft_big

**USER:** Design 20 novel macrocyclic peptides targeting the Keap1 Kelch domain binding pocket (targeting the Nrf2 binding site, PDB: 2FLU). Peptides should be sidechain-to-sidechain or head-to-tail cyclized, 6 to 12 residues in length, incorporating canonical or non-canonical hydrophobic and acidic residues. Desired profiles include high predicted affinity (pKd > 7.5), molecular weight between 700 and 1500 Da, TPSA < 350 Å², cLogP between -1.0 and 2.5, and a minimum of 2 hydrogen bond acceptors to engage the arginine-rich Kelch pocket.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Nrf2 binding site)", "scaffold_policy": "Macrocyclic peptides (head-to-tail or sidechain cyclized), length 6-12 residues, permitting non-canonical amino acids", "property_envelope": {"molecular_weight": [700, 1500], "clogP": [-1.0, 2.5], "tpsa": "< 350", "pKd": "> 7.5", "h_bond_acceptors": ">= 2"}, "count": 20}

---

## [35] source=multitask_sft_big

**USER:** Design 50 de novo small molecules from scratch with favorable oral bioavailability and an optimized safety profile. The compounds should have an optimal logP between 1.5 and 3.0 to balance permeability and metabolic stability, alongside low hERG liability (predicted hERG IC50 > 10 µM). Keep molecular weight under 450 Da and TPSA between 50 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": "hERG (off-target safety)", "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_umol": {"min": 10.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 50, "max": 120}}, "count": 50}

---

## [36] source=multitask_sft_big

**USER:** Please generate 20 de-novo macrocyclic peptides targeting the p53-binding cleft of human MDM2 (UniProt: P56945) to inhibit the MDM2-p53 protein-protein interaction. The designs should be 8 to 12 amino acids in length, cyclized via a head-to-tail amide bond or an i, i+4 lactam bridge, and mimic the hydrophobic hot-spot triad (Phe19, Trp23, Leu26) of p53. Aim for predicted binding affinity Kd < 50 nM, molecular weight < 1600 Da, and clogP between 0.0 and 4.0 to retain cell-permeability potential.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-binding interface, UniProt P56945)", "scaffold_policy": "Macrocyclic peptide (8-12 residues, head-to-tail or i, i+4 lactam linkage)", "property_envelope": {"length": "8-12 residues", "binding_affinity": "Kd < 50 nM", "molecular_weight": "< 1600 Da", "clogP": "0.0 - 4.0", "pharmacophore": "p53-mimetic triad (Phe, Trp, Leu equivalent spatial presentation)"}, "count": 20}

---

## [37] source=multitask_sft_big

**USER:** Generate 30 novel drug-like small molecules targeting the 5-HT2A receptor with an optimized safety and ADME profile. Specifically, tune lipophilicity to a cLogP between 2.0 and 3.0, and mitigate cardiac liability by ensuring low hERG affinity (predicted hERG IC50 > 10 µM). Restrict molecular weight to < 450 Da, TPSA to 50–90 Å², and avoid basic secondary/tertiary amines strongly associated with hERG-induced QT prolongation.

**ASSISTANT:** {"stage": "generate", "target": "5-HT2A receptor", "scaffold_policy": "novel_scaffolds", "property_envelope": {"cLogP": {"min": 2.0, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 50, "max": 90}}, "count": 30}

---

## [38] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptide binders targeting the p53-binding pocket of MDM2 (PDB: 1YCR). Peptides should be head-to-tail or sidechain-to-sidechain cyclized with lengths between 8 and 13 amino acids, mimicking the key p53 hotspot triad (Phe, Trp, Leu). Require predicted Kd < 50 nM, molecular weight between 800 and 1600 Da, LogP between -0.5 and 3.0, and polar surface area (tPSA) under 350 Å² to support cellular permeability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding interface, PDB: 1YCR)", "scaffold_policy": {"type": "macrocyclic_peptide", "length": [8, 13], "cyclization": ["head-to-tail", "sidechain-to-sidechain"], "pharmacophore_motifs": ["Phe-Trp-Leu hotspot mimicry"]}, "property_envelope": {"affinity_Kd_nM": "< 50", "molecular_weight": [800, 1600], "logP": [-0.5, 3.0], "tPSA": "<= 350"}, "count": 20}

---

## [39] source=multitask_sft_big

**USER:** Generate 10 novel de-novo RNA aptamer sequences targeting the receptor-binding domain (RBD) of the SARS-CoV-2 Spike glycoprotein (UniProt P0DTC2). Each aptamer should have a sequence length between 35 and 50 nucleotides, a predicted binding affinity Kd < 50 nM, a GC content between 40% and 60%, a minimum free energy (MFE) of secondary structure folding <= -12.0 kcal/mol, and exclude homopolymer runs longer than 3 nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "SARS-CoV-2 Spike glycoprotein RBD (UniProt: P0DTC2)", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 35, "max": 50}, "affinity_Kd_nM": {"max": 50}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "mfe_kcal_per_mol": {"max": -12.0}, "max_homopolymer_length": 3}, "count": 10}

---

## [40] source=multitask_sft_big

**USER:** Design 50 novel bifunctional PROTAC linkers connecting a JQ1-derived BRD4 warhead via a terminal amine exit vector to a VHL E3 ligase recruiting ligand (VH032-derivative handle). The linkers should have an effective linear chain length of 8 to 14 atoms, incorporating semi-rigid elements such as piperazines or alkynes alongside alkyl/PEG motifs to tune flexibility. Ensure the linker molecular weight is between 120 and 300 Da, maintain overall PROTAC cLogP between 2.0 and 5.0, and exclude hydrolytically unstable or metabolically labile functional groups such as esters, acetals, and hydrazines.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linker", "scaffold_policy": "linker_design_with_two_exit_vectors", "property_envelope": {"linker_chain_atom_count": {"min": 8, "max": 14}, "linker_molecular_weight": {"min": 120.0, "max": 300.0}, "clogp": {"min": 2.0, "max": 5.0}, "rotatable_bonds": {"max": 12}, "excluded_substructures": ["[C;!$(C=O)][O][C](=O)", "[N][N]", "C(O[C,H])(O[C,H])"]}, "count": 50}

---

## [41] source=multitask_sft_big

**USER:** Design 8 novel RNA aptamer sequences targeting human epidermal growth factor receptor (EGFR, UniProt P00533). The aptamers should have a length between 40 and 60 nucleotides, an estimated binding affinity Kd < 50 nM, a melting temperature Tm > 55 °C, and a predicted minimum free energy (MFE) secondary structure stability <= -15 kcal/mol in physiological buffer.

**ASSISTANT:** {"stage": "generate", "target": "Human EGFR (UniProt: P00533)", "scaffold_policy": "none", "property_envelope": {"length": {"min": 40, "max": 60}, "Kd_nM": {"max": 50}, "Tm_C": {"min": 55}, "mfe_kcal_mol": {"max": -15.0}}, "count": 8}

---

## [42] source=multitask_sft_big

**USER:** Generate 20 de novo drug-like small molecules in novel chemical space with well-balanced physicochemical properties. Ensure optimal lipophilicity with cLogP between 1.5 and 3.0 and reduced cardiotoxicity risk with predicted hERG pIC50 < 5.0 (IC50 > 10 uM). Maintain molecular weight under 450 Da and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "de_novo", "property_envelope": {"cLogP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 20}

---

## [43] source=multitask_sft_big

**USER:** Please design 8 de-novo RNA aptamers targeting human thrombin (exosite I). The sequences should be 30 to 45 nucleotides in length with a GC content between 40% and 60%. They must fold into a stable stem-loop architecture with a predicted minimum free energy (ΔG) below -10.0 kcal/mol at 37°C, exhibit an estimated Kd < 50 nM, and be compatible with 2'-fluoro-modified pyrimidines for RNase resistance.

**ASSISTANT:** {"stage": "generate", "target": "Human thrombin (exosite I)", "scaffold_policy": "stem-loop architecture", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_delta_g": {"max": -10.0, "unit": "kcal/mol"}, "kd": {"max": 50, "unit": "nM"}, "chemistry": "2'-fluoro pyrimidines"}, "count": 8}

---

## [44] source=multitask_sft_big

**USER:** Design 30 novel bifunctional PROTAC linkers connecting a BTK-targeting warhead (attached via piperidine-4-yl nitrogen) to the cereblon (CRBN) E3 ligase ligand pomalidomide (attached at the C4-amino position). Linkers should span 8 to 14 heavy atoms, incorporating semi-rigid elements like piperazines or alkynes alongside alkyl/PEG units to restrict conformational entropy. Avoid metabolically labile groups such as esters, hydrazones, or unstable acetals. The resulting PROTAC conjugates should aim for a cLogP between 2.5 and 5.0, overall TPSA below 180 Å², and no more than 10 rotatable bonds within the linker region.

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN PROTAC linkers", "scaffold_policy": "Connect BTK warhead at piperidine nitrogen to pomalidomide at C4-amino; linker length 8-14 heavy atoms; incorporate semi-rigid motifs; exclude esters, hydrazones, and acetals", "property_envelope": {"cLogP": "2.5 - 5.0", "tpsa": "< 180 \u00c5\u00b2", "linker_heavy_atoms": "8 - 14", "linker_rotatable_bonds": "<= 10"}, "count": 30}

---

## [45] source=multitask_sft_big

**USER:** We are initiating a de novo design campaign targeting the ATP-binding pocket of CDK2 (Cyclin-Dependent Kinase 2). Please generate 50 novel, structurally diverse hinge-binding scaffolds. The designs must avoid well-precedented kinase cores such as 2-aminopyrimidines and staurosporine derivatives to secure IP freedom. The resulting molecules should exhibit kinase drug-like properties: molecular weight between 300 and 450 Da, LogP between 1.5 and 3.5, TPSA between 50 and 90 Å², no more than 3 hydrogen bond donors, and 6 or fewer rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "CDK2 ATP-binding hinge region", "scaffold_policy": "novel hinge-binding chemotypes; exclude 2-aminopyrimidines, staurosporine analogs, and known pan-kinase privileged scaffolds", "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "logP": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 50, "max": 90}, "hbd": {"max": 3}, "rotatable_bonds": {"max": 6}}, "count": 50}

---

## [46] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loop sequences grafted onto the Trastuzumab VH scaffold (PDB: 1N8Z) targeting human HER2 Domain IV, specifically focusing on the epitope defined by residues Thr560, Lys591, and Asp562. The designed CDR-H3 loops should range between 11 and 16 amino acids in length, maintain a net charge between 0 and +2 at pH 7.4, minimize hydrophobic surface patches, and demonstrate predicted binding affinity with a Kd under 10 nM.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 (ErbB2) Domain IV", "pdb_id": "1N8Z", "epitope_residues": ["Thr560", "Asp562", "Lys591"]}, "scaffold_policy": {"base_scaffold": "Trastuzumab VH (1N8Z)", "design_region": "CDR-H3", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"]}, "property_envelope": {"cdr_h3_length": [11, 16], "net_charge": [0, 2], "max_hydrophobic_patch_area_A2": 300, "predicted_kd_nM": "<= 10"}, "count": 50}

---

## [47] source=multitask_sft_big

**USER:** Design 50 de-novo drug-like small molecules with balanced lipophilicity and low cardiotoxicity liability. Maintain cLogP between 1.5 and 3.0, ensure predicted hERG IC50 > 10 µM, molecular weight under 450 Da, and TPSA between 70 and 120 Å² without enforcing any fixed core scaffold.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "free", "property_envelope": {"cLogP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 70.0, "max": 120.0}}, "count": 50}

---

## [48] source=multitask_sft_big

**USER:** Design 25 novel, metabolically stable linkers connecting our VHL ligand (VH032 derivative via terminal hydroxyl/phenol exit vector) to an EGFR kinase warhead (gefitinib core at the piperidine nitrogen). Linkers should have an optimal chain length of 10-16 heavy atoms, favor rigidified/heterocyclic motifs to reduce conformational entropy, avoid labile esters or unhindered amides, maintain overall PROTAC cLogP between 2.0 and 5.0, and keep TPSA below 180 Å².

**ASSISTANT:** {"stage": "generate", "target": "EGFR-VHL PROTAC linker", "scaffold_policy": "linker_between_warheads: EGFR-binding motif (piperidine N) and VHL ligand (VH032 exit vector)", "property_envelope": {"linker_heavy_atom_count": {"min": 10, "max": 16}, "clogP": {"min": 2.0, "max": 5.0}, "tpsa": {"max": 180.0}, "unwanted_substructures": ["esters", "aliphatic_amines_labile", "hydrolyzable_acetals"]}, "count": 25}

---

## [49] source=multitask_sft_big

**USER:** Generate 50 novel de-novo kinase inhibitor scaffolds designed to bind the ATP-binding hinge region of LRRK2. The core structures must avoid established aminopyrimidine and indolinone scaffolds to ensure chemical novelty. Keep molecular weight between 300 and 450 Da, cLogP between 1.5 and 3.5, TPSA under 100 Å², HBD <= 2, and HBA <= 7. Exclude PAINS and reactive functional groups.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 kinase", "scaffold_policy": "novel hinge-binding heterocycles distinct from aminopyrimidines and indolinones", "property_envelope": {"MW": [300, 450], "cLogP": [1.5, 3.5], "TPSA": {"max": 100}, "HBD": {"max": 2}, "HBA": {"max": 7}, "PAINS_free": true, "exclude_reactive_groups": true}, "count": 50}

---

## [50] source=multitask_sft_big

**USER:** Design 8 de novo RNA aptamer sequences targeting human PCSK9 (UniProt: Q8NBP7). The aptamers must be 35 to 50 nucleotides in length, show high predicted binding affinity with a Kd below 50 nM, have a GC content between 40% and 60%, and exhibit a predicted minimum free energy (MFE) secondary structure stability between -15.0 and -30.0 kcal/mol. Sequences should be compatible with 2'-fluoro pyrimidine modifications for nuclease resistance.

**ASSISTANT:** {"stage": "generate", "target": "human PCSK9 (UniProt: Q8NBP7)", "scaffold_policy": "de novo RNA, length 35-50 nt, 2'-fluoro pyrimidine compatible", "property_envelope": {"length": [35, 50], "kd_nM": "<50", "gc_content_pct": [40, 60], "mfe_kcal_mol": [-30.0, -15.0]}, "count": 8}

---

## [51] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamers targeting human vascular endothelial growth factor 165 (VEGF-165, UniProt: P15692). The sequences must be 40 to 60 nucleotides long, incorporate stable stem-loop secondary structures, achieve a predicted binding affinity (Kd) below 10 nM, maintain a folding free energy (ΔG) at 37°C between -25.0 and -12.0 kcal/mol, and have a GC content between 45% and 60%.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 40, "max": 60}, "predicted_kd_nM": {"max": 10.0}, "delta_G_kcal_per_mol": {"min": -25.0, "max": -12.0}, "gc_content_pct": {"min": 45.0, "max": 60.0}, "structural_motifs": ["stem-loop"]}, "count": 8}

---

## [52] source=multitask_sft_big

**USER:** Design 20 novel, semi-rigid linkers connecting a known BRD4 warhead (JQ1-derived carboxylic acid handle) to a VHL E3 ligase binder (VH032 primary amine exit vector). The linkers should replace standard flexible PEG/alkyl chains with conformationally constrained bioisosteres (e.g., piperazines, spirocycles, or alkynes) spanning 9 to 15 atoms in length. Total PROTAC molecular weight must remain under 1000 Da, with an overall cLogP between 2.0 and 5.0, TPSA below 180 Å², and at most 12 rotatable bonds within the linker region to balance ternary complex stability with cell permeability.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC ternary complex", "scaffold_policy": "rigid_linker_design_between_handles", "property_envelope": {"linker_atom_length": "9-15", "overall_mw_max": 1000, "clogp": [2.0, 5.0], "tpsa_max": 180.0, "linker_rotatable_bonds_max": 12, "structural_motifs": ["piperazines", "spirocycles", "alkynes"], "excluded_motifs": ["pure alkyl chains", "long flexible PEG chains"]}, "count": 20}

---

## [53] source=multitask_sft_big

**USER:** Design 8 novel RNA aptamers targeting human Interleukin-6 (IL-6). The sequences should be 40 to 50 nucleotides in length, have a GC content between 40% and 60%, a predicted secondary structure folding free energy (ΔG) between -12.0 and -22.0 kcal/mol, and contain no homopolymeric runs of more than 3 consecutive guanines (poly-G <= 3).

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (IL-6)", "scaffold_policy": "none", "property_envelope": {"length_nt": {"min": 40, "max": 50}, "gc_content": {"min": 0.4, "max": 0.6}, "delta_G_kcal_mol": {"min": -22.0, "max": -12.0}, "max_poly_g": 3}, "count": 8}

---

## [54] source=multitask_sft_big

**USER:** Design 8 novel de-novo RNA aptamer sequences targeting human VEGF-165. The aptamers should be between 35 and 50 nucleotides in length, possess a GC content between 40% and 60%, exhibit a predicted secondary structure folding minimum free energy (MFE) below -12.0 kcal/mol, and demonstrate high predicted binding affinity (Kd < 50 nM).

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "none", "property_envelope": {"length": {"min": 35, "max": 50}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_folding_energy_kcal_per_mol": {"max": -12.0}, "predicted_kd_nM": {"max": 50.0}}, "count": 8}

---

## [55] source=multitask_sft_big

**USER:** Generate 20 de-novo macrocyclic peptides (6-12 amino acids) designed to bind the Keap1 Kelch domain and disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should feature head-to-tail or staple/disulfide cyclization and incorporate a motif mimicking the beta-hairpin DxETGE sequence. Required properties: molecular weight between 800 and 1400 Da, predicted binding affinity Kd < 100 nM, clogP between -1.0 and 2.5, and high predicted serum stability (half-life > 2 hours).

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (PPI: Keap1-Nrf2)", "scaffold_policy": "Macrocyclic peptide (6-12 residues, head-to-tail or side-chain staple/disulfide cyclization, incorporating DxETGE-mimetic beta-turn motif)", "property_envelope": {"molecular_weight": [800, 1400], "clogP": [-1.0, 2.5], "length_residues": [6, 12], "predicted_Kd_nM": "< 100", "plasma_stability_t_half_hr": "> 2"}, "count": 20}

---

## [56] source=multitask_sft_big

**USER:** Design 25 novel linkers to connect our BTK warhead (attachment via terminal alkynyl/amine) to a CRBN E3 ligase binder (pomalidomide 4-position). We need rigidified linkers spanning an effective distance of 10 to 15 Å, incorporating rigid motifs like piperazines, piperidines, or spirocyclic rings to reduce conformational entropy. Please keep linker rotatable bonds <= 6, linker cLogP between 0.5 and 2.5, total PROTAC MW < 950 Da, and ensure high aqueous solubility while avoiding chemically labile groups like esters or hydrazones.

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN ternary complex", "scaffold_policy": "Bifunctional linker design connecting BTK inhibitor and pomalidomide exit vectors; incorporate rigid heterocycles (piperazine, piperidine, spirocycles)", "property_envelope": {"linker_effective_length_A": [10.0, 15.0], "linker_rotatable_bonds": "<= 6", "linker_clogP": [0.5, 2.5], "protac_MW": "< 950", "unwanted_substructures": ["ester", "hydrazone", "aliphatic_chain_length_gt_6"]}, "count": 25}

---

## [57] source=multitask_sft_big

**USER:** Design 20 novel, conformationally constrained PROTAC linkers to connect a VHL E3 ligase ligand (attached via the phenolic oxygen of VH032) and a BRD4 warhead (attached via the diazepine methyl ester exit vector of (+)-JQ1). The linkers should incorporate cyclic or spirocyclic motifs to reduce conformational entropy relative to standard alkyl/PEG chains, maintain a linker MW between 140 and 300 Da, yield full PROTAC molecules with MW < 1000 Da, tPSA < 210 Å², and cLogP between 2.0 and 5.0.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex", "scaffold_policy": {"type": "linker_design", "terminal_A": "VH032 phenol ether exit vector", "terminal_B": "JQ1-derived amide/ester exit vector", "structural_preferences": "rigidified, spirocyclic, or piperazine-containing motifs; avoid purely linear aliphatic or PEG chains"}, "property_envelope": {"linker_mw": "140 - 300 Da", "full_protac_mw": "< 1000 Da", "tpsa": "< 210 \u00c5\u00b2", "clogp": "2.0 - 5.0", "rotatable_bonds_linker": "<= 8"}, "count": 20}

---

## [58] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamers targeting human vascular endothelial growth factor 165 (VEGF-165). The RNA sequences should be 30 to 45 nucleotides in length, have a GC content between 40% and 60%, a predicted minimum free energy (MFE) secondary structure stability of at most -10 kcal/mol, and a high predicted target binding affinity with Kd < 50 nM. Avoid homopolymer tracts of 5 or more consecutive identical bases.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": null, "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "minimum_free_energy_kcal_mol": {"max": -10.0}, "affinity_kd_nM": {"max": 50.0}, "max_homopolymer_length": 4}, "count": 8}

---

## [59] source=multitask_sft_big

**USER:** Please design 10 de-novo CDR-H3 loop sequences for a VH3-23/Trastuzumab-derived antibody framework directed against human TIGIT (PDB ID: 3RQ3), specifically targeting the binding interface around residues Gln56, Asn58, and Glu60. The CDR-H3 length should be constrained between 12 and 16 residues. Generated candidates must lack unpaired cysteines and N-glycosylation motifs (N-X-[S/T]), maintain a net charge between -1 and +2 at pH 7.4, and demonstrate low predicted aggregation propensity.

**ASSISTANT:** {"stage": "generate", "target": {"name": "human TIGIT", "pdb_id": "3RQ3", "epitope_residues": ["Gln56", "Asn58", "Glu60"]}, "scaffold_policy": {"framework": "VH3-23 / Trastuzumab-derived heavy chain", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "loop_length_range": [12, 16]}, "property_envelope": {"net_charge_ph7_4": [-1, 2], "avoid_motifs": ["unpaired Cys", "N-X-[S/T] glycosylation"], "developability_criteria": "low predicted aggregation propensity"}, "count": 10}

---

## [60] source=multitask_sft_big

**USER:** Design 15 de-novo macrocyclic peptides targeting the p53-binding groove of human MDM2 (PDB: 1YCR). Candidates should contain 8 to 12 residues cyclized via head-to-tail backbone amide coupling or a disulfide bond, while presenting pharmacophore features mimicking the p53 hotspot triad (Phe19, Trp23, and Leu26). Ensure predicted binding affinity Kd < 50 nM, molecular weight < 1500 Da, and low predicted immunogenicity.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 p53-binding pocket (PDB: 1YCR)", "scaffold_policy": "8-12 residue macrocyclic peptides cyclized via head-to-tail backbone or disulfide bridge, incorporating Phe/Trp/Leu hotspot mimicry", "property_envelope": {"molecular_weight": "< 1500 Da", "sequence_length": "8-12 amino acids", "binding_affinity_Kd": "< 50 nM", "immunogenicity": "low"}, "count": 15}

---

## [61] source=multitask_sft_big

**USER:** Generate 25 novel small-molecule drug candidates with optimized lipophilicity and a low risk of hERG-related cardiotoxicity. Maintain logP between 1.5 and 3.0, keep MW under 450 Da, and ensure predicted hERG IC50 > 10 µM (pIC50 < 5.0). Avoid lipophilic basic amine scaffolds known to drive hERG channel blockade.

**ASSISTANT:** {"stage": "generate", "target": "hERG (anti-target)", "scaffold_policy": "free novel scaffolds; avoid lipophilic basic amine motifs", "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "MW": "<= 450", "hERG_pIC50": "< 5.0", "hERG_IC50_uM": "> 10"}, "count": 25}

---

## [62] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops (length 11-16 amino acids) grafted into a trastuzumab VH framework targeting the HER2 extracellular domain (PDB: 1N8Z). Candidates must have high predicted binding affinity (predicted pKd > 8.0 / Kd < 10 nM), no unpaired cysteines, zero N-linked glycosylation sequons (N-X-S/T where X != P), fewer than 2 net negative charges, and low predicted hydrophobic patch area (< 350 Å²).

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain", "pdb_id": "1N8Z", "target_chain": "A", "epitope_residues": ["P251", "R252", "E253", "L254", "D255", "T256", "V257", "S258"]}, "scaffold_policy": {"framework": "Trastuzumab_VH", "variable_region": "CDR-H3", "cdr_definition": "Chothia", "loop_length_range": [11, 16], "fixed_framework_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"]}, "property_envelope": {"predicted_kd_nM": "< 10", "unpaired_cysteines": 0, "n_glycosylation_motifs": 0, "isoelectric_point_range": [6.0, 8.5], "hydrophobic_patch_area_A2": "< 350"}, "count": 50}

---

## [63] source=multitask_sft_big

**USER:** Design 50 novel core scaffolds for a Type I kinase inhibitor targeting the ATP hinge-binding pocket. The designs must offer clean intellectual property by strictly avoiding common quinazoline, pyrazolopyrimidine, and bis-indole cores, while incorporating a competent donor-acceptor motif for hinge interaction. Ensure the resulting cores fall within a drug-like property space: MW 250-400 Da, cLogP 1.5-3.5, TPSA 60-110 Å², RotB <= 5, and no PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP-binding site (Type I hinge-binding pocket)", "scaffold_policy": {"novelty": "strictly novel core scaffolds", "exclude": ["quinazoline", "pyrazolopyrimidine", "bis-indole"], "required_motifs": ["hinge-binding hydrogen bond donor-acceptor motif"]}, "property_envelope": {"molecular_weight": {"min": 250, "max": 400}, "clogp": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 60, "max": 110}, "rotatable_bonds": {"max": 5}, "exclude_alerts": ["PAINS", "reactive_functional_groups"]}, "count": 50}

---

## [64] source=multitask_sft_big

**USER:** Design 10 novel de-novo kinase inhibitor scaffolds targeting the ATP-binding site hinge region. The scaffolds must be distinct from classical quinazoline, purine, and 2,4-diaminopyrimidine cores to ensure novel IP. Target drug-like kinase inhibitor space with molecular weight between 350 and 480 Da, cLogP from 2.0 to 4.2, TPSA between 65 and 100 Å², 1 to 3 hydrogen bond donors (incorporating an authentic hinge-binding motif), and no more than 6 rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP-binding site hinge region", "scaffold_policy": "Novel core distinct from classical quinazolines, purines, and 2,4-diaminopyrimidines", "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "clogp": {"min": 2.0, "max": 4.2}, "tpsa": {"min": 65, "max": 100}, "hbd": {"min": 1, "max": 3}, "rotatable_bonds": {"max": 6}}, "count": 10}

---

## [65] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loop variants (lengths 12 to 16 amino acids) grafted onto the trastuzumab VH framework (PDB: 1N8Z) to enhance binding against HER2 domain IV. Ensure high shape complementarity, predicted binding affinity pKd >= 8.5, low hydrophobicity to minimize aggregation risk, and a net CDR-H3 charge between -1 and +2 at pH 7.4.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 domain IV", "pdb_id": "1N8Z", "target_chain": "C", "antibody_chains": {"heavy": "H", "light": "L"}}, "scaffold_policy": {"framework": "Trastuzumab (PDB: 1N8Z)", "fixed_regions": ["VL", "VH_FR1", "CDR-H1", "VH_FR2", "CDR-H2", "VH_FR3", "VH_FR4"], "design_region": "CDR-H3", "cdr_definition": "Chothia", "loop_length_range": [12, 16]}, "property_envelope": {"predicted_pKd": {"min": 8.5}, "net_charge": {"min": -1.0, "max": 2.0}, "hydrophobic_residue_fraction": {"max": 0.35}, "polyreactivity_risk": "low"}, "count": 50}

---

## [66] source=multitask_sft_big

**USER:** Design 20 novel small molecules from scratch with an optimized physicochemical profile focusing on logP and reduced hERG liability. Molecules should have a cLogP between 1.5 and 3.0, a predicted hERG pIC50 below 5.0 (IC50 > 10 µM), molecular weight between 250 and 450 Da, and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "de_novo", "property_envelope": {"clogp": {"min": 1.5, "max": 3.0}, "herg_pIC50": {"max": 5.0}, "mw": {"min": 250, "max": 450}, "tpsa": {"min": 60, "max": 120}}, "count": 20}

---

## [67] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide binders targeting the p53-binding pocket of MDM2 (PDB: 1YCR). The peptides should have a sequence length of 8 to 13 amino acids, utilizing head-to-tail cyclization or a hydrocarbon staple. They must recapitulate key hydrophobic interactions of the p53 helical triad (Phe19, Trp23, Leu26). Filter for molecular weight between 800 and 1500 Da, clogP between 1.0 and 4.5, topological polar surface area (TPSA) < 350 Å², and no metabolically unstable residues (e.g., free cysteines or prone to rapid deamidation).

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 interaction interface, PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptides (length 8-13 residues) with head-to-tail backbone cyclization or sidechain-to-sidechain hydrocarbon stapling; must include pharmacophore triad mimetic residues", "property_envelope": {"molecular_weight": {"min": 800, "max": 1500}, "clogP": {"min": 1.0, "max": 4.5}, "tpsa": {"max": 350}, "length": {"min": 8, "max": 13}, "excluded_motifs": ["free thiol (Cys)", "deamidation-prone Asn-Gly motifs"]}, "count": 20}

---

## [68] source=multitask_sft_big

**USER:** Design 25 novel small-molecule kinase inhibitor scaffolds targeting the ATP-binding pocket of LRRK2 for neurodegenerative indications. The core scaffolds must be structurally distinct from established kinase chemotypes (specifically avoid standard indazoles, aminopyrimidines, and pyrazolopyrimidines) while maintaining characteristic hinge-donor/acceptor hydrogen bonding motifs. Prioritize high CNS penetrance: MW < 450 Da, cLogP between 2.0 and 3.5, TPSA < 80 Å², rotatable bonds ≤ 5, and synthetic accessibility score (SAscore) < 4.0.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 kinase (ATP-binding site)", "scaffold_policy": "novel hinge-binding cores; strictly exclude indazole, aminopyrimidine, and pyrazolopyrimidine templates", "property_envelope": {"MW": "<450", "cLogP": "2.0-3.5", "TPSA": "<80 \u00c5\u00b2", "rotatable_bonds": "<=5", "SAscore": "<4.0"}, "count": 25}

---

## [69] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide binders targeting the p53-binding pocket of MDM2 (UniProt: Q00987). The peptides should have a sequence length of 8 to 12 residues and utilize a head-to-tail backbone cyclization or a hydrocarbon staple. Ensure high predicted shape complementarity to the hydrophobic cleft (Leu26, Trp23, Phe19 interaction hot spots), with a molecular weight between 800 and 1500 Da, net charge between -1 and +1 at pH 7.4, and high predicted proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 interaction interface, PDB: 1YCR / UniProt: Q00987)", "scaffold_policy": {"monomer_type": "peptide", "topology": "macrocycle", "cyclization_type": ["head-to-tail amide", "hydrocarbon staple"], "length": {"min": 8, "max": 12}, "incorporate_hotspot_mimetics": ["Phe", "Trp", "Leu"]}, "property_envelope": {"molecular_weight": {"min": 800, "max": 1500}, "net_charge_pH_7_4": {"min": -1, "max": 1}, "tPSA": {"max": 450}, "clogP": {"min": -1.0, "max": 4.5}, "proteolytic_stability": "high"}, "count": 20}

---

## [70] source=multitask_sft_big

**USER:** Design 20 novel PROTAC linkers to join a BRD4-targeting warhead (JQ1-derived exit vector at the methyl ester position) and a VHL E3 ligase ligand (VH032-amine derivative). The linkers should replace typical floppy PEG chains with semi-rigid, drug-like motifs such as piperazines, spirocycles, or bicyclic rings. Ensure the final PROTAC molecules have a calculated molecular weight under 1050 Da, cLogP between 2.0 and 5.0, TPSA between 150 and 220 Å², and between 4 and 10 rotatable bonds within the linker region itself to maintain appropriate ternary complex conformation.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL PROTAC ternary complex", "scaffold_policy": "bifunctional_linker_join", "property_envelope": {"linker_rotatable_bonds": {"min": 4, "max": 10}, "total_protac_mw_max": 1050, "total_protac_clogp": {"min": 2.0, "max": 5.0}, "total_protac_tpsa": {"min": 150.0, "max": 220.0}, "preferred_structural_motifs": ["piperazine", "spirocycle", "conformationally_constrained_heterocycle"], "disallowed_motifs": ["unbranched_peg_gt_3"]}, "count": 20}

---

## [71] source=multitask_sft_big

**USER:** Generate 50 de novo macrocyclic peptide binders targeting the p53-interaction cleft of human MDM2. Peptides should be 8 to 14 residues in length, cyclized via head-to-tail or disulfide linkage, and compatible with canonical and standard non-canonical amino acids. Maintain MW between 800 and 1600 Da, cLogP below 3.5, and polar surface area between 200 and 400 Å².

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding pocket)", "scaffold_policy": "macrocyclic peptide backbone (8-14 residues, head-to-tail amide or disulfide cyclization)", "property_envelope": {"molecular_weight": "800 - 1600 Da", "clogp": "< 3.5", "tpsa": "200 - 400 \u00c5\u00b2", "sequence_length": "8 - 14 residues"}, "count": 50}

---

## [72] source=multitask_sft_big

**USER:** Please design 10 de novo RNA aptamer candidates targeting human VEGF-165 (UniProt: P15692). The sequences should be between 30 and 45 nucleotides in length, have a GC content between 40% and 65%, achieve a predicted binding affinity (Kd) below 50 nM, and show stable secondary structure folding with a minimum free energy (MFE) below -10.0 kcal/mol.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": null, "property_envelope": {"length": {"min": 30, "max": 45}, "gc_content": {"min": 0.4, "max": 0.65}, "predicted_kd_nM": {"max": 50}, "mfe_kcal_mol": {"max": -10.0}}, "count": 10}

---

## [73] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small molecules with balanced lipophilicity (clogP between 1.5 and 3.0) and reduced cardiac toxicity risk, specifically with low hERG liability (predicted hERG pIC50 < 5.0). Ensure molecular weight is kept below 450 Da.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"clogP": [1.5, 3.0], "hERG_pIC50": "< 5.0", "MW": "<= 450"}, "count": 50}

---

## [74] source=multitask_sft_big

**USER:** Generate 50 de-novo CDR-H3 loop sequences grafted onto the humanized VH3-23 framework (Trastuzumab backbone) targeted against Domain IV of human HER2 (UniProt P04626). The CDR-H3 length must be constrained between 12 and 16 amino acids. Candidates should exhibit high predicted binding affinity (Kd < 10 nM), a net charge between -1.0 and +2.0 at pH 7.4, spatial aggregation propensity (SAP) score below 40, and strictly exclude N-linked glycosylation motifs (N-X-[S/T], X!=P) and DP/DG isomerization hotspots.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human epidermal growth factor receptor 2 (HER2)", "uniprot_id": "P04626", "domain": "Domain IV"}, "scaffold_policy": {"type": "fixed_framework_loop_replacement", "framework": "IGHV3-23 (Trastuzumab VH backbone)", "engineered_region": "CDR-H3", "length_range": [12, 16]}, "property_envelope": {"predicted_kd_nm": "< 10", "net_charge_pH_7_4": [-1.0, 2.0], "max_sap_score": 40, "forbidden_motifs": ["N[^P][ST]", "DG", "DP"]}, "count": 50}

---

## [75] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamer sequences (35 to 45 nucleotides) targeting human VEGF-165 with high affinity (predicted Kd < 50 nM). The aptamers should exhibit stable secondary structures with a minimum folding free energy (ΔG) below -10 kcal/mol and maintain a GC content between 40% and 60%. Avoid homopolymer runs longer than 4 consecutive identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692-4)", "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "affinity_kd_nM": {"max": 50.0}, "folding_delta_G_kcal_per_mol": {"max": -10.0}, "max_homopolymer_run": 4}, "count": 5}

---

## [76] source=multitask_sft_big

**USER:** Design 25 de-novo small-molecule scaffolds as ATP-competitive inhibitors for LRRK2. The designs must feature novel heterocyclic hinge-binding cores that are structurally distinct from known bis-anilino pyrimidines and indolinone series. Focus on CNS-compliant drug-like chemical space: molecular weight under 450 Da, LogP between 2.0 and 3.5, topological polar surface area below 75 Å², at most 2 hydrogen bond donors, and no PAINS or reactive motifs.

**ASSISTANT:** {"stage": "generate", "target": {"name": "LRRK2", "site": "ATP-binding site (hinge region)", "organism": "Homo sapiens"}, "scaffold_policy": {"type": "novel_core", "required_interaction": "heterocyclic hinge-binding acceptor-donor or acceptor motif", "disallowed_scaffolds": ["bis-anilino pyrimidine", "indolinone", "staurosporine-like bisindole", "4-anilinoquinazoline"]}, "property_envelope": {"molecular_weight": {"min": 250, "max": 450}, "logP": {"min": 2.0, "max": 3.5}, "tpsa": {"min": 40.0, "max": 75.0}, "hbd": {"min": 1, "max": 2}, "hba": {"min": 2, "max": 6}, "rotatable_bonds": {"max": 5}, "filters": ["PAINS", "BRENK"]}, "count": 25}

---

## [77] source=multitask_sft_big

**USER:** Design 20 de-novo CDR-H3 loop sequences grafted into a humanized VH3-23/IGHJ4 antibody framework to bind the SARS-CoV-2 Spike receptor-binding domain (PDB: 7K8Z, focusing on epitope residues 484–505). CDR-H3 loop length should be between 12 and 16 residues. Designs must avoid post-translational liabilities (no N-linked glycosylation motifs [N-X-S/T, X!=P], no DP/DG cleavage motifs, and at most 1 Met or Trp), maintain a loop net charge between -1 and +2 at pH 7.4, and exhibit low hydrophobicity to ensure high developability.

**ASSISTANT:** {"stage": "generate", "target": "SARS-CoV-2 Spike RBD (PDB: 7K8Z, epitope residues 484-505)", "scaffold_policy": "Fixed human VH3-23/IGHJ4 heavy chain framework, variable CDR-H3 graft", "property_envelope": {"cdr_h3_length": "12-16 residues", "net_charge_at_pH_7_4": "-1 to +2", "excluded_motifs": ["N[^P][ST]", "DP", "DG"], "max_tryptophan_methionine_count": 1, "hydrophobicity": "low"}, "count": 20}

---

## [78] source=multitask_sft_big

**USER:** Design 10 novel macrocyclic peptide binders targeting the p53-binding domain of human MDM2 (PDB: 1YCR). The peptides should be 8 to 12 residues in length, head-to-tail or sidechain-to-sidechain cyclized, and present a hydrophobic triad mimicking the native p53 Phe19-Trp23-Leu26 binding motif. Ensure predicted binding affinity Kd < 50 nM, molecular weight between 900 and 1600 Da, net charge between 0 and +2 at physiological pH, and clogP between 1.0 and 4.0 to promote cellular permeability.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 p53-binding cleft (PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptide (head-to-tail or sidechain-to-sidechain cyclization), 8-12 amino acids, presenting Phe-Trp-Leu mimicking pharmacophore", "property_envelope": {"peptide_length": "8-12 amino acids", "molecular_weight_Da": [900, 1600], "predicted_kd_nM": "< 50", "net_charge_pH_7_4": [0, 2], "clogP": [1.0, 4.0]}, "count": 10}

---

## [79] source=multitask_sft_big

**USER:** Generate 25 novel scaffold designs targeting a kinase ATP-binding site. The designs must avoid standard hinge-binding cores such as quinazolines or 2,4-diaminopyrimidines. Ensure drug-like properties with MW 350-480 Da, logP 2.0-4.5, TPSA 60-100 Å², rotatable bonds <= 6, and include donor-acceptor functionality capable of hinge hydrogen bonding.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP-binding site", "scaffold_policy": {"mode": "de_novo", "exclude_known_chemotypes": ["quinazoline", "2,4-diaminopyrimidine"]}, "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "logP": {"min": 2.0, "max": 4.5}, "TPSA": {"min": 60, "max": 100}, "rotatable_bonds": {"max": 6}, "hinge_binding_motifs": {"min_HBD": 1, "min_HBA": 1}}, "count": 25}

---

## [80] source=multitask_sft_big

**USER:** Generate 50 novel, diverse heterocyclic core scaffolds for kinase inhibitors targeting CDK4. The designs must be distinct from standard purine, pyrimidine, and pyrido[2,3-d]pyrimidine chemotypes while incorporating a bidentate donor-acceptor hinge-binding motif. Keep the core fragments within standard drug-like property limits: MW between 250 and 400 Da, cLogP 1.5 to 3.5, TPSA between 50 and 90 Å², HBD ≤ 3, and HBA ≤ 6.

**ASSISTANT:** {"stage": "generate", "target": "CDK4", "scaffold_policy": {"requirement": "novel hinge-binding heterocyclic core", "exclude_known_motifs": ["purine", "pyrimidine", "pyrido[2,3-d]pyrimidine"], "features": ["bidentate donor-acceptor hinge-binding motif"]}, "property_envelope": {"mw": {"min": 250, "max": 400}, "clogp": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 50.0, "max": 90.0}, "hbd": {"max": 3}, "hba": {"max": 6}}, "count": 50}

---

## [81] source=multitask_sft_big

**USER:** Generate 50 de novo CDR-H3 loop candidates to target the extracellular domain of HER2, using the Trastuzumab heavy chain variable framework (PDB: 1N8Z). The designed H3 loops should have a length between 10 and 16 residues, demonstrate predicted binding affinity pKd >= 8.5, predicted loop stability ddG < -2.0 kcal/mol, a humanness OAS score >= 0.85, and low aggregation propensity (SAP score < 10).

**ASSISTANT:** {"stage": "generate", "target": "HER2 extracellular domain (PDB: 1N8Z)", "scaffold_policy": "Trastuzumab VH framework (fixed CDR-H1, CDR-H2, and framework regions; de-novo CDR-H3 generation)", "property_envelope": {"cdr_length": [10, 16], "predicted_binding_pKd": ">= 8.5", "loop_stability_ddG_kcal_mol": "< -2.0", "humanness_score": ">= 0.85", "spatial_aggregation_propensity_sap": "< 10"}, "count": 50}

---

## [82] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small molecules designed to minimize hERG liability (predicted hERG IC50 > 10 µM) while maintaining optimal lipophilicity with a clogP between 1.5 and 3.0. Filter for MW ≤ 450 Da and TPSA between 40 and 100 Å².

**ASSISTANT:** {"stage": "generate", "target": "hERG (off-target safety)", "scaffold_policy": "free", "property_envelope": {"clogP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 40, "max": 100}}, "count": 50}

---

## [83] source=multitask_sft_big

**USER:** We are developing PROTAC degraders targeting BRD4 by coupling a (+)-JQ1 carboxylic acid warhead to a VHL ligand (VH032 amine derivative). Standard aliphatic and PEG linkers have shown poor ternary complex stability and excessive conformational flexibility. Please generate 20 novel, partially rigidified linkers connecting these two specified exit vectors. The resulting full PROTAC conjugates should satisfy the following property criteria: overall molecular weight < 1050 Da, linker-specific rotatable bond count between 4 and 10, full molecule cLogP between 2.0 and 5.0, TPSA < 210 Å², and absence of labile ester or hydrazine linkages.

**ASSISTANT:** {"stage": "generate", "target": "BRD4/VHL", "scaffold_policy": "fixed warhead ((+)-JQ1 derivative) and fixed E3 ligand (VH032 derivative) with de-novo linker design bridging specified attachment vectors", "property_envelope": {"full_MW_max": 1050, "cLogP_range": [2.0, 5.0], "TPSA_max": 210.0, "linker_rotatable_bonds_range": [4, 10], "undesired_motifs": ["ester", "hydrazine"]}, "count": 20}

---

## [84] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loop variants against the human Claudin-18.2 extracellular loop 1 (ECL1) presented on a humanized VH3-23/JH4 framework scaffold. The framework and CDR-H1/H2 regions must remain fully fixed. Loop length should be restricted to 11–16 amino acids. Candidates should exhibit high predicted affinity (estimated Kd < 20 nM), avoid N-glycosylation motifs (N-X-[S/T], X!=P), unpaired cysteines, and cleavage sites, with net charge at neutral pH between -1 and +2 and low hydrophobic patch surface area to minimize aggregation risks.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Claudin-18.2", "epitope": "Extracellular loop 1 (ECL1)", "species": "Homo sapiens"}, "scaffold_policy": {"framework": "Human VH3-23/JH4", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "length_range": [11, 16]}, "property_envelope": {"predicted_kd_nm": "< 20", "net_charge_ph7": [-1, 2], "motif_exclusions": ["N[^P][ST]", "C"], "aggregation_risk": "low"}, "count": 50}

---

## [85] source=multitask_sft_big

**USER:** Generate 10 de-novo RNA aptamer sequences targeting the catalytic domain of human PCSK9 (UniProt Q8NBP7). Sequences should be 40 to 50 nucleotides in length, fold into stable secondary structures with a predicted minimum free energy (ΔG) <= -15.0 kcal/mol at 37°C, maintain a GC content between 40% and 60%, and avoid poly-U runs greater than 4 consecutive uridines. Prioritize designs with high predicted target affinity (estimated Kd < 50 nM).

**ASSISTANT:** {"stage": "generate", "target": "Human PCSK9 catalytic domain (UniProt: Q8NBP7)", "scaffold_policy": "de_novo; RNA sequence length 40-50 nt; no fixed primer sequences", "property_envelope": {"target_affinity_Kd_nM": "<50", "mfe_delta_G_kcal_per_mol": "<=-15.0", "gc_content_pct": [40, 60], "max_consecutive_homopolymer": {"U": 4}}, "count": 10}

---

## [86] source=multitask_sft_big

**USER:** Design 20 novel, conformationally restricted linkers connecting the BRD4 inhibitor JQ1 to the VHL E3 ligase ligand VH032. The linker should connect the JQ1 carboxylic ester exit vector to the terminal amine vector of VH032. Avoid purely linear alkyl or extended PEG motifs; favor rigidifying heterocycles, spirocyclic, or bicyclic linkers with an effective span of 8–14 Å (approx. 6–12 linear atoms). Ensure the complete PROTAC molecules maintain MW < 1050 Da, cLogP between 2.5 and 5.0, TPSA < 210 Å², and total linker rotatable bonds ≤ 8 to support cellular permeability.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 (BD1/BD2) and VHL (von Hippel-Lindau) E3 ligase", "scaffold_policy": "Keep JQ1 warhead and VH032 recruiter invariant at specified exit vectors; generate de novo linkers enriched in rigidifying motifs (spirocycles, piperazines, bicyclic rings) and depleted of unsubstituted alkyl/PEG chains", "property_envelope": {"linker_atom_length": [6, 12], "linker_effective_distance_angstrom": [8.0, 14.0], "linker_rotatable_bonds": "<= 8", "molecular_weight": "< 1050", "clogp": [2.5, 5.0], "tpsa": "< 210"}, "count": 20}

---

## [87] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamer sequences targeting human alpha-thrombin. The aptamers should be between 35 and 45 nucleotides long, with a GC content between 45% and 60%. Ensure stable secondary structure formation with a predicted minimum free energy (MFE) of less than -12.0 kcal/mol, avoid homopolymer runs longer than 4 consecutive bases, and optimize for predicted target binding affinity with Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin", "scaffold_policy": null, "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "gc_content": {"min": 0.45, "max": 0.6}, "max_homopolymer_length": 4, "minimum_free_energy_kcal_mol": {"max": -12.0}, "predicted_kd_nM": {"max": 50.0}}, "count": 8}

---

## [88] source=multitask_sft_big

**USER:** Generate 25 novel, conformationally constrained PROTAC linkers to connect our JQ1-derived BRD4 warhead (via terminal alkylamine exit vector) to the VH032 VHL ligase binder (via phenolic ether exit vector). Linkers must be 8-16 atoms in chain length, incorporate rigidifying spirocyclic or small heterocycles (e.g., piperazine, azetidine) rather than flexible poly-PEG chains, keep linker MW between 120 and 320 Da, maintain linker rotatable bonds <= 7, and ensure the resulting PROTACs have predicted clogP < 5.5 and TPSA < 180 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL", "scaffold_policy": "De novo linkers bridging JQ1 amine to VH032 phenolic oxygen; must contain rigidifying heterocycles/spirocycles; exclude continuous flexible alkyl/PEG motifs", "property_envelope": {"linker_chain_length_atoms": [8, 16], "linker_mw": [120, 320], "linker_rotatable_bonds": "<= 7", "clogp": "< 5.5", "tpsa": "< 180"}, "count": 25}

---

## [89] source=multitask_sft_big

**USER:** Design 25 de-novo PROTAC linkers connecting a BRD4-targeting warhead (attached via a secondary aliphatic amine handle) and a VHL E3 ligase ligand (attached via a phenolic ether handle). Linkers must span an extended path length of 8 to 16 linear atoms, avoid ester bonds and hydrazones, maintain overall PROTAC cLogP between 1.5 and 4.5, TPSA under 180 Å², and have between 6 and 14 rotatable bonds within the linker region.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL E3 ligase PROTAC system", "scaffold_policy": "Bifunctional linker design between specified exit vectors: aliphatic amine handle on BRD4 binder and phenolic oxygen on VHL ligand; exclude labile functional groups (esters, hydrazones)", "property_envelope": {"linker_chain_length_atoms": [8, 16], "clogP": [1.5, 4.5], "tpsa": [0, 180.0], "rotatable_bonds": [6, 14]}, "count": 25}

---

## [90] source=multitask_sft_big

**USER:** Design 20 novel, diverse PROTAC linkers connecting a CRBN ligand (pomalidomide 4-amino derivative) to a BRD4 warhead (JQ1 analog). The linkers must span between 10 and 16 rotatable/linear atoms to allow efficient ternary complex formation, avoid labile ester bonds or polyether-heavy PEG chains prone to oxidation, maintain overall PROTAC cLogP between 2.0 and 5.5, PROTAC MW < 1000 Da, and linker-alone MW < 250 Da with TPSA < 160 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN", "scaffold_policy": {"type": "linker_design", "warhead": "JQ1_derivative", "warhead_attachment_idx": "[Warhead]-C(=O)-[*]", "e3_ligand": "Pomalidomide_4_amino", "e3_attachment_idx": "[CRBN]-N(H)-[*]", "min_chain_length": 10, "max_chain_length": 16}, "property_envelope": {"protac_mw_max": 1000, "linker_mw_max": 250, "protac_clogp_min": 2.0, "protac_clogp_max": 5.5, "protac_tpsa_max": 160.0, "forbidden_functional_groups": ["ester", "peroxide", "acyl_halide"]}, "count": 20}

---

## [91] source=multitask_sft_big

**USER:** Design 20 novel bifunctional PROTAC linkers connecting our JQ1-derived BRD4 warhead (attached via terminal amide) to a VHL-1 ligase recruiting element (attached via phenoxy alkyl ether). Linkers should span 8 to 16 heavy atoms in linear length to achieve optimal ternary complex formation, incorporate rigidifying motifs such as piperazines, spirocycles, or alkynes to reduce conformational entropy, maintain a calculated LogP between 1.5 and 4.0, and avoid unstable bonds such as esters or hydrazones.

**ASSISTANT:** {"stage": "generate", "target": "BRD4/VHL ternary complex", "scaffold_policy": {"connection_point_warhead": "amide vector on JQ1 derivative", "connection_point_e3": "terminal alkyl on VHL-1 ligand", "linker_motifs": ["piperazine", "spirocycle", "alkyne", "PEG-alkyl hybrid"], "excluded_substructures": ["ester", "hydrazone", "peroxide", "azo"]}, "property_envelope": {"linker_heavy_atom_count": [8, 16], "clogp": [1.5, 4.0], "rotatable_bonds": "<= 8"}, "count": 20}

---

## [92] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptide binders targeting the p53 binding interface of MDM2 (PDB: 1YCR). The candidates should be 7 to 11 amino acids in length, cyclized via a head-to-tail peptide bond or a hydrocarbon staple, and must mimic the key p53 hydrophobic triad (Phe19, Trp23, Leu26). Filter for predicted Kd < 50 nM, topological polar surface area (tPSA) between 250 and 400 Å², and high proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 interaction interface, PDB: 1YCR)", "scaffold_policy": "macrocyclic peptide, 7-11 residues (head-to-tail or hydrocarbon-stapled backbone)", "property_envelope": {"predicted_kd_nM": "< 50", "sequence_length": "7-11 amino acids", "tPSA_A2": "250-400", "pharmacophore_constraints": "mimicry of p53 hot-spot triad (Phe19, Trp23, Leu26)", "proteolytic_stability": "high"}, "count": 20}

---

## [93] source=multitask_sft_big

**USER:** Generate 50 de novo macrocyclic peptides that bind the p53-interaction interface of human MDM2 (PDB: 1YCR). The peptides should consist of 8 to 14 residues (including canonical and non-canonical amino acids) cyclized via head-to-tail backbone cyclization or sidechain-to-sidechain stapling. Filter for predicted binding affinity Kd < 50 nM, molecular weight between 900 and 1600 Da, AlogP between 1.0 and 4.0, PSA < 350 Å², and at least 2 intramolecular hydrogen bonds to promote membrane permeability. Avoid unstable or chemically reactive motifs.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-interaction interface, PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptides (8-14 residues) cyclized via head-to-tail or sidechain stapling; canonical and non-canonical amino acids allowed; no reactive or unstable functional groups", "property_envelope": {"sequence_length": {"min": 8, "max": 14}, "affinity_Kd_nM": "< 50", "molecular_weight": {"min": 900, "max": 1600}, "logP": {"min": 1.0, "max": 4.0}, "tpsa_angstrom2": "< 350", "intramolecular_h_bonds": ">= 2"}, "count": 50}

---

## [94] source=multitask_sft_big

**USER:** Design 20 de novo CDR-H3 loop sequences grafted onto a Trastuzumab VH framework targeting the extracellular domain IV of human HER2 (PDB: 1N8Z). The CDR-H3 loop lengths should range between 12 and 16 amino acids. Candidate loops must have high predicted interface binding energy (docking score / predicted Kd < 10 nM), low hydrophobic patch surface area (< 800 Å²), a net charge between -1 and +2 at pH 7.4, and zero high-risk sequence liabilities (exclude motifs NG, NS, and DG).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human HER2 extracellular domain (Domain IV)", "pdb_id": "1N8Z"}, "scaffold_policy": {"framework": "Trastuzumab VH", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "length_range": [12, 16]}, "property_envelope": {"binding_affinity_predicted_kd_max_nM": 10.0, "hydrophobic_patch_area_max_A2": 800.0, "net_charge_pH_7_4": {"min": -1.0, "max": 2.0}, "forbidden_motifs": ["NG", "NS", "DG"]}, "count": 20}

---

## [95] source=multitask_sft_big

**USER:** Generate 50 de novo antibody CDR-H3 loop sequences designed to bind the HER2 extracellular domain (PDB: 1N8Z). Graft the loops into a human IGHV3-23/IGHJ4 framework, restricting CDR-H3 lengths to 12-16 amino acids. Ensure designs have high predicted affinity (pKd >= 8.5), a CDR-H3 net charge between -1 and +2 at pH 7.4, no N-linked glycosylation sequons (N-X-[S/T], X!=P), and low aggregation propensity (hydrophobic surface patch <= 350 Å²).

**ASSISTANT:** {"stage": "generate", "target": "HER2 extracellular domain (PDB: 1N8Z)", "scaffold_policy": "Human IGHV3-23/IGHJ4 framework with CDR-H3 loop length 12-16 residues", "property_envelope": {"predicted_pKd": ">= 8.5", "net_charge_cdr_h3": "[-1, +2]", "glycosylation_motifs": "none", "max_hydrophobic_patch_area_A2": 350}, "count": 50}

---

## [96] source=multitask_sft_big

**USER:** Generate 50 novel core scaffolds targeting the ATP-binding pocket of EGFR T790M/C797S mutant kinase. The molecules must be structurally distinct from standard quinazoline and aminopyrimidine chemotypes to circumvent existing IP, provide an accessible exit vector for covalent warhead attachment, and strictly adhere to drug-like space: MW 280-420 Da, LogP 1.5-3.5, TPSA < 90 Å², rotatable bonds ≤ 5, and synthetic accessibility score < 4.0.

**ASSISTANT:** {"stage": "generate", "target": "EGFR T790M/C797S mutant kinase ATP-binding pocket", "scaffold_policy": "novel non-quinazoline, non-aminopyrimidine core scaffolds with defined covalent attachment exit vectors", "property_envelope": {"molecular_weight": {"min": 280, "max": 420}, "logP": {"min": 1.5, "max": 3.5}, "tpsa": {"max": 90.0}, "rotatable_bonds": {"max": 5}, "sa_score": {"max": 4.0}}, "count": 50}

---

## [97] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamers targeting human VEGF-165 (Uniprot: P15692-4) for anti-angiogenic therapeutic exploration. Each sequence should have a 30-nt central recognition loop flanked by defined 5' (5'-GGGAGAAUUCAACUGCCAUCU-3') and 3' (5'-AGAGUAGUCUAGAGCCG-3') primer binding arms for RT-PCR amplification. Candidates must exhibit predicted binding affinity (Kd) below 20 nM, an MFE stability < -12 kcal/mol, GC content within 40-60%, and avoid homopolymeric runs of 4 or more identical nucleotides (especially G-tracts that form off-target G-quadruplexes).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Vascular endothelial growth factor A (VEGF-165)", "organism": "Homo sapiens", "uniprot_id": "P15692-4"}, "scaffold_policy": {"flanking_5_prime": "GGGAGAAUUCAACUGCCAUCU", "flanking_3_prime": "AGAGUAGUCUAGAGCCG", "variable_region_length": 30, "scaffold_type": "flanked_library_template"}, "property_envelope": {"total_length": 68, "gc_content_range": [0.4, 0.6], "target_kd_nM": "< 20", "mfe_kcal_per_mol": "< -12.0", "max_homopolymer_run": 3}, "count": 10}

---

## [98] source=multitask_sft_big

**USER:** Design 15 de novo macrocyclic peptide binders targeting the p53 interaction cleft of human MDM2 to inhibit the p53-MDM2 protein-protein interaction. The peptides should be head-to-tail or disulfide-bridged macrocycles between 7 and 11 amino acids in length. Ensure they satisfy a property envelope of MW 800-1400 Da, cLogP between 0.5 and 3.5, and tPSA between 180 and 280 Å².

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-binding cleft)", "scaffold_policy": "Macrocyclic peptide (head-to-tail or disulfide cyclization, 7-11 residues)", "property_envelope": {"molecular_weight": "800 - 1400 Da", "clogp": "0.5 - 3.5", "tpsa": "180 - 280 \u00c5\u00b2", "sequence_length": "7 - 11 residues"}, "count": 15}

---

## [99] source=multitask_sft_big

**USER:** Generate 5 de novo RNA aptamers targeting human VEGF-165. Sequences must be 30 to 45 nucleotides long, maintain a GC content between 40% and 60%, have predicted secondary structure minimum free energy (MFE) <= -10.0 kcal/mol, and show high binding affinity with an estimated Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "free", "property_envelope": {"length": {"min": 30, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_kcal_mol": {"max": -10.0}, "kd_nM": {"max": 50.0}}, "count": 5}

---

## [100] source=multitask_sft_big

**USER:** Design 50 de novo macrocyclic peptides targeting the MDM2-p53 interaction interface to disrupt p53 binding. Peptides must be cyclic via head-to-tail backbone cyclization or a disulfide bridge, with sequence lengths between 8 and 14 residues. Generated candidates should exhibit high predicted affinity (pKd > 8.0), molecular weight between 800 and 1600 Da, clogP between -1.0 and 3.5, and topological polar surface area (TPSA) < 350 Å² to support intracellular permeability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 interaction interface)", "scaffold_policy": "Macrocyclic peptides (8-14 natural or non-canonical amino acids, head-to-tail or disulfide-bridged cyclization)", "property_envelope": {"molecular_weight": [800, 1600], "clogP": [-1.0, 3.5], "TPSA_max": 350, "pKd_min": 8.0, "peptide_length": [8, 14]}, "count": 50}

---

## [101] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptide inhibitors targeting the p53-binding pocket of human MDM2 (PDB: 1YCR). Peptides should be 8 to 12 residues in length, cyclized via head-to-tail backbone amide bonds or hydrocarbon stapling, with predicted sub-micromolar binding affinity (Kd < 500 nM), molecular weight between 800 and 1600 Da, and clogP between -1.0 and 3.5.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 p53-binding cleft (PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptides (8-12 residues) cyclized via head-to-tail amide linkage or hydrocarbon staples", "property_envelope": {"Kd": "< 500 nM", "molecular_weight": "800 - 1600 Da", "clogP": "[-1.0, 3.5]", "sequence_length": "8-12 residues"}, "count": 20}

---

## [102] source=multitask_sft_big

**USER:** Please generate 5 de novo RNA aptamers targeting the receptor-binding domain (RBD) of SARS-CoV-2 spike protein with predicted high binding affinity (Kd < 50 nM). The aptamer sequences must be between 35 and 50 nucleotides in length, maintain a GC content between 40% and 60%, avoid homopolymer runs greater than 3 nucleotides, and possess stable secondary structure folding with a predicted minimum free energy (MFE) between -10.0 and -22.0 kcal/mol.

**ASSISTANT:** {"stage": "generate", "target": "SARS-CoV-2 spike protein RBD", "scaffold_policy": "none", "property_envelope": {"length": [35, 50], "gc_content": [0.4, 0.6], "mfe_delta_g_kcal_mol": [-22.0, -10.0], "max_homopolymer_length": 3, "predicted_kd_nM": "<= 50"}, "count": 5}

---

## [103] source=multitask_sft_big

**USER:** Design 20 novel, semi-rigid linkers to bridge a JQ1-derived BRD4 warhead and a VHL ligand (VH032). The connection points should link an alkyl amine exit vector on the warhead to the terminal benzylic carbon of the VH032 ligand. The linkers should have a path length of 8 to 14 heavy atoms, incorporate non-aromatic heterocyclic rings (such as piperazine, azetidine, or piperidine) to constrain conformational entropy, maintain a linker-only cLogP between 0.5 and 2.5, TPSA < 50 Å², and exclude hydrolytically unstable moieties like esters or hydrazones.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linker", "scaffold_policy": "Bifunctional linker bridging warhead exit vector [R1] to VH032 exit vector [R2], constrained to semi-rigid heterocyclic scaffolds (e.g., azetidine, piperidine, piperazine)", "property_envelope": {"linker_heavy_atom_length": "8-14", "linker_clogP": "0.5 - 2.5", "linker_tpsa": "< 50", "excluded_functional_groups": ["ester", "hydrazone", "reactive_halide"], "preferred_motifs": ["azetidine", "piperidine", "piperazine", "sp3-rich heterocycles"]}, "count": 20}

---

## [104] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692). Each sequence must be between 35 and 45 nucleotides in length, exhibit a predicted binding affinity (Kd) below 20 nM, maintain a GC content between 40% and 60%, and have a minimum folding free energy (ΔG) ≤ -12.0 kcal/mol at 37°C. Exclude sequences with homopolymer tracts longer than 4 consecutive identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human VEGF-165", "uniprot_id": "P15692"}, "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "affinity_kd_nM": {"max": 20}, "gc_content_pct": {"min": 40.0, "max": 60.0}, "folding_free_energy_kcal_mol": {"max": -12.0}, "max_homopolymer_length": 4}, "count": 5}

---

## [105] source=multitask_sft_big

**USER:** Generate 40 novel small molecules designed de novo with a balanced lipophilicity profile and minimized cardiotoxicity risks. Specifically, optimize logP to fall strictly within 1.5 to 3.0 and ensure low hERG channel affinity with predicted hERG pIC50 < 5.0 (IC50 > 10 µM). Compounds should maintain drug-like properties with MW < 450 Da and TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "novel", "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60.0, "max": 110.0}}, "count": 40}

---

## [106] source=multitask_sft_big

**USER:** Generate 20 de novo macrocyclic peptide binders targeting the Keap1 Kelch domain to disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should be 7 to 13 residues in length, cyclized via head-to-tail backbone amide coupling or a stable thioether/disulfide staple, and may include canonical residues along with simple D-amino acids to enhance proteolytic resistance. Aim for high predicted binding affinity (Kd < 200 nM), good serum stability (t1/2 > 4 hours), cLogP between -1.5 and 2.5, and low propensity for self-aggregation.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Nrf2 PPI interface)", "scaffold_policy": "Macrocyclic peptides (7-13 amino acids) with head-to-tail backbone amide cyclization or thioether/disulfide bridging; canonical L-amino acids with optional D-amino acid substitutions allowed", "property_envelope": {"length": [7, 13], "predicted_affinity_kd_nM": "<= 200", "serum_stability_half_life_hours": ">= 4", "clogp": [-1.5, 2.5], "aggregation_propensity": "low"}, "count": 20}

---

## [107] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loops grafted onto the Trastuzumab heavy chain framework to bind the extracellular domain of human HER2 (PDB: 1N8Z). The new CDR-H3 loops should have a length between 12 and 18 residues (Kabat definition positions 95-102). Filter out candidates with post-translational modification liabilities including N-glycosylation (NxS/T), deamidation (NG, NS), and aspartate isomerization (DG). Ensure the CDR-H3 net charge is between -1 and +2 at pH 7.4, hydrophobicity index is under 45%, and predicted binding affinity Kd is below 10 nM.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human HER2 extracellular domain", "pdb_id": "1N8Z"}, "scaffold_policy": {"base_framework": "Trastuzumab VH", "redesign_region": "CDR-H3", "definition": "Kabat", "positions": "H95-H102", "framework_status": "fixed"}, "property_envelope": {"cdr_length_range": [12, 18], "net_charge_range": [-1.0, 2.0], "max_hydrophobicity_percent": 45.0, "excluded_motifs": ["N[^P][ST]", "NG", "NS", "DG"], "target_affinity_kd_nm": 10.0}, "count": 50}

---

## [108] source=multitask_sft_big

**USER:** Generate 50 novel drug-like small molecules from scratch designed to minimize hERG liability while maintaining optimal lipophilicity. Compounds should have a logP between 1.5 and 3.0, predicted hERG IC50 > 10 µM (pIC50 < 5.0), MW < 450 Da, and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": "hERG (off-target safety)", "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 50}

---

## [109] source=multitask_sft_big

**USER:** Design 50 de novo small-molecule candidates targeting the 5-HT2A receptor that minimize cardiovascular safety risks, specifically avoiding hERG liability (hERG pIC50 < 5.0) while maintaining optimal lipophilicity with a LogP between 1.5 and 2.8. Ensure compounds are drug-like with MW between 250 and 450 Da and PSA between 40 and 90 Å².

**ASSISTANT:** {"stage": "generate", "target": "5-HT2A receptor", "scaffold_policy": "free", "property_envelope": {"logP": {"min": 1.5, "max": 2.8}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"min": 250, "max": 450}, "tpsa": {"min": 40, "max": 90}}, "count": 50}

---

## [110] source=multitask_sft_big

**USER:** Design 25 novel macrocyclic peptide binders targeting the Menin-MLL protein-protein interaction site. The peptides should be 8-14 amino acids in length, utilizing head-to-tail or hydrocarbon staple cyclization, with no more than 2 non-canonical residues. Desired specifications include predicted Kd < 50 nM, molecular weight < 1500 Da, net charge between 0 and +2, and high serum proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "Menin-MLL interface", "scaffold_policy": "macrocyclic peptide (8-14 residues, head-to-tail or staple cyclized, max 2 non-canonical amino acids)", "property_envelope": {"predicted_Kd": "< 50 nM", "molecular_weight": "< 1500 Da", "net_charge": "0 to +2", "serum_stability": "high"}, "count": 25}

---

## [111] source=multitask_sft_big

**USER:** Design 50 novel, semi-rigid PROTAC linkers connecting our BTK warhead (piperidine-4-yl exit vector) to a CRBN ligand (pomalidomide C4-amino exit vector). The linkers should replace typical flexible alkyl/PEG chains with rigid or heterocyclic motifs to improve cell permeability. Ensure the final PROTACs maintain MW < 1050 Da, LogP between 2.0 and 5.0, TPSA < 210 Å², and linker rotatable bonds ≤ 8.

**ASSISTANT:** {"stage": "generate", "target": "BTK / CRBN PROTAC", "scaffold_policy": "connect fixed BTK warhead and CRBN ligand exit vectors with de novo linkers", "property_envelope": {"MW": "< 1050", "LogP": [2.0, 5.0], "TPSA": "< 210", "linker_rotatable_bonds": "<= 8", "structural_preferences": "semi-rigid, heterocyclic motifs, avoid long flexible PEG/alkyl chains"}, "count": 50}

---

## [112] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamers targeting the human Interleukin-6 protein (IL-6, UniProt: P05231). The sequences must be 40 to 50 nucleotides in length, possess a GC content between 45% and 60%, and fold into a stable stem-loop structure with a minimum free energy (MFE) between -18.0 and -10.0 kcal/mol. Avoid homopolymer runs longer than 4 consecutive identical nucleotides. No fixed scaffold regions required.

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (UniProt: P05231)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 40, "max": 50}, "gc_content": {"min": 0.45, "max": 0.6}, "predicted_mfe_kcal_per_mol": {"min": -18.0, "max": -10.0}, "max_homopolymer_run": 4, "structural_motif": "stem-loop"}, "count": 10}

---

## [113] source=multitask_sft_big

**USER:** Design 25 de-novo linkers connecting the 4-position amino group of pomalidomide (CRBN binder) to the solvent-exposed piperidine nitrogen of our BTK kinase warhead. Linker length must span 8 to 16 linear atoms. For the linker fragment alone, ensure MW < 300 Da, cLogP between 0.5 and 3.0, and TPSA < 80 Å². Exclude hydrolytically labile or reactive functional groups such as esters, hydrazones, and aliphatic halides, and include a mix of PEG-like and rigid alkyl/heterocyclic motifs for conformational diversity.

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN PROTAC", "scaffold_policy": "fixed warhead (BTK inhibitor) and E3 ligase ligand (4-amino pomalidomide) with de-novo linker generation between defined exit vectors", "property_envelope": {"linker_chain_length_atoms": "8-16", "linker_mw": "< 300", "linker_clogp": "0.5 - 3.0", "linker_tpsa": "< 80", "excluded_motifs": ["ester", "hydrazone", "aliphatic_halide"]}, "count": 25}

---

## [114] source=multitask_sft_big

**USER:** Please generate 10 de novo RNA aptamers targeting human PCSK9 (UniProt Q8NBP7). The designed sequences should be between 30 and 45 nucleotides long, exhibit a predicted melting temperature (Tm) of at least 55°C, have a GC content between 40% and 60%, and contain no more than 4 consecutive identical nucleotides (especially avoiding G-quadruplex-forming poly-G or termination poly-U tracts). No fixed scaffold or primer binding region is required.

**ASSISTANT:** {"stage": "generate", "target": "Human Proprotein Convertase Subtilisin/Kexin Type 9 (PCSK9, UniProt: Q8NBP7)", "scaffold_policy": "none", "property_envelope": {"length": [30, 45], "gc_content_pct": [40.0, 60.0], "melting_temperature_celsius": ">= 55.0", "max_homopolymer_length": 4}, "count": 10}

---

## [115] source=multitask_sft_big

**USER:** Generate 50 novel, non-quinazoline kinase inhibitor core scaffolds targeting the ATP-binding site (hinge region) of EGFR C797S. Ensure type-I-like hinge-binding capacity with at least one hydrogen bond donor and one acceptor. Keep the core structures drug-like: MW between 300 and 450 Da, cLogP 2.0 to 4.0, TPSA between 60 and 100 Å², HBD ≤ 3, HBA ≤ 7, and rotatable bonds ≤ 6. Avoid PAINS, toxicophores, and known patented 4-anilinoquinazoline or aminopyrimidine chemotypes.

**ASSISTANT:** {"stage": "generate", "target": "EGFR C797S", "scaffold_policy": "Novel heterocyclic cores; exclude 4-anilinoquinazolines and 2,4-diaminopyrimidines; must possess a hinge-binding motif (donor-acceptor or donor-acceptor-donor)", "property_envelope": {"MW": [300, 450], "cLogP": [2.0, 4.0], "TPSA": [60, 100], "HBD": {"max": 3}, "HBA": {"max": 7}, "rotatable_bonds": {"max": 6}, "PAINS_filter": true, "reactive_groups": false}, "count": 50}

---

## [116] source=multitask_sft_big

**USER:** Design 8 de novo RNA aptamers targeting human Interleukin-6 (IL-6, UniProt P05231). The sequences should be 30 to 50 nucleotides in length without using predefined scaffold motifs. Target a predicted binding affinity (Kd) below 50 nM, an MFE folding free energy deltaG <= -15 kcal/mol, GC content between 40% and 60%, and limit homopolymer tracts of G or U to at most 4 consecutive bases.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Interleukin-6", "organism": "Homo sapiens", "uniprot_id": "P05231"}, "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 30, "max": 50}, "affinity_kd_nM": {"max": 50}, "mfe_folding_dG_kcal_mol": {"max": -15.0}, "gc_content": {"min": 0.4, "max": 0.6}, "max_homopolymer_run": {"G": 4, "U": 4}}, "count": 8}

---

## [117] source=multitask_sft_big

**USER:** Generate 50 novel CDR-H3 loop sequences (lengths 10 to 16 residues) grafted onto the Trastuzumab VH framework (fixing framework regions 1-94 and 103-119) targeted against the extracellular domain IV of human HER2 (PDB: 1N8Z). Optimize for interface shape complementarity and predicted binding affinity (predicted Kd < 20 nM / pKd > 7.7). Filter out sequences with developability liabilities, specifically avoiding unpaired cysteines, N-glycosylation motifs (N-X-S/T, X!=P), deamidation motifs (NG, NN), and ensure CDR-H3 net charge remains between -1 and +2 at pH 7.4.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human Epidermal Growth Factor Receptor 2 (HER2) Extracellular Domain", "uniprot_id": "P04626", "pdb_reference": "1N8Z", "epitope": "Domain IV"}, "scaffold_policy": {"framework": "Trastuzumab VH (IGHV3-23 / IGHJ4)", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3 (residues 1-94)", "FR-H4 (residues 103-119)"], "design_region": "CDR-H3", "length_range": [10, 16]}, "property_envelope": {"predicted_kd_nM": "<= 20", "unpaired_cysteines": 0, "n_glycosylation_motifs": 0, "deamidation_motifs": 0, "net_charge_pH_7_4": [-1, 2]}, "count": 50}

---

## [118] source=multitask_sft_big

**USER:** Please design 8 de-novo RNA aptamer candidates targeting human VEGF-165 (UniProt P15692). The RNA sequences should be 30 to 45 nucleotides long, exhibit a predicted dissociation constant (Kd) < 50 nM, maintain a secondary structure minimum free energy (MFE) between -18.0 and -8.0 kcal/mol, have a GC content between 40% and 60%, and contain no homopolymer tracts longer than 4 consecutive identical bases.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Vascular endothelial growth factor A (VEGF-165)", "uniprot_id": "P15692", "organism": "Homo sapiens", "type": "protein"}, "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "binding_affinity_kd_nM": {"max": 50.0}, "folding_mfe_kcal_mol": {"min": -18.0, "max": -8.0}, "gc_content_fraction": {"min": 0.4, "max": 0.6}, "max_homopolymer_length": 4}, "count": 8}

---

## [119] source=multitask_sft_big

**USER:** Design 50 de novo macrocyclic peptides (8 to 14 amino acids) targeting the p53 interaction pocket of human MDM2 (PDB: 1YCR). The peptides must utilize head-to-tail or hydrocarbon stapling cyclization to stabilize an alpha-helical conformation, mimic the hydrophobic interaction triad (Phe19, Trp23, Leu26), have an estimated Kd < 100 nM, molecular weight between 900 and 1800 Da, cLogP < 3.5, and at least 2 hydrogen bond donors/acceptors facing the solvent-exposed surface for solubility.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 p53-binding domain (PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptides (8\u201314 residues) stabilized via head-to-tail cyclization or hydrocarbon stapling enforcing an alpha-helical fold", "property_envelope": {"peptide_length": [8, 14], "molecular_weight": [900, 1800], "clogp_max": 3.5, "predicted_kd_nm_max": 100, "pharmacophore_features": ["Phe19_mimic", "Trp23_mimic", "Leu26_mimic"], "min_solvent_exposed_polar_groups": 2}, "count": 50}

---

## [120] source=multitask_sft_big

**USER:** Design 50 de-novo macrocyclic peptides targeting the Keap1 Kelch domain binding pocket to inhibit the Keap1-Nrf2 protein-protein interaction. Peptides should consist of 7 to 13 amino acids, incorporate a hydrocarbon or thioether macrocyclization strategy, and include unnatural amino acids for proteolytic stability. Desired properties include predicted Kd < 50 nM against Keap1, molecular weight between 800 and 1500 Da, LogP between -1.0 and 2.5, and low cytotoxicity.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Kelch-Nrf2 interaction site)", "scaffold_policy": "macrocyclic peptide, 7-13 residues, hydrocarbon or thioether staple cyclization, incorporation of unnatural amino acids", "property_envelope": {"molecular_weight": "800 - 1500 Da", "Kd": "< 50 nM", "logP": "-1.0 - 2.5", "proteolytic_stability": "high", "cytotoxicity": "low"}, "count": 50}

---

## [121] source=multitask_sft_big

**USER:** Design 15 de novo CDR-H3 loop sequences to bind the receptor-binding domain of human epidermal growth factor receptor 2 (HER2, PDB: 1N8Z) grafted onto the Trastuzumab heavy-chain variable domain (IGHV3-23 framework). Constrain CDR-H3 length to 12-16 residues. Ensure predicted binding energy (ddG) is below -35.0 REU, interface shape complementarity (Sc) is greater than 0.65, net CDR-H3 charge remains between -1 and +2 at pH 7.4, and filter out sequence liabilities including N-glycosylation (N-X-[S/T]), Asp isomerization (DG, DS), and unpaired cysteines.

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 (PDB: 1N8Z)", "scaffold_policy": "Trastuzumab heavy-chain framework (IGHV3-23), fixed framework with de novo CDR-H3 loop grafting", "property_envelope": {"cdr_h3_length": [12, 16], "predicted_binding_ddg_reu": "< -35.0", "shape_complementarity": "> 0.65", "net_charge_at_ph_7_4": [-1, 2], "sequence_liabilities_excluded": ["N-glycosylation (N-X-[S/T], X!=P)", "Asp isomerization (DG, DS)", "Unpaired cysteines"]}, "count": 15}

---

## [122] source=multitask_sft_big

**USER:** Design 25 de novo macrocyclic peptides targeting the Kelch domain of Keap1 to inhibit the Keap1-Nrf2 protein-protein interaction. The candidates should be macrocycles of 6 to 10 residues, utilizing head-to-tail amide or thioether/disulfide staple cyclization, with molecular weight under 1200 Da, cLogP between -2.0 and 2.5, TPSA < 350 Å², and maximum 8 hydrogen bond donors.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Keap1-Nrf2 PPI)", "scaffold_policy": "macrocyclic peptide backbone, 6-10 amino acid residues, cyclized via head-to-tail amide or side-chain staple (disulfide/thioether)", "property_envelope": {"molecular_weight": "< 1200 Da", "clogP": "[-2.0, 2.5]", "tpsa": "< 350 \u00c5\u00b2", "hbd": "<= 8", "sequence_length": "[6, 10]"}, "count": 25}

---

## [123] source=multitask_sft_big

**USER:** Design 50 novel, drug-like small molecules from scratch with favorable lipophilicity and minimal cardiac toxicity risk. The candidates should have a cLogP between 1.5 and 3.0, predicted hERG pIC50 below 5.0 (IC50 > 10 µM), molecular weight under 500 Da, and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "none", "property_envelope": {"cLogP": [1.5, 3.0], "hERG_pIC50": "< 5.0", "MW": "< 500", "TPSA": [60, 120]}, "count": 50}

---

## [124] source=multitask_sft_big

**USER:** Please generate 50 novel drug-like small molecules from scratch with an optimized safety and physicochemical profile. The compounds should have an optimal logP between 1.5 and 3.0, and demonstrate a strong safety margin against cardiotoxicity with predicted hERG pIC50 < 5.0 (IC50 > 10 µM). Keep molecular weight under 450 Da, TPSA between 50 and 120 Å², and avoid highly basic lipophilic amine motifs prone to hERG binding.

**ASSISTANT:** {"stage": "generate", "target": {"anti_target": "hERG (KCNH2)"}, "scaffold_policy": {"type": "de_novo", "forbidden_motifs": ["lipophilic_tertiary_amines", "p-basic_aryl_alkylamines"]}, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 50, "max": 120}, "rule_of_5_compliant": true}, "count": 50}

---

## [125] source=multitask_sft_big

**USER:** Design 15 novel macrocyclic peptides to disrupt the Keap1-Nrf2 protein-protein interaction by targeting the Kelch domain. The macrocycles should consist of 7 to 10 amino acid residues cyclized via a head-to-tail backbone amide bond or a stable thioether bridge. Please ensure the designs have molecular weights between 800 and 1300 Da, cLogP between -1.0 and 2.5, and TPSA under 350 Å².

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (disrupting Keap1-Nrf2 PPI)", "scaffold_policy": {"scaffold_class": "macrocyclic peptide", "length": "7-10 residues", "cyclization_chemistry": ["head-to-tail backbone amide", "thioether bridge"]}, "property_envelope": {"molecular_weight": "800 - 1300 Da", "clogP": "-1.0 to 2.5", "tpsa": "< 350 \u00c5\u00b2"}, "count": 15}

---

## [126] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 sequences grafted into a human IGHV3-23/IGHJ4 antibody framework targeting the receptor-binding domain of SARS-CoV-2 Spike (PDB: 7KMS, Chain A, epitope residues Arg403, Tyr453, Leu455, Phe486, Asn501). Keep the rest of the heavy chain and the entire light chain sequence fixed. Filter for CDR-H3 loop lengths between 10 and 16 residues, predicted ipTM > 0.80, net CDR-H3 charge between -1 and +2 at pH 7.4, and strictly eliminate liability motifs (N-glycosylation N-[^P]-[ST], deamidation NG/NN, and Asp isomerization DG/DS).

**ASSISTANT:** {"stage": "generate", "target": {"antigen": "SARS-CoV-2 Spike Receptor-Binding Domain (RBD)", "pdb_id": "7KMS", "target_chain": "A", "epitope_residues": ["ARG403", "TYR453", "LEU455", "PHE486", "ASN501"]}, "scaffold_policy": {"framework": "Human IGHV3-23 / IGHJ4", "fixed_regions": ["VH_FR1", "CDR-H1", "VH_FR2", "CDR-H2", "VH_FR3", "VH_FR4", "VL_all"], "design_region": "CDR-H3 (Kabat H95-H102)"}, "property_envelope": {"loop_length_range": [10, 16], "predicted_ipTM_min": 0.8, "net_charge_range": [-1.0, 2.0], "excluded_sequence_motifs": ["N[^P][ST]", "NG", "NN", "DG", "DS"]}, "count": 50}

---

## [127] source=multitask_sft_big

**USER:** Design 25 novel, diverse, drug-like PROTAC linkers to connect a BRD4-targeting JQ1 derivative (attachment at the free carboxylic acid/ester position) to a VHL E3 ligase ligand (VH032 derivative via the terminal hydroxyproline-associated phenyl methyl group). The linkers should avoid simple repetitive PEG or aliphatic chains, incorporating rigid motifs (e.g., piperazines, spirocycles, or alkynes) to reduce conformational entropy. Optimize for ternary complex formation with an exit-vector distance spanning 9 to 14 Å, maintain acceptable physicochemical properties (linker MW < 250 Da, cLogP between 0.5 and 3.0), and minimize hydrolytically labile bonds.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex (PROTAC linker)", "scaffold_policy": {"linker_type": "bifunctional_connector", "anchor_1": "JQ1-derived BET warhead exit vector", "anchor_2": "VH032-derived VHL ligand exit vector", "forbidden_motifs": ["linear alkyl chain > 5 atoms", "PEG chain > 3 repeats", "esters", "hydrazones", "reactive electrophiles"], "preferred_motifs": ["piperazine", "morpholine", "spirocyclic rings", "rigid alkynes", "1,4-disubstituted cycloalkanes"]}, "property_envelope": {"linker_length_angstroms": {"min": 9.0, "max": 14.0}, "linker_mw": {"max": 250}, "linker_clogp": {"min": 0.5, "max": 3.0}, "linker_rotatable_bonds": {"max": 8}, "linker_tpsa": {"min": 20, "max": 75}, "fraction_sp3": {"min": 0.4}}, "count": 25}

---

## [128] source=multitask_sft_big

**USER:** Generate 30 novel drug-like small molecules with optimized lipophilicity and low cardiotoxicity liability. Maintain clogP between 1.5 and 3.0, MW < 450 Da, and ensure high hERG safety with predicted hERG pIC50 < 5.0.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "novel", "property_envelope": {"logP": [1.5, 3.0], "MW": {"max": 450}, "hERG_pIC50": {"max": 5.0}}, "count": 30}

---

## [129] source=multitask_sft_big

**USER:** Design 50 novel small-molecule candidates with controlled lipophilicity and low cardiotoxicity liability. Aim for a clogP between 1.5 and 3.0 and minimized hERG channel inhibition (predicted hERG pIC50 < 5.0 or IC50 > 10 µM). Keep MW under 450 Da and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": "hERG (counter-target)", "scaffold_policy": null, "property_envelope": {"clogP": [1.5, 3.0], "hERG_pIC50": "< 5.0", "MW": "<= 450", "TPSA": [60, 120]}, "count": 50}

---

## [130] source=multitask_sft_big

**USER:** Design 20 de novo CDR-H3 loop sequences grafted onto a Trastuzumab (anti-HER2) framework targeting the extracellular domain of human HER2 (PDB: 1N8Z). Keep the light chain, heavy chain frameworks (FR1-FR4), and CDR-H1/H2 fixed. The generated CDR-H3 loops should have lengths between 10 and 16 residues, a net charge between -1.0 and +2.0 at pH 7.4, and no developability liabilities (avoid unpaired cysteines, N-linked glycosylation sequons Nx[S/T], Asp-Pro cleavage motifs, and poly-tryptophan stretches). Filter for predicted binding energy Rosetta dG_separated < -35.0 REU.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain", "pdb_id": "1N8Z", "organism": "Homo sapiens"}, "scaffold_policy": {"scaffold_name": "Trastuzumab", "fixed_regions": ["LC", "HC_FR1", "CDR-H1", "HC_FR2", "CDR-H2", "HC_FR3", "HC_FR4"], "redesign_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length_range": [10, 16], "net_charge_ph7_4": [-1.0, 2.0], "excluded_motifs": ["C", "N[^P][ST]", "DP", "WWW"], "predicted_binding_energy_reu": "< -35.0"}, "count": 20}

---

## [131] source=multitask_sft_big

**USER:** Generate 30 novel small molecules from scratch targeting drug-like chemical space with minimal cardiac liability. Compounds must demonstrate low hERG channel inhibition (predicted hERG pIC50 < 5.0) and optimal lipophilicity with a LogP between 1.5 and 3.0. Additionally, ensure MW <= 450 Da and TPSA between 60 and 110 Å² to support good oral bioavailability.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 60.0, "max": 110.0}}, "count": 30}

---

## [132] source=multitask_sft_big

**USER:** Design 20 de novo linkers connecting the BTK inhibitor warhead (ibrutinib-derived amine exit vector) to a cereblon (CRBN) E3 ligase binder (pomalidomide 4-amino exit vector). The linkers should feature diverse chemistries beyond standard pure PEG or aliphatic chains, such as rigidifying cycloalkyl or saturated heterocycle motifs. Linker atom count must be between 8 and 14 linear atoms. For the linker fragments alone, ensure MW < 250 Da, cLogP between 0.5 and 3.0, rotatable bonds between 4 and 9, and TPSA < 60 Å².

**ASSISTANT:** {"stage": "generate", "target": "BTK / CRBN PROTAC ternary complex", "scaffold_policy": "Bifunctional linker connecting ibrutinib warhead (piperidine/amine handle) to pomalidomide core (4-amino handle) with rigidifying heterocyclic or cycloalkyl inserts", "property_envelope": {"linker_atom_length": [8, 14], "linker_mw": "< 250 Da", "linker_clogP": [0.5, 3.0], "linker_rotatable_bonds": [4, 9], "linker_tpsa": "< 60 \u00c5\u00b2"}, "count": 20}

---

## [133] source=multitask_sft_big

**USER:** Please design 25 de novo macrocyclic peptide candidates targeting the Keap1 Kelch domain to disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should be 7 to 12 residues in length, cyclized either head-to-tail or via a staple/thioether bridge, and exhibit high predicted binding affinity (Kd < 100 nM). Ensure designs have a molecular weight under 1600 Da, tPSA < 450 Å², net charge between -1 and +2 at physiological pH, and incorporate non-canonical amino acids where appropriate to improve metabolic stability.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Keap1-Nrf2 PPI interface)", "scaffold_policy": {"structure_class": "macrocyclic peptide", "monomer_length": [7, 12], "cyclization_types": ["head-to-tail", "thioether", "stapled"], "residue_types": ["canonical", "non-canonical"]}, "property_envelope": {"MW_max": 1600, "tPSA_max": 450, "net_charge_range": [-1, 2], "affinity_Kd_nM": 100}, "count": 25}

---

## [134] source=multitask_sft_big

**USER:** Design 50 de-novo macrocyclic peptide binders targeting the PD-1 interaction surface on human PD-L1 (PDB: 4ZQK). The peptides should utilize a head-to-tail backbone cyclization with a sequence length of 8 to 13 amino acids, maximizing shape complementarity and polar contacts at the interface while maintaining MW between 900 and 1500 Da, cLogP from -1.0 to 2.5, and TPSA under 350 Å².

**ASSISTANT:** {"stage": "generate", "target": "Human PD-L1 (PD-1 binding site, PDB: 4ZQK)", "scaffold_policy": "Head-to-tail macrocyclic peptides (8-13 residues)", "property_envelope": {"molecular_weight": "900-1500 Da", "clogp": "-1.0 to 2.5", "tpsa": "< 350 \u00c5\u00b2", "sequence_length": "8-13 residues"}, "count": 50}

---

## [135] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops grafted onto the Trastuzumab VH framework to bind human HER2 receptor (PDB: 1N8Z). Keep the framework residues and remaining CDRs fixed, generating only the CDR-H3 loop (Chothia positions H95 to H102). CDR-H3 length should be constrained between 10 and 16 residues. Generated designs should have predicted pKd >= 8.5 against the target epitope, a net CDR charge between -1 and +2, less than 35% hydrophobic residues to reduce aggregation risk, and pass standard antibody developability filters.

**ASSISTANT:** {"stage": "generate", "target": {"identifier": "1N8Z", "molecule": "Human Epidermal Growth Factor Receptor 2 (HER2)", "binding_region": "Domain IV epitope"}, "scaffold_policy": {"framework": "Trastuzumab (anti-HER2 IgG1)", "fixed_regions": ["VL", "VH_FR1", "CDR-H1", "VH_FR2", "CDR-H2", "VH_FR3", "VH_FR4"], "redesign_region": "CDR-H3 (Chothia H95-H102)"}, "property_envelope": {"cdr_h3_length": [10, 16], "predicted_pKd": {"min": 8.5}, "net_charge": {"min": -1, "max": 2}, "hydrophobic_fraction_max": 0.35, "developability_flags": ["no_unpaired_cysteines", "low_polyreactivity", "no_canonical_glycosylation_motifs"]}, "count": 50}

---

## [136] source=multitask_sft_big

**USER:** Please generate 10 novel de-novo RNA aptamer sequences targeting human VEGF-165 (Vascular Endothelial Growth Factor 165). Each candidate should have a total length of 40 to 50 nucleotides, incorporating a 30-nt variable core flanked by fixed 5' and 3' primer-binding handles (5'-GGGAG- and -UCCCC-3' terminal clamps). Filter for high predicted target binding affinity (estimated Kd < 50 nM), a balanced GC content between 45% and 60%, and an ensemble secondary structure minimum free energy (MFE) between -18.0 and -10.0 kcal/mol at 37°C.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (Vascular Endothelial Growth Factor 165)", "scaffold_policy": "Variable central loop/region of 30 nt constrained by fixed 5' (GGGAG) and 3' (UCCCC) terminal stem-forming handles", "property_envelope": {"length_nt": [40, 50], "affinity_Kd_nM": "< 50", "gc_content_percent": [45, 60], "mfe_folding_kcal_mol": [-18.0, -10.0]}, "count": 10}

---

## [137] source=multitask_sft_big

**USER:** We are designing novel PROTAC degraders targeting BRD4 using a pomalidomide E3 ligase binder (4-amino exit vector) and a JQ1-derived warhead. Generate 50 de novo linkers bridging these two attachment points. The linkers should span 8 to 14 heavy atoms, incorporate semi-rigid motifs such as piperazine, saturated heterocycles, or alkynes to avoid purely flexible alkyl/PEG chains, and exclude hydrolytically unstable motifs like esters or hydrazones. The full PROTAC constructs should target a clogP between 3.0 and 5.5, TPSA < 180 Å², and rotatable bond count < 15 within the linker.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN PROTAC", "scaffold_policy": "Keep JQ1 warhead and pomalidomide E3 binder fixed at defined exit vectors; generate novel connecting linkers", "property_envelope": {"linker_heavy_atom_count": [8, 14], "linker_rotatable_bonds": "<= 15", "clogp": [3.0, 5.5], "tpsa": "<= 180", "structural_alerts": ["ester", "hydrazone", "peroxide", "acyl_halide"]}, "count": 50}

---

## [138] source=multitask_sft_big

**USER:** Generate 50 de novo linkers connecting our BTK warhead (attached via piperidine nitrogen at exit vector [*:1]) to a CRBN pomalidomide ligand (attached at the 4-position phenyl amine [*:2]). We want linkers that avoid floppy, linear PEG chains and instead introduce rigidifying heterocyclic or spirocyclic motifs (e.g., piperazine, morpholine, or azetidine-containing rings) to improve oral bioavailability. The linker path should span 8 to 14 atoms (approx. 10–16 Å). Keep total PROTAC MW < 950, linker-only cLogP between 0.5 and 3.0, rotatable bonds in the linker ≤ 8, and TPSA for the complete molecule < 220 Å².

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN PROTAC linker", "scaffold_policy": "Fix BTK warhead and CRBN ligand; grow de novo bifunctional linker between specified exit vectors [*:1] and [*:2] incorporating semi-rigid aliphatic/heterocyclic scaffolds", "property_envelope": {"linker_atom_length": "8-14", "linker_cLogP": "0.5 - 3.0", "linker_rotatable_bonds": "<= 8", "protac_MW": "< 950", "protac_TPSA": "< 220"}, "count": 50}

---

## [139] source=multitask_sft_big

**USER:** Design 10 novel CDR-H3 loop sequences to be grafted onto a Trastuzumab human IgG1 framework targeting the extracellular domain of human HER2 (PDB: 1N8Z). Maintain the native framework regions and CDR-H1/H2 loops intact. The new CDR-H3 loops must have a length between 12 and 16 residues, avoid liabilities including unpaired cysteines, N-glycosylation sites (N-X-S/T, X!=P), and high hydrophobic patches (HI < 4.0), while achieving a predicted binding free energy (ddG) of less than -15.0 kcal/mol and a developability score above 0.8.

**ASSISTANT:** {"stage": "generate", "target": "Human epidermal growth factor receptor 2 (HER2) extracellular domain (PDB: 1N8Z)", "scaffold_policy": "Fix Trastuzumab VH/VL framework and CDR-H1/H2/L1/L2/L3 loops; generate de novo CDR-H3 sequence/conformation only", "property_envelope": {"cdr_h3_length": [12, 16], "predicted_binding_ddg_kcal_per_mol": "< -15.0", "developability_score": ">= 0.8", "motifs_excluded": ["N[^P][ST]", "C"], "hydrophobicity_index": "< 4.0"}, "count": 10}

---

## [140] source=multitask_sft_big

**USER:** Design 20 novel, core-differentiated kinase inhibitor scaffolds targeting LRRK2. The molecules must possess a hinge-binding motif distinct from canonical adenine-mimetic scaffolds (avoid aminopyrimidine, indolinone, and bisindolylmaleimide chemotypes). Optimize for brain penetration: MW < 450, cLogP 2.0–3.5, tPSA < 80 Å², HBD ≤ 1, HBA ≤ 5, and RotB ≤ 5.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 kinase", "scaffold_policy": "novel hinge-binding cores; exclude aminopyrimidine, indolinone, and bisindolylmaleimide chemotypes", "property_envelope": {"molecular_weight_max": 450, "clogp_min": 2.0, "clogp_max": 3.5, "tpsa_max": 80, "hbd_max": 1, "hba_max": 5, "rotatable_bonds_max": 5, "cns_penetrant": true}, "count": 20}

---

## [141] source=multitask_sft_big

**USER:** Please generate 15 de novo CDR-H3 loop sequences targeting the human TROP2 extracellular domain (PDB ID: 7E3M). Graft the loops into a human VH3-23 / JH4 framework with fixed CDR-H1, CDR-H2, and cognate light chain. Constrain the CDR-H3 length to 12-16 amino acids (IMGT numbering). Ensure the generated candidates have predicted high affinity (Kd < 50 nM), contain no unpaired cysteines or N-glycosylation motifs (N-X-S/T, X!=P), and maintain low hydrophobicity to minimize aggregation risk.

**ASSISTANT:** {"stage": "generate", "target": "Human TROP2 extracellular domain (PDB: 7E3M)", "scaffold_policy": "Fixed human VH3-23/JH4 framework and fixed CDR-H1/H2 and VL; de novo redesign restricted to CDR-H3 (IMGT positions 105-117)", "property_envelope": {"cdr_h3_length": "12-16 residues", "predicted_kd": "< 50 nM", "sequence_liabilities": {"unpaired_cysteines": 0, "n_glycosylation_motifs": 0}, "aggregation_propensity": "low / favorable hydrophobicity profile"}, "count": 15}

---

## [142] source=multitask_sft_big

**USER:** Please design 8 de novo RNA aptamers targeting human Interleukin-6 (IL-6, UniProt: P05231). Sequences should be 35 to 45 nucleotides in length and compatible with 2'-fluoro-modified pyrimidines for serum stability. Desired candidates must have predicted binding affinity Kd < 50 nM against IL-6, folding free energy (ΔG) between -18.0 and -10.0 kcal/mol, GC content between 40% and 60%, and low off-target predicted cross-reactivity to human serum albumin.

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (IL-6, UniProt: P05231)", "scaffold_policy": "de novo design of single-stranded RNA sequences (35-45 nt) with 2'-fluoro pyrimidine modifications", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "affinity_kd_nm": {"max": 50}, "folding_delta_g_kcal_mol": {"min": -18.0, "max": -10.0}, "gc_content_pct": {"min": 40.0, "max": 60.0}, "counter_targets": ["Human Serum Albumin (HSA)"]}, "count": 8}

---

## [143] source=multitask_sft_big

**USER:** Generate 25 novel de novo head-to-tail macrocyclic peptides targeting the p53-binding cleft of human MDM2 (PDB: 1YCR). The designs should be 7 to 10 amino acids in length and feature hydrophobic motifs mimicking the critical p53 hot-spot residues (Phe19, Trp23, Leu26), allowing non-canonical aromatic or aliphatic amino acids. Candidates must have a clogP between 1.0 and 4.5, tPSA < 220 Å², net charge from -1 to +1 at physiological pH, and a predicted docking/binding affinity stronger than the native p53 peptide.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 p53-binding interface (PDB: 1YCR)", "scaffold_policy": {"type": "macrocyclic_peptide", "cyclization": "head-to-tail backbone amide", "sequence_length": [7, 10], "motif_requirements": "mimic Phe19-Trp23-Leu26 hydrophobic triad, permitting non-canonical hydrophobic/aromatic residues"}, "property_envelope": {"clogP": [1.0, 4.5], "tPSA_max": 220.0, "net_charge": [-1, 1], "binding_affinity": "< wt p53 reference docking score"}, "count": 25}

---

## [144] source=multitask_sft_big

**USER:** Generate 40 novel drug-like small molecules targeting the serotonin 5-HT2A receptor with optimized lipophilicity and a low cardiotoxicity profile. Ensure calculated logP (cLogP) is restricted between 2.0 and 3.2, and enforce hERG safety with predicted hERG pIC50 < 5.0 (IC50 > 10 µM). Maintain molecular weight under 450 Da and a synthetic accessibility score below 4.0.

**ASSISTANT:** {"stage": "generate", "target": "5-HT2A receptor", "scaffold_policy": "novel", "property_envelope": {"cLogP": [2.0, 3.2], "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "SA_score": {"max": 4.0}}, "count": 40}

---

## [145] source=multitask_sft_big

**USER:** Generate 20 de novo macrocyclic peptide candidates targeting the Keap1 Kelch domain to disrupt the Keap1-Nrf2 protein-protein interaction. The peptides should be 6 to 10 residues in length, cyclized via a head-to-tail backbone amide bond or a thioether staple. Incorporate both canonical and non-canonical amino acids to enhance metabolic stability and shape complementarity. Filter for drug-like macrocyclic properties: MW < 1200 Da, topological polar surface area (TPSA) < 350 Å², and predicted binding affinity Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (disrupting the Keap1-Nrf2 interaction)", "scaffold_policy": {"topology": "macrocycle", "sequence_length": [6, 10], "cyclization_type": ["head-to-tail amide bond", "thioether staple"], "allowed_monomers": ["canonical amino acids", "non-canonical amino acids"]}, "property_envelope": {"molecular_weight_max": 1200, "tpsa_max": 350, "predicted_kd_max_nm": 50}, "count": 20}

---

## [146] source=multitask_sft_big

**USER:** Design 25 novel drug-like small molecules with favorable cardiac safety profiles and balanced lipophilicity. Compounds should have a clogP between 1.5 and 3.0, minimized hERG liability (predicted hERG IC50 > 10 uM), molecular weight under 450 Da, and topological polar surface area (TPSA) between 60 and 110 Å² to minimize QT prolongation risk while maintaining membrane permeability.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "novel", "property_envelope": {"clogP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 110}}, "count": 25}

---

## [147] source=multitask_sft_big

**USER:** Design 10 novel 40-nucleotide RNA aptamers targeting human VEGF-165. The sequences should have a GC content between 45% and 60%, a predicted minimum free energy (MFE) of secondary structure folding below -15 kcal/mol, and strong predicted binding affinity with a Kd under 50 nM. No fixed flanking primer regions are needed.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "none", "property_envelope": {"length_nt": 40, "gc_content_pct": {"min": 45, "max": 60}, "mfe_kcal_per_mol": {"max": -15.0}, "kd_nm": {"max": 50.0}}, "count": 10}

---

## [148] source=multitask_sft_big

**USER:** Please design 20 de novo CDR-H3 loops grafted onto the human IGHV3-23/IGHJ4 framework to target the receptor-binding domain (RBD) of SARS-CoV-2 Spike (PDB: 6M0J, Chain A). The CDR-H3 loop length should be constrained between 12 and 16 residues (Chothia definition). Filter designs for high predicted binding interface confidence (ipTM > 0.8), zero unpaired cysteines, CDR-H3 net charge between -1 and +2 at pH 7.4, and hydrophobic patch surface area below 500 Å² to minimize aggregation risk.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike Receptor-Binding Domain (RBD)", "structure_reference": "PDB: 6M0J", "target_chain": "A", "epitope": "ACE2-binding interface"}, "scaffold_policy": {"framework": "Human IGHV3-23 / IGHJ4", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "design_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [12, 16], "unpaired_cysteines": 0, "net_charge_pH_7_4": [-1.0, 2.0], "hydrophobic_patch_area_A2": {"max": 500}, "ipTM": {"min": 0.8}}, "count": 20}

---

## [149] source=multitask_sft_big

**USER:** Generate 25 novel drug-like small molecules with optimized lipophilicity and minimal cardiotoxicity risk. Maintain a cLogP between 1.5 and 2.8 and ensure high hERG safety margins with a predicted hERG IC50 > 10 µM. Keep molecular weight under 450 Da and TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"clogp": {"min": 1.5, "max": 2.8}, "herg_ic50_um": {"min": 10.0}, "molecular_weight": {"max": 450.0}, "tpsa": {"min": 60.0, "max": 110.0}}, "count": 25}

---

## [150] source=multitask_sft_big

**USER:** Design 50 novel, drug-like de novo chemical scaffolds targeting the ATP-binding pocket of Bruton's Tyrosine Kinase (BTK) C481S mutant. The scaffolds must be distinct from standard ibrutinib (pyrazolopyrimidine) and acalabrutinib (imidazopyrazine) cores to circumvent existing IP, but must contain a competent hinge-binding pharmacophore (at least one H-bond donor and one acceptor). Filter compounds to satisfy oral drug-likeness: MW between 350 and 480 Da, LogP between 2.0 and 4.0, TPSA between 60 and 110 Å², and rotatable bonds ≤ 5.

**ASSISTANT:** {"stage": "generate", "target": "Bruton's Tyrosine Kinase (BTK) C481S mutant", "scaffold_policy": "Novel heterocyclic cores; exclude pyrazolopyrimidine and imidazopyrazine backbones; require an ATP-hinge-binding motif with \u22651 donor and \u22651 acceptor", "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "logP": {"min": 2.0, "max": 4.0}, "tpsa": {"min": 60, "max": 110}, "rotatable_bonds": {"max": 5}}, "count": 50}

---

## [151] source=multitask_sft_big

**USER:** Please design 5 de novo RNA aptamer sequences that bind human Interleukin-6 (IL-6, UniProt P05231) with high affinity. The aptamers should be 35 to 45 nucleotides in length, maintain a GC content between 40% and 60%, fold into a stable stem-loop secondary structure with a predicted minimum free energy (MFE) below -12 kcal/mol, and have an estimated dissociation constant (Kd) under 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (IL-6, UniProt P05231)", "scaffold_policy": "de novo single-stranded RNA with stem-loop architecture", "property_envelope": {"length_nt": [35, 45], "gc_content_percent": [40.0, 60.0], "mfe_kcal_mol": {"max": -12.0}, "affinity_kd_nm": {"max": 50.0}}, "count": 5}

---

## [152] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like kinase inhibitor scaffolds targeting the ATP-binding cleft of mutant EGFR (L858R/T790M/C797S). The designs must incorporate a novel hinge-binding chemotype distinct from classical quinazoline, aminopyrimidine, or pyrazolopyrimidine cores. Restrict physicochemical properties to MW 350-480 Da, cLogP 2.0-4.0, TPSA 60-100 Å², HBD <= 2, and RotB <= 6.

**ASSISTANT:** {"stage": "generate", "target": "EGFR (L858R/T790M/C797S)", "scaffold_policy": {"novelty": "de_novo", "required_motifs": ["hinge_binding_heterocycle"], "excluded_scaffolds": ["quinazoline", "aminopyrimidine", "pyrazolopyrimidine"]}, "property_envelope": {"MW": [350, 480], "cLogP": [2.0, 4.0], "TPSA": [60.0, 100.0], "HBD": [0, 2], "RotB": [0, 6]}, "count": 50}

---

## [153] source=multitask_sft_big

**USER:** Design 20 novel bifunctional PROTAC linkers connecting a JQ1-derived BRD4 warhead (exit vector at the carboxylate position) to a VHL ligand (VH032 with a terminal phenolic or amine attachment). The linkers should feature 8 to 16 chain atoms, incorporating semi-rigid elements such as piperazines, spirocycles, or alkynes to control conformational flexibility. Linker molecular weight must be under 250 Da, resulting overall PROTAC cLogP between 2.5 and 5.0, TPSA < 180 Å², and the structures must strictly avoid hydrolyzable ester linkages or metabolically labile aliphatic chains.

**ASSISTANT:** {"stage": "generate", "target": "PROTAC linker (BRD4-JQ1 to VHL-VH032)", "scaffold_policy": "linker_design_between_exit_vectors", "property_envelope": {"linker_chain_length_atoms": [8, 16], "linker_MW": "<= 250", "overall_cLogP": [2.5, 5.0], "overall_TPSA": "<= 180", "preferred_motifs": ["piperazine", "spirocycle", "alkyne"], "excluded_functionalities": ["ester", "unsubstituted_long_alkyl_chain"]}, "count": 20}

---

## [154] source=multitask_sft_big

**USER:** Design 20 de-novo CDR-H3 loops targeting the catalytic domain of human PCSK9 (PDB: 2P4E). Scaffold them into a humanized VH3-23/JH4 framework with fixed CDR-H1 and CDR-H2. The designed CDR-H3 loops should have lengths between 11 and 15 residues (IMGT 105-117), avoid sequence liabilities (no N-glycosylation Nx[S/T], DG, or DP motifs), maintain an isoelectric net charge between -1 and +2 at pH 7.4, and exhibit high predicted structural confidence (ipTM >= 0.75, CDR-H3 pLDDT >= 80).

**ASSISTANT:** {"stage": "generate", "target": "Human PCSK9 catalytic domain (PDB: 2P4E)", "scaffold_policy": {"framework": "Human IGHV3-23*01 / IGHJ4*01", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "design_region": "CDR-H3 (IMGT positions 105-117)"}, "property_envelope": {"cdr_h3_length": [11, 15], "net_charge_pH_7_4": [-1.0, 2.0], "sequence_liability_filters": ["Nx[S|T]", "DG", "DP"], "iptm_min": 0.75, "cdr_h3_plddt_min": 80.0}, "count": 20}

---

## [155] source=multitask_sft_big

**USER:** Generate 50 novel small-molecule candidates for oral delivery with an optimized cardiotoxicity profile. I need de-novo structures that avoid hERG potassium channel liability, ideally with hERG IC50 > 30 µM (or pIC50 < 4.5). Optimize lipophilicity to an ideal drug-like window with clogP between 2.0 and 3.2, molecular weight between 300 and 450 Da, and PSA < 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "de_novo", "property_envelope": {"clogP": [2.0, 3.2], "hERG_IC50_uM": "> 30", "hERG_pIC50": "< 4.5", "MW": [300, 450], "TPSA": "< 120"}, "count": 50}

---

## [156] source=multitask_sft_big

**USER:** Design a de-novo CDR-H3 loop grafted onto the human VH3-23 / JH4 framework to target the receptor-binding motif of the SARS-CoV-2 Spike RBD (PDB ID: 6M0J, Chain E). Please generate 50 diverse CDR-H3 candidates with lengths between 12 and 18 amino acids. Candidates should exhibit high predicted interface binding affinity (interface dG < -35.0 REU, shape complementarity Sc > 0.65), adopt a stable kinked or extended stem conformation, avoid developability liabilities (no unpaired cysteines, no N-glycosylation motifs NxS/T, low aggregation propensity), and keep the remaining VH framework scaffold fixed.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike RBD", "pdb_id": "6M0J", "chain": "E", "epitope": "ACE2 receptor-binding motif (residues 438-506)"}, "scaffold_policy": {"framework": "human IGHV3-23*01 / IGHJ4*01", "cdr_region": "H3", "framework_mutation_allowed": false, "cdr_h1_h2_status": "fixed_native"}, "property_envelope": {"cdr_h3_length": [12, 18], "interface_dg_reu": {"max": -35.0}, "shape_complementarity_sc": {"min": 0.65}, "avoid_motifs": ["N[^P][ST]", "C", "NG", "NS"], "net_charge": {"min": -1.0, "max": 2.0}, "gravy_score": {"max": 0.0}}, "count": 50}

---

## [157] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamers targeting the extracellular domain of human HER2 (ErbB2). The sequences should be 35 to 45 nucleotides in length, possess a predicted minimum free energy (MFE) secondary structure stability with ΔG ≤ -10.0 kcal/mol, have a balanced GC content between 40% and 60%, and exhibit high predicted binding affinity (Kd < 50 nM). Please avoid homopolymer runs of 5 or more consecutive identical bases to ensure chemical synthesizability.

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 (ErbB2) extracellular domain", "scaffold_policy": "de novo single-stranded RNA, length 35-45 nt, unconstrained library architecture", "property_envelope": {"length": [35, 45], "predicted_binding_affinity_Kd_nM": "< 50", "mfe_delta_G_kcal_mol": "<= -10.0", "gc_content_percent": [40, 60], "max_homopolymer_run": "< 5"}, "count": 10}

---

## [158] source=multitask_sft_big

**USER:** Design 5 de-novo RNA aptamer sequences targeting human alpha-thrombin (UniProt: P00734). The candidates should be 30 to 45 nucleotides in length, possess a predicted binding affinity Kd < 50 nM, a GC content between 40% and 65%, and a folding minimum free energy (delta G) between -18.0 and -8.0 kcal/mol to ensure conformational stability without excessive rigidity. Use standard canonical RNA bases (A, C, G, U).

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin (UniProt: P00734)", "scaffold_policy": "de-novo canonical RNA (A, C, G, U)", "property_envelope": {"length_nt": {"min": 30, "max": 45}, "affinity_kd_nM": {"max": 50}, "gc_content_pct": {"min": 40.0, "max": 65.0}, "folding_delta_g_kcal_mol": {"min": -18.0, "max": -8.0}}, "count": 5}

---

## [159] source=multitask_sft_big

**USER:** Generate 50 novel drug-like small molecules de novo with optimized lipophilicity (cLogP 1.5 to 3.0) and minimal hERG channel liability (predicted hERG IC50 > 10 µM, pIC50 < 5.0). Maintain MW between 250 and 450 Da, TPSA < 120 Å², and minimize strongly basic aliphatic amines.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"cLogP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"min": 250, "max": 450}, "TPSA": {"max": 120.0}}, "count": 50}

---

## [160] source=multitask_sft_big

**USER:** Generate 5 novel RNA aptamer sequences targeting human vascular endothelial growth factor 165 (VEGF-165). The designed aptamers should be de novo single-stranded RNA constructs between 30 and 45 nucleotides in length, without fixed flanking primer binding arms. Ensure the sequences exhibit a predicted binding affinity Kd <= 50 nM, minimum free energy (MFE) folding ΔG <= -10.0 kcal/mol at 37°C, and a balanced GC content between 40% and 60%.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (P15692-4)", "scaffold_policy": "none", "property_envelope": {"length": {"min": 30, "max": 45}, "affinity_kd_nm": {"max": 50}, "mfe_folding_delta_g_kcal_mol": {"max": -10.0}, "gc_content_pct": {"min": 40.0, "max": 60.0}}, "count": 5}

---

## [161] source=multitask_sft_big

**USER:** Design 50 de-novo linkers connecting the aliphatic piperazine nitrogen of our BRD4 warhead to the phenolic oxygen of the VHL-1 ligand. The linkers should have an optimal path length of 8 to 14 heavy atoms and incorporate partially rigidified motifs (such as alkynyl, azetidine, pyrrolidine, or piperidine spacers) rather than linear aliphatic or PEG chains. For the isolated linker fragment, keep molecular weight under 250 Da, cLogP between 0.5 and 2.5, rotatable bond count <= 8, and TPSA between 15 and 60 Å² to ensure favorable cellular permeability and oral bioavailability potential.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC", "scaffold_policy": "bivalent_linker_generation(warhead_vector=BRD4_piperazine_N, E3_vector=VHL_phenol_O, prefer_heterocyclic_rigidification=true)", "property_envelope": {"linker_chain_length_heavy_atoms": [8, 14], "linker_MW": "<= 250", "linker_cLogP": [0.5, 2.5], "linker_nRot": "<= 8", "linker_TPSA": [15, 60]}, "count": 50}

---

## [162] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loop sequences for an antibody heavy chain targeting the Human HER2 extracellular domain (Domain IV, PDB: 1N8Z). Maintain the trastuzumab framework (VH3-23/JH4) and CDR-H1/H2 unchanged. The CDR-H3 length should be between 12 and 16 residues. Designs must demonstrate predicted high binding affinity (interface dG < -35 REU), retain the conserved C-terminal salt bridge/base motif (typically Asp101/Phe100), and filter out developability red flags: no unpaired cysteines, no N-glycosylation motifs (N-X-[S/T]), and a net CDR charge between -1 and +2.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human HER2 (ErbB2) extracellular domain", "structure_id": "1N8Z", "epitope": "Domain IV"}, "scaffold_policy": {"framework": "Human VH3-23 / JH4 (Trastuzumab backbone)", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4", "Light Chain"], "design_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [12, 16], "interface_energy_reu": "< -35.0", "unpaired_cysteines": 0, "n_glycosylation_motifs": 0, "net_cdr_charge": [-1, 2]}, "count": 50}

---

## [163] source=multitask_sft_big

**USER:** Design 20 novel bifunctional PROTAC linkers to conjugate an Ibrutinib-derived BTK warhead (via an exit vector at the 4-phenoxyphenyl amino group) to a Pomalidomide-based CRBN E3 ligase ligand (via the 4-position fluoro/amino exit vector). The linkers should provide an optimal balance of flexibility and conformational preorganization, spanning 9 to 15 heavy atoms in length. Maintain total PROTAC MW below 1100 Da, linker LogP between 1.0 and 3.5, and topological polar surface area (TPSA) below 220 Å² for the fully assembled ternary complex. Avoid easily metabolizable motifs such as esters, hydrazones, and unstable acetals, and include non-peptidic motifs like alkyl, PEG, piperazine, or triazole spacers to promote solubility and cellular permeability.

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN PROTAC", "scaffold_policy": "Connect designated exit vectors of ibrutinib-derived BTK inhibitor and pomalidomide E3 ligase recruiter using novel linear or semi-rigid linkers; prohibit hydrolytically labile bonds (esters, hydrazones, acyl hydrazides, hemiacetals)", "property_envelope": {"linker_chain_length_heavy_atoms": [9, 15], "full_protac_mw_max": 1100, "linker_clogp": [1.0, 3.5], "protac_tpsa_max": 220, "structural_motifs_allowed": ["alkyl", "PEG", "piperazine", "triazole", "oxetane", "cyclobutyl"]}, "count": 20}

---

## [164] source=multitask_sft_big

**USER:** Design 10 de-novo RNA aptamer sequences targeting human vascular endothelial growth factor 165 (VEGF-165, UniProt: P15692). Each sequence should be between 35 and 45 nucleotides in length, have a GC content between 40% and 60%, fold into a stable secondary structure with an MFE delta G < -12.0 kcal/mol, avoid homopolymer runs longer than 4 nucleotides, and achieve predicted binding affinity with a Kd below 25 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human vascular endothelial growth factor 165 (VEGF-165, UniProt: P15692)", "scaffold_policy": "free de-novo generation (length 35-45 nt)", "property_envelope": {"length": [35, 45], "gc_content_pct": [40, 60], "mfe_folding_energy_kcal_per_mol": "< -12.0", "max_homopolymer_run": 4, "predicted_kd_nM": "< 25.0"}, "count": 10}

---

## [165] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loops grafted onto a fixed trastuzumab VH/VL framework targeting the extracellular domain of HER2 (PDB: 1N8Z). Restrict the CDR-H3 length to 12-16 amino acids. Filter out sequences containing developability liabilities (unpaired cysteines, N-glycosylation motifs N-X-[S/T], and DP cleavage sites). Ensure predicted binding affinity pKd > 8.5 and a net CDR charge between -1 and +2 at pH 7.4.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain (domain IV)", "pdb_id": "1N8Z", "target_chain": "C", "epitope_residues": ["557-565", "570-583"]}, "scaffold_policy": {"antibody_format": "Fab / scFv", "framework": "Trastuzumab (humanized IgG1)", "fixed_regions": ["VL", "VH_FR1", "CDR-H1", "VH_FR2", "CDR-H2", "VH_FR3", "VH_FR4"], "design_region": "CDR-H3", "kabat_positions": "95-102", "cdr_length_range": [12, 16]}, "property_envelope": {"binding_affinity_pkd": {"min": 8.5}, "net_charge_cdr_h3": {"min": -1.0, "max": 2.0}, "max_unpaired_cysteines": 0, "forbidden_motifs": ["N[^P][ST]", "DP"]}, "count": 50}

---

## [166] source=multitask_sft_big

**USER:** Please design 5 novel RNA aptamers from scratch targeting human alpha-thrombin with high binding affinity (target Kd < 50 nM). The sequences should be between 30 and 45 nucleotides in length, have a predicted minimum free energy (MFE) below -12 kcal/mol for secondary structural stability, maintain a GC content between 40% and 65%, and avoid single-nucleotide homopolymer runs longer than 4 bases.

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 30, "max": 45}, "affinity_Kd_nM": {"max": 50}, "mfe_kcal_per_mol": {"max": -12.0}, "gc_content_fraction": {"min": 0.4, "max": 0.65}, "max_homopolymer_run": 4}, "count": 5}

---

## [167] source=multitask_sft_big

**USER:** Design 20 de novo CDR-H3 loops grafted onto a human VH3-23/JH4 framework targeting the SARS-CoV-2 Spike receptor-binding domain (PDB: 7K9Z, chain A). Keep the framework regions and CDR-H1 and CDR-H2 fixed. The CDR-H3 length must be constrained between 10 and 16 amino acids. Target the ACE2-binding site epitope (specifically contacting residues K417, E484, and N501). Filter for candidates with predicted high shape complementarity (sc > 0.65), a net CDR-H3 charge between -1 and +2 at pH 7.4, and no more than 3 consecutive hydrophobic residues to prevent aggregation.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike RBD", "pdb_id": "7K9Z", "target_chain": "A", "epitope_residues": ["K417", "E484", "N501"]}, "scaffold_policy": {"framework": "IGHV3-23 / IGHJ4", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "numbering_scheme": "IMGT"}, "property_envelope": {"length_range": [10, 16], "net_charge_range": [-1, 2], "max_consecutive_hydrophobics": 3, "min_shape_complementarity": 0.65}, "count": 20}

---

## [168] source=multitask_sft_big

**USER:** Please design 50 de novo CDR-H3 loops targeting the domain IV epitope of human HER2 (PDB: 1N8Z). Use the Trastuzumab heavy chain framework (IGHV3-23/IGHJ4) with the CDR-H3 loop (Kabat H95-H102) fully redesigned de novo. Constrain CDR-H3 loop length to between 10 and 16 amino acids. Candidates must exclude unpaired cysteines, N-glycosylation motifs (N-X-[S/T], where X!=P), and have no more than 1 methionine. Target high interface shape complementarity, predicted interface binding energy (ddG < -35 REU), and low hydrophobic surface patch exposure (SAP score < 40).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human HER2 (ErbB2) Domain IV", "structure_source": "PDB: 1N8Z", "epitope_residues": ["P557", "K569", "D560", "L525", "T562", "E558"]}, "scaffold_policy": {"framework": "Trastuzumab VH (IGHV3-23 / IGHJ4)", "redesign_region": "CDR-H3 (Kabat positions H95-H102)", "length_range": [10, 16], "flanking_stems": "Fixed standard canonical base (CAR...FDY)"}, "property_envelope": {"predicted_binding_ddg": "< -35 REU", "sap_score": "< 40", "unpaired_cysteines": 0, "n_glycosylation_motifs": 0, "max_methionine_count": 1}, "count": 50}

---

## [169] source=multitask_sft_big

**USER:** Generate 50 de novo macrocyclic peptides targeting the p53-binding pocket of MDM2 to inhibit the MDM2-p53 interaction. Peptides should consist of 8 to 14 amino acid residues cyclized via head-to-tail backbone or a disulfide bridge. Desired candidates should display high target complementarity with predicted Kd < 100 nM, molecular weight between 800 and 1600 Da, LogP between -1.0 and 3.0, and minimal aggregation propensity.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding interface)", "scaffold_policy": "Macrocyclic peptide (8-14 residues; head-to-tail backbone or disulfide cyclization)", "property_envelope": {"peptide_length": [8, 14], "molecular_weight": [800, 1600], "logP": [-1.0, 3.0], "affinity_Kd": "< 100 nM"}, "count": 50}

---

## [170] source=multitask_sft_big

**USER:** Design 15 de novo scaffolds targeting the kinase ATP-binding pocket. We want novel hinge-binding cores distinct from standard quinazoline and aminopyrimidine motifs. Compounds should possess a hinge-compatible donor-acceptor motif, MW 320-460 Da, cLogP 2.0-4.2, TPSA 60-100 Å², <= 3 H-bond donors, <= 6 rotatable bonds, and favorable synthetic accessibility.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP-binding site", "scaffold_policy": "novel scaffolds; exclude quinazoline and aminopyrimidine chemotypes; require hinge-binding donor-acceptor vector", "property_envelope": {"MW": [320, 460], "cLogP": [2.0, 4.2], "TPSA": [60, 100], "HBD": "<= 3", "RotBonds": "<= 6", "SAscore": "<= 4.5"}, "count": 15}

---

## [171] source=multitask_sft_big

**USER:** Design 25 novel drug-like small molecules optimized for metabolic stability and safety. The compounds must exhibit reduced cardiotoxic liability with hERG IC50 > 10 µM (pIC50 < 5.0) and maintain optimal lipophilicity with a LogP between 1.5 and 3.0. Please keep molecular weight under 450 Da.

**ASSISTANT:** {"stage": "generate", "target": "hERG (anti-target)", "scaffold_policy": null, "property_envelope": {"logP": [1.5, 3.0], "hERG_pIC50": "< 5.0", "MW": "<= 450"}, "count": 25}

---

## [172] source=multitask_sft_big

**USER:** Design 20 novel macrocyclic peptide binders targeting the p53-binding pocket of human MDM2 to disrupt the MDM2/p53 interaction. The peptides should be 8 to 12 residues in length, cyclized via head-to-tail or disulfide linkage, and maintain hydrophobic interactions mimicking the Phe19-Trp23-Leu26 triad. Target a molecular weight between 800 and 1500 Da, cLogP < 3.5, and predicted affinity Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53 interaction pocket)", "scaffold_policy": "Macrocyclic peptide backbone (8-12 residues, head-to-tail or disulfide cyclization, incorporating Phe19/Trp23/Leu26 mimicry)", "property_envelope": {"molecular_weight": "800 - 1500 Da", "clogp": "< 3.5", "sequence_length": "8-12 residues", "predicted_kd": "< 50 nM"}, "count": 20}

---

## [173] source=multitask_sft_big

**USER:** Please design 50 novel small-molecule candidates from scratch that maintain moderate lipophilicity (clogP between 1.5 and 3.0) and minimize cardiotoxicity risk, specifically requiring low hERG liability (predicted hERG pIC50 < 5.0). Keep MW under 450 Da and TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"clogP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 60, "max": 110}}, "count": 50}

---

## [174] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like kinase inhibitor scaffolds designed to target the ATP hinge-binding pocket. The cores must be distinct from common kinase chemotypes such as quinazolines, pyrazolopyrimidines, and indoles. Ensure all candidates fall within the following physicochemical envelope: MW 300-450 Da, cLogP 1.5-3.8, TPSA 60-100 Å², HBD 1-2, HBA 3-7, and no more than 5 rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP hinge-binding pocket", "scaffold_policy": {"type": "novel_core", "exclude_scaffolds": ["quinazoline", "pyrazolopyrimidine", "indole"], "hinge_binding_feature": "1-2 hydrogen bond donors/acceptors for hinge interaction"}, "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "clogp": {"min": 1.5, "max": 3.8}, "tpsa": {"min": 60, "max": 100}, "hbd": {"min": 1, "max": 2}, "hba": {"min": 3, "max": 7}, "rotatable_bonds": {"max": 5}}, "count": 50}

---

## [175] source=multitask_sft_big

**USER:** Generate 50 de novo macrocyclic peptides (length: 7–12 amino acids) designed to bind the human MDM2 hydrophobic cleft and disrupt the p53 interaction. Include head-to-tail backbone cyclization or sidechain-to-sidechain stapling. Ensure molecular weight is between 800 and 1500 Da, topological polar surface area (tPSA) is below 350 Å², with predicted low nanomolar binding affinity (Kd < 100 nM) and high proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53 interaction interface)", "scaffold_policy": "Macrocyclic peptides (7-12 residues, head-to-tail or sidechain-to-sidechain cyclization)", "property_envelope": {"molecular_weight": [800, 1500], "tPSA": "<= 350", "affinity_Kd_nM": "< 100", "proteolytic_stability": "high"}, "count": 50}

---

## [176] source=multitask_sft_big

**USER:** Design 15 de novo macrocyclic peptide binders targeting the p53 binding groove of MDM2 to disrupt the MDM2-p53 interaction. The peptides should be 8-12 residues long, cyclized via head-to-tail amide or disulfide linkage, contain no more than 3 aromatic amino acids to reduce non-specific lipophilicity, and exhibit molecular weights between 800 and 1400 Da with an estimated cLogP between -1.0 and 3.0.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 binding cleft)", "scaffold_policy": {"type": "macrocyclic_peptide", "length": "8-12 amino acids", "cyclization": ["head-to-tail amide", "disulfide"], "substructure_limits": {"max_aromatic_residues": 3}}, "property_envelope": {"molecular_weight": {"min": 800, "max": 1400}, "clogp": {"min": -1.0, "max": 3.0}}, "count": 15}

---

## [177] source=multitask_sft_big

**USER:** Design 25 novel, diverse PROTAC linkers to connect a BRD4-targeting warhead (attached via piperazine nitrogen) to a CRBN E3 ligase ligand (attached via pomalidomide 4-position). Linkers should have an effective path length of 8 to 16 atoms, avoid plain aliphatic or standard PEG chains by incorporating semi-rigid structural elements (such as piperidine, bicyclic, spirocyclic, or small heteroaryl rings) to minimize conformational entropy, and maintain overall PROTAC molecular weight under 950 Da with a tPSA between 120 and 180 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / CRBN ternary complex", "scaffold_policy": "Fixed BRD4 warhead and CRBN ligand anchors; generate novel connecting linkers enriched with semi-rigid cyclic and heteroaliphatic scaffolds, excluding pure unbranched alkyl or homomeric PEG chains", "property_envelope": {"linker_chain_length_atoms": "8-16", "protac_molecular_weight": "<= 950", "protac_tpsa": "120-180", "rotatable_bonds_linker": "<= 10", "clogp": "2.0-5.5"}, "count": 25}

---

## [178] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptides targeting the p53 interaction interface of MDM2 (PDB: 1YCR). The designs should be head-to-tail or sidechain-to-sidechain cyclized peptides consisting of 8 to 13 amino acid residues, incorporating non-canonical amino acids where beneficial. Ensure predicted binding affinity Kd < 50 nM, molecular weight < 1600 Da, tPSA < 350 Å², and no hydrolytically labile or reactive functional groups.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-binding pocket, PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptide (head-to-tail or sidechain-to-sidechain cyclization, 8-13 residues)", "property_envelope": {"predicted_Kd": "< 50 nM", "molecular_weight": "< 1600 Da", "tPSA": "< 350 \u00c5\u00b2", "reactive_functional_groups": "exclude"}, "count": 20}

---

## [179] source=multitask_sft_big

**USER:** Please generate 8 de-novo RNA aptamers targeting human vascular endothelial growth factor 165 (VEGF-165). Each sequence should be between 35 and 50 nucleotides, maintain a GC content between 40% and 60%, exhibit a predicted secondary structure folding free energy (MFE) below -12 kcal/mol, and show high estimated binding affinity with target Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "none", "property_envelope": {"length": {"min": 35, "max": 50}, "gc_content": {"min": 0.4, "max": 0.6}, "minimum_free_energy_kcal_mol": {"max": -12.0}, "affinity_kd_nM": {"max": 50.0}}, "count": 8}

---

## [180] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamer sequences (30 to 45 nucleotides) targeting human VEGF-165. The aptamers should be generated de novo with predicted secondary structure stability (minimum free energy < -12 kcal/mol), a GC content between 40% and 60%, no homopolymer runs longer than 4 consecutive nucleotides, and high predicted binding affinity with Kd < 20 nM.

**ASSISTANT:** {"stage": "generate", "target": "human VEGF-165", "scaffold_policy": "de novo", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content_pct": {"min": 40, "max": 60}, "minimum_free_energy_kcal_per_mol": {"max": -12.0}, "kd_nM": {"max": 20.0}, "max_homopolymer_run": 4}, "count": 5}

---

## [181] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small-molecule lead candidates targeting the Dopamine D2 receptor with minimal cardiac liability and balanced lipophilicity. Candidates must demonstrate low hERG channel inhibition (predicted hERG IC50 > 10 µM / pIC50 < 5.0) and favorable logP (clogP 1.5 - 3.0), while adhering to standard drug-like property criteria (MW ≤ 450 Da, TPSA 50 - 120 Å², rotatable bonds ≤ 7).

**ASSISTANT:** {"stage": "generate", "target": "Dopamine D2 receptor (DRD2) with hERG channel counter-screening", "scaffold_policy": "novel", "property_envelope": {"clogP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450.0}, "tpsa": {"min": 50.0, "max": 120.0}, "rotatable_bonds": {"max": 7}}, "count": 50}

---

## [182] source=multitask_sft_big

**USER:** Design 15 novel core scaffolds targeting the ATP-binding pocket of EGFR C797S for non-covalent inhibition. The cores must be structurally distinct from standard quinazoline and pyrrolopyrimidine hinge-binding motifs. Ensure drug-like properties: MW between 350 and 480 Da, cLogP 2.0–4.0, TPSA between 60 and 100 Å², HBD ≤ 2, and rotatable bonds ≤ 6.

**ASSISTANT:** {"stage": "generate", "target": "EGFR C797S kinase", "scaffold_policy": {"novelty": "novel core required", "exclude": ["quinazoline", "pyrrolopyrimidine"], "interaction_mode": "non-covalent / reversible"}, "property_envelope": {"MW": [350, 480], "cLogP": [2.0, 4.0], "TPSA": [60, 100], "HBD": "<= 2", "RotB": "<= 6"}, "count": 15}

---

## [183] source=multitask_sft_big

**USER:** Design 5 de novo RNA aptamer sequences targeting human VEGF-165 (UniProt P15692). Sequences should be between 35 and 45 nucleotides in length with a GC content of 40% to 60%. Ensure a predicted folding minimum free energy (MFE) <= -12.0 kcal/mol at 37°C, avoid homopolymer runs of 4 or more identical nucleotides, and target an estimated binding affinity Kd under 20 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt P15692)", "scaffold_policy": "free", "property_envelope": {"length": {"min": 35, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_kcal_per_mol": {"max": -12.0}, "predicted_kd_nM": {"max": 20.0}, "max_homopolymer_run": 3}, "count": 5}

---

## [184] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loop variants for the Trastuzumab scaffold (PDB: 1N8Z) targeting the HER2 extracellular domain interface. The redesigned CDR-H3 loops should have lengths between 11 and 15 residues, avoid post-translational modification liabilities like N-linked glycosylation (N-X-S/T where X!=P) and unpaired cysteines, maintain an isoelectric point between 6.5 and 8.2, and exhibit low hydrophobicity to minimize aggregation risk.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain IV", "pdb_id": "1N8Z", "interaction_site": "domain IV epitope"}, "scaffold_policy": {"scaffold": "Trastuzumab VH framework", "design_region": "CDR-H3 (Kabat residues 95-102)", "fixed_regions": ["Heavy Chain FR1-FR4", "CDR-H1", "CDR-H2", "Light Chain"]}, "property_envelope": {"cdr_h3_length": [11, 15], "isoelectric_point": [6.5, 8.2], "max_unpaired_cysteines": 0, "forbidden_motifs": ["N[^P][ST]"], "hydrophobicity": "low"}, "count": 50}

---

## [185] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptide inhibitors (7-12 residues) targeting the p53 binding groove of MDM2 to disrupt the MDM2-p53 interaction. The peptides should be cyclized via a head-to-tail peptide bond or a hydrocarbon staple, project hydrophobic residues that mimic the p53 Phe19-Trp23-Leu26 binding triad, have a molecular weight below 1500 Da, ClogP between 0.5 and 4.0, PSA < 400 Å², and high predicted proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding pocket)", "scaffold_policy": "Macrocyclic peptides of 7-12 amino acids, cyclized via head-to-tail amide bond or hydrocarbon staple, presenting aromatic/hydrophobic side chains mimicking p53 Phe19-Trp23-Leu26", "property_envelope": {"molecular_weight": "<1500 Da", "clogP": [0.5, 4.0], "topological_polar_surface_area": "<400 \u00c5\u00b2", "peptide_length": [7, 12]}, "count": 20}

---

## [186] source=multitask_sft_big

**USER:** Design 20 de novo linkers connecting a JQ1-derived BRD4 warhead bearing an amine exit vector to a VH032 VHL ligand terminating in a carboxylate. The linkers should span 8 to 14 extended atoms in length, prioritize sp3-rich or rigid heterocycles (such as piperazines, spirocycles, or bicyclic diamines) over floppy poly-PEG chains to reduce conformational entropy, maintain whole-PROTAC MW < 1000 Da, cLogP between 2.5 and 4.8, and total TPSA < 170 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL PROTAC", "scaffold_policy": "linker design connecting primary/secondary amine on warhead to carboxylic acid on E3 ligand", "property_envelope": {"linker_chain_length_atoms": [8, 14], "molecular_weight_total": "<1000", "clogp_total": [2.5, 4.8], "tpsa_total": "<170", "structural_motifs": "rigidified sp3-rich heterocycles, minimize linear PEG"}, "count": 20}

---

## [187] source=multitask_sft_big

**USER:** Generate 25 novel, diverse kinase inhibitor scaffolds targeting the ATP-binding pocket of EGFR T790M/C797S mutant. The scaffolds must not be based on classical 4-anilinoquinazoline or aminopyrimidine motifs. Aim for drug-like properties with MW 350-480 Da, cLogP 2.0-4.0, TPSA between 60 and 100 Å², HBD <= 3, HBA <= 7, rotatable bonds <= 6, and a synthetic accessibility score below 4.0.

**ASSISTANT:** {"stage": "generate", "target": "EGFR T790M/C797S kinase ATP-binding pocket", "scaffold_policy": "novel core scaffolds distinct from 4-anilinoquinazolines and 2,4-diaminopyrimidines", "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "clogp": {"min": 2.0, "max": 4.0}, "tpsa": {"min": 60, "max": 100}, "hbd": {"max": 3}, "hba": {"max": 7}, "rotatable_bonds": {"max": 6}, "sa_score": {"max": 4.0}}, "count": 25}

---

## [188] source=multitask_sft_big

**USER:** Design 15 novel CDR-H3 loop sequences to bind human HER2 (PDB: 1N8Z) using the trastuzumab VH framework as a template. Restrict the CDR-H3 length to between 11 and 15 residues, ensuring predicted high binding affinity (pKd >= 8.5), solubility (hydrophobic patch area < 400 Å²), net CDR-H3 charge between 0 and +2, and no liability motifs like N-linked glycosylation (N-X-S/T) or aspartate isomerization (DG, DS).

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 (PDB: 1N8Z)", "scaffold_policy": {"framework": "Trastuzumab VH", "region_to_design": "CDR-H3", "length_range": [11, 15]}, "property_envelope": {"predicted_pKd": ">= 8.5", "hydrophobic_patch_area": "< 400 A^2", "net_charge": [0, 2], "unwanted_motifs": ["N[^P][ST]", "DG", "DS"]}, "count": 15}

---

## [189] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human VEGF-165 (UniProt P15692-4). The aptamers should be de novo single-stranded RNA sequences with a length between 30 and 45 nucleotides. They must exhibit high predicted binding affinity (Kd < 50 nM), a stable secondary structure with minimum free energy (MFE) <= -12 kcal/mol, and a GC content strictly between 40% and 60%. Do not include constant primer binding regions.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt P15692-4)", "scaffold_policy": "none", "property_envelope": {"molecule_type": "RNA", "sequence_length": {"min": 30, "max": 45}, "affinity_kd_nm": {"max": 50}, "minimum_free_energy_kcal_mol": {"max": -12.0}, "gc_content": {"min": 0.4, "max": 0.6}}, "count": 5}

---

## [190] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamers targeting human VEGF-165 (UniProt: P15692). Sequences must be between 30 and 45 nucleotides in length, with a GC content between 40% and 60%, and a predicted minimum free energy (MFE) secondary structure stability between -18.0 and -10.0 kcal/mol. The candidates should exhibit high predicted affinity (Kd < 50 nM) toward the receptor-binding domain and avoid predefined aptamer scaffolds.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 30, "max": 45}, "gc_content_pct": {"min": 40.0, "max": 60.0}, "mfe_kcal_mol": {"min": -18.0, "max": -10.0}, "predicted_kd_nM": {"max": 50.0}}, "count": 10}

---

## [191] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptides (8 to 12 residues) targeting the p53-binding pocket of human MDM2 to disrupt the MDM2-p53 protein-protein interaction. Candidates should utilize head-to-tail or hydrocarbon staple cyclization, mimic the key p53 hydrophobic triad (Phe19, Trp23, Leu26), have a molecular weight between 800 and 1500 Da, cLogP < 3.5, and feature high proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-binding pocket, PPI disruption)", "scaffold_policy": "Macrocyclic peptides (8-12 residues, head-to-tail or hydrocarbon staple cyclization incorporating p53 interaction hotspot mimics)", "property_envelope": {"molecular_weight": "800 - 1500 Da", "clogp": "< 3.5", "sequence_length": "8-12 amino acids", "cyclization_type": "head-to-tail or hydrocarbon stapled", "structural_motifs": "Phe, Trp, Leu mimetic pharmacophore", "stability": "high proteolytic stability"}, "count": 20}

---

## [192] source=multitask_sft_big

**USER:** Design 25 de-novo CDR-H3 loops grafted onto an IGHV3-23/IGHJ4 human heavy chain scaffold to bind the human TIGIT extracellular domain (PDB: 3RQ3). Keep the framework residues and CDR-H1/CDR-H2 fixed. The generated CDR-H3 loops should have lengths between 11 and 16 residues (Kabat definitions H95–H102), avoid liability motifs (unpaired cysteines, N-glycosylation sites N-X-[S/T], and aspartate isomerization DG/DS), maintain a net charge between -1 and +2 at pH 7.4, and exhibit high predicted shape complementarity to the TIGIT epitope.

**ASSISTANT:** {"stage": "generate", "target": "Human TIGIT extracellular domain (PDB: 3RQ3)", "scaffold_policy": "Fix heavy chain framework (IGHV3-23/IGHJ4) and CDR-H1/CDR-H2; generate only CDR-H3 (Kabat residues H95\u2013H102)", "property_envelope": {"cdr_h3_length_range": [11, 16], "net_charge_pH_7_4": [-1.0, 2.0], "unpaired_cysteines": 0, "forbidden_motifs": ["N[^P][ST]", "DG", "DS"], "predicted_binding_epitope": "TIGIT homodimerization/PVR binding interface"}, "count": 25}

---

## [193] source=multitask_sft_big

**USER:** Please design 50 novel linkers for a PROTAC targeting BRD4 using our VHL E3 ligase recruiter. The linker must connect the exit vector of the JQ1-derived warhead (terminal carboxylic acid / amide attachment point) to the trans-4-hydroxyproline core of the VHL ligand (terminal amine). We need linker lengths ranging between 8 and 16 heavy atoms, combining flexible aliphatic/PEG segments with semi-rigid heterocyclic spacers (e.g., piperazine, piperidine, or triazole) to encourage stable ternary complex formation. The full molecules should maintain LogP between 2.0 and 5.0, overall TPSA below 180 Å², and exclude metabolically labile moieties like hydrolyzable esters or reactive alkyl halides.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linker (connecting JQ1 warhead to VHL ligand)", "scaffold_policy": "Bifunctional linker design connecting defined JQ1 acid/amide exit vector to VHL amine exit vector; 8-16 heavy atoms; incorporates mixed aliphatic, PEG, and rigid cyclic/heterocyclic spacers", "property_envelope": {"linker_heavy_atom_length": "8-16", "clogP": "2.0 - 5.0", "tpsa": "< 180", "structural_alerts": "no hydrolyzable esters, no reactive alkyl halides"}, "count": 50}

---

## [194] source=multitask_sft_big

**USER:** Design 15 de novo CDR-H3 loops targeting the human TIGIT extracellular domain (PDB: 3UDW) specifically directed at the PVR-interaction interface (residues Q56, F107, T117). Scaffold the loops into a humanized VH3-23 / VK1 framework with CDR-H1, CDR-H2, and all light chain CDRs held constant. The CDR-H3 loop length should be constrained between 11 and 15 amino acids (Chothia definition). Ensure candidates lack canonical liabilities (no unpaired cysteines, no N-glycosylation sites N-X-[S/T]), have an isoelectric point/net CDR charge between -1.5 and +2.0 at pH 7.4, and exhibit high predicted interfacial shape complementarity (Sc > 0.65) and binding affinity (predicted FoldX ddG < -30 kcal/mol).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human TIGIT (extracellular domain)", "pdb_id": "3UDW", "epitope_residues": ["Q56", "F107", "T117"]}, "scaffold_policy": {"framework": "Humanized VH3-23 / VK1", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4", "VL_all"], "mutable_regions": ["CDR-H3"], "cdr_numbering_scheme": "Chothia"}, "property_envelope": {"cdr_h3_length_range": [11, 15], "net_charge_range": [-1.5, 2.0], "avoid_motifs": ["C", "N[^P][ST]"], "min_shape_complementarity": 0.65, "max_predicted_ddg_kcal_mol": -30.0}, "count": 15}

---

## [195] source=multitask_sft_big

**USER:** Design 20 novel PROTAC linkers connecting the phenolic ether exit vector of our BRD4 warhead (JQ1 derivative) to the terminal amine of the VHL ligand (VH032 derivative). The linkers should span 8 to 16 linear atoms, incorporate semi-rigid motifs such as piperazines, alkynes, or spirocycles to limit conformational entropy while avoiding simple PEG or polymethylene chains, keep total PROTAC MW < 1050 Da, cLogP between 2.0 and 5.0, TPSA < 200 Å², and possess no metabolically labile ester or hydrazone groups.

**ASSISTANT:** {"stage": "generate", "target": "PROTAC linker (BRD4-JQ1 to VHL-VH032)", "scaffold_policy": "bifunctional_linker_attachment", "property_envelope": {"linker_chain_length_atoms": [8, 16], "protac_molecular_weight_max": 1050, "clogp_min": 2.0, "clogp_max": 5.0, "tpsa_max": 200.0, "unwanted_substructures": ["esters", "hydrazones", "pure_polyethylene_glycol", "pure_polymethylene"], "required_motifs": ["semi-rigid cyclic or alkyne core"]}, "count": 20}

---

## [196] source=multitask_sft_big

**USER:** Design 30 novel, semi-rigid bifunctional linkers to connect a VHL E3 ligase ligand (attached via the phenol oxygen of VH032) and a JQ1-derived BRD4 warhead (attached via the tert-butyl ester deprotected carboxylic acid). The exit vector distance is roughly 10-14 Å. Avoid simple linear polyethylene glycol (PEG) or unbranched alkyl chains; prioritize linkers with rigidifying motifs such as piperazines, spirocycles, or alkynes to reduce conformational entropy while maintaining cell permeability. Desired property criteria: linker heavy atom count between 8 and 14, calculated logP between 1.5 and 4.0, total PROTAC TPSA ≤ 180 Å², and high synthetic accessibility (SAScore ≤ 4.5).

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex (PROTAC)", "scaffold_policy": "Bifunctional linker generation connecting VH032 phenol exit vector and JQ1 carboxylic exit vector; must avoid pure PEG or flexible alkyl chains; prioritize semi-rigid motifs like piperazines, spirocycles, or alkynes", "property_envelope": {"linker_heavy_atom_count": [8, 14], "exit_vector_distance_angstrom": [10.0, 14.0], "clogP": [1.5, 4.0], "tpsa_upper_bound": 180.0, "sa_score_max": 4.5}, "count": 30}

---

## [197] source=multitask_sft_big

**USER:** Design 50 de novo linkers connecting a BTK warhead amine attachment point to a CRBN pomalidomide phenolic oxygen. The linker path length should span 8 to 14 heavy atoms to optimize ternary complex formation. Avoid simple flexible PEG chains; prioritize partially rigidified motifs such as piperazines, piperidines, spirocycles, or alkynes to reduce conformational entropy. Linker fragment constraints: MW <= 250 Da, cLogP between 0.5 and 2.5, TPSA <= 60 Å², and rotatable bonds <= 6.

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN PROTAC linker", "scaffold_policy": "Bifunctional linker joining BTK-NH-* and CRBN-O-* vectors; length 8-14 heavy atoms; incorporate rigidifying motifs (piperazine, piperidine, spirocycles, alkyne)", "property_envelope": {"linker_heavy_atom_count": "8-14", "linker_mw": "<= 250", "linker_clogp": "0.5 - 2.5", "linker_tpsa": "<= 60", "linker_rotatable_bonds": "<= 6"}, "count": 50}

---

## [198] source=multitask_sft_big

**USER:** Design 25 novel, diverse core scaffolds targeting the kinase ATP-binding site hinge region. The scaffolds must provide at least one hydrogen bond donor and one hydrogen bond acceptor capable of forming hinge interactions, while deliberately avoiding classic bicyclic heteroaryl purine and pyrazolo-pyrimidine motifs. Keep molecular weight between 300 and 420 Da, clogP between 1.5 and 3.5, TPSA under 90 Å², and rotatable bonds no greater than 5.

**ASSISTANT:** {"stage": "generate", "target": "kinase ATP-binding site", "scaffold_policy": {"type": "novel", "required_motifs": ["hinge donor-acceptor pair"], "excluded_motifs": ["purine", "pyrazolo[3,4-d]pyrimidine", "4-aminoquinazoline"]}, "property_envelope": {"mw": [300, 420], "logP": [1.5, 3.5], "tpsa": [0, 90], "rotatable_bonds": [0, 5], "hbd": [1, 3], "hba": [2, 6]}, "count": 25}

---

## [199] source=multitask_sft_big

**USER:** Design 10 novel small molecules targeting CDK4/6 with an optimized lipophilicity and favorable hERG safety profile. Ensure a LogP between 2.0 and 3.2, hERG IC50 > 10 µM (pIC50 < 5.0), MW < 480 Da, and TPSA between 70 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": "CDK4/6", "scaffold_policy": "novel", "property_envelope": {"LogP": {"min": 2.0, "max": 3.2}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 480}, "TPSA": {"min": 70, "max": 120}}, "count": 10}

---

## [200] source=multitask_sft_big

**USER:** Generate 50 novel small molecule candidates designed de novo with an optimal physicochemical profile and minimal cardiotoxicity liability. The compounds should have an octanol-water partition coefficient (logP) strictly between 1.5 and 2.8 and demonstrate high hERG safety with a predicted hERG pIC50 < 5.0 (IC50 > 10 µM). Keep molecular weight between 250 and 450 Da, TPSA between 40 and 110 Å², and rotatable bonds under 7.

**ASSISTANT:** {"stage": "generate", "target": "hERG (anti-target counter-screening)", "scaffold_policy": "novel", "property_envelope": {"logP": {"min": 1.5, "max": 2.8}, "hERG_pIC50": {"max": 5.0}, "hERG_IC50_uM": {"min": 10.0}, "molecular_weight": {"min": 250, "max": 450}, "tpsa": {"min": 40.0, "max": 110.0}, "rotatable_bonds": {"max": 7}}, "count": 50}

---

## [201] source=multitask_sft_big

**USER:** Generate 5 novel RNA aptamer sequences (30 to 45 nucleotides in length) that target human VEGF-165 (UniProt: P15692). The designs must have high predicted affinity (Kd < 50 nM), a predicted minimum free energy (MFE) secondary structure stability below -10.0 kcal/mol, and a balanced GC content between 40% and 60%.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human VEGF-165", "uniprot_id": "P15692"}, "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "binding_affinity_kd_nm": {"max": 50.0}, "mfe_kcal_per_mol": {"max": -10.0}, "gc_content_pct": {"min": 40.0, "max": 60.0}}, "count": 5}

---

## [202] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamers targeting human VEGF-165 (Vascular Endothelial Growth Factor 165). The aptamers should be 40 to 60 nucleotides in length, achieve an estimated binding affinity (Kd) under 10 nM, exhibit a secondary structure minimum free energy (MFE) below -15 kcal/mol, and have a GC content between 40% and 60%. Please exclude sequences with homopolymer runs exceeding 4 consecutive uridines or guanines.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 40, "max": 60}, "affinity_kd_nm": {"max": 10.0}, "mfe_kcal_mol": {"max": -15.0}, "gc_content": {"min": 0.4, "max": 0.6}, "max_homopolymer_length": {"poly_U": 4, "poly_G": 4}}, "count": 10}

---

## [203] source=multitask_sft_big

**USER:** Design 20 novel PROTAC linkers connecting a JQ1-derived BRD4 warhead (exit vector via the terminal ester/amide) to a VH032 VHL ligand (exit vector via the phenolic ether). The linkers must span between 8 and 16 linear atoms, avoid simple linear PEG or polymethylene repeats by incorporating rigidifying motifs (e.g., piperazine, piperidine, or small cycloalkyl rings), maintain overall cLogP between 2.5 and 5.5, limit linker rotatable bonds to 10 or fewer, and keep total PROTAC TPSA below 240 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL ternary complex", "scaffold_policy": "keep JQ1 warhead and VH032 E3 ligase binder fixed at specified exit vectors; generate de-novo linkers with constrained/rigidifying ring motifs", "property_envelope": {"linker_chain_length_atoms": [8, 16], "linker_rotatable_bonds": "<= 10", "clogp": [2.5, 5.5], "tpsa": "<= 240", "excluded_motifs": ["unbranched aliphatic chains >= 6 carbons", "linear PEG >= 3 repeating units", "chemically reactive groups"]}, "count": 20}

---

## [204] source=multitask_sft_big

**USER:** Design 10 novel CDR-H3 loops (length 11-16 amino acids) grafted onto a human IGHV3-23/IGHJ4 antibody framework to bind the receptor-binding domain of human TIGIT (PDB: 3U5D). Keep CDR-H1, CDR-H2, and the light chain fixed. The designed CDR-H3 sequences must have a predicted binding affinity (Kd) < 50 nM, net loop charge between -1 and +2 at pH 7.4, no N-linked glycosylation sequons (N-X-S/T, where X != P), fewer than 3 aromatic residues, and a predicted developability/solubility score > 0.7.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human TIGIT", "pdb_id": "3U5D", "binding_site": "Receptor-binding domain / PVR interaction interface"}, "scaffold_policy": {"heavy_chain_framework": "IGHV3-23/IGHJ4", "light_chain": "Fixed", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4", "VL"], "design_region": "CDR-H3", "loop_length_range": [11, 16]}, "property_envelope": {"predicted_kd_nM": {"max": 50}, "net_charge_ph7_4": {"min": -1, "max": 2}, "aromatic_residue_count": {"max": 2}, "solubility_score": {"min": 0.7}, "forbidden_motifs": ["N[^P][ST]"]}, "count": 10}

---

## [205] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide binders targeting the PD-1 binding interface of human PD-L1. The designs should be head-to-tail or sidechain-to-tail cyclized peptides ranging from 8 to 14 residues, permitting both canonical and non-canonical amino acids. Ensure predicted high binding affinity (Kd < 50 nM), molecular weight below 1600 Da, clogP between -1.0 and 3.0, and low predicted conformational flexibility in solution.

**ASSISTANT:** {"stage": "generate", "target": "Human PD-L1 (PD-1 interaction epitope)", "scaffold_policy": {"topology": "macrocyclic peptide", "cyclization_type": "head-to-tail or sidechain-to-tail", "sequence_length": [8, 14], "monomer_types": ["canonical amino acids", "non-canonical amino acids"]}, "property_envelope": {"binding_affinity_Kd_nM": "< 50", "molecular_weight_Da": "< 1600", "clogP": [-1.0, 3.0]}, "count": 20}

---

## [206] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human VEGF-165 (Vascular Endothelial Growth Factor 165). The sequences should be 35 to 50 nucleotides in length, fully de novo without fixed primer binding regions, exhibit high predicted binding affinity (Kd < 15 nM), and possess a GC content between 40% and 60%. Sequences must form stable secondary structures with a predicted minimum free energy (ΔG) ≤ -12.0 kcal/mol at 37°C.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692-4)", "scaffold_policy": "de_novo_unconstrained", "property_envelope": {"sequence_length": {"min": 35, "max": 50, "unit": "nt"}, "gc_content": {"min": 40.0, "max": 60.0, "unit": "%"}, "binding_affinity_kd": {"max": 15.0, "unit": "nM"}, "folding_mfe": {"max": -12.0, "unit": "kcal/mol"}}, "count": 5}

---

## [207] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like linkers to conjugate our BRD4-targeting warhead (attached via aryl amine) to a VHL E3 ligase ligand (attached via phenol ether). We need linkers spanning 8 to 16 atoms in length, incorporating semi-rigid motifs like piperazines, piperidines, or spirocyclic rings to reduce conformational entropy relative to standard PEG chains. Keep the linker portion cLogP between 1.0 and 3.5, TPSA < 120 Å², and ensure structures are synthetically tractable with no chemically labile bonds.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linker", "scaffold_policy": "bifunctional linker connecting aryl amine to phenol ether; incorporates conformationally constrained motifs (e.g., piperazine, spirocycles); avoids linear alkyl/PEG homopolymers", "property_envelope": {"linker_atom_length": "8-16", "clogp": "1.0 - 3.5", "tpsa": "< 120", "rotatable_bonds": "<= 8", "unwanted_substructures": ["reactive_groups", "labile_esters", "hydrazones"]}, "count": 50}

---

## [208] source=multitask_sft_big

**USER:** Generate 15 novel macrocyclic peptide binders targeting the Menin-MLL1 protein-protein interaction interface. Peptides should be 8-12 amino acids in length, cyclized via head-to-tail amide or disulfide linkage, presenting a hydrophobic binding motif against the central cavity of Menin. Require molecular weight between 900 and 1500 Da, cLogP between -1.5 and 2.5, and topological polar surface area (tPSA) below 450 Å².

**ASSISTANT:** {"stage": "generate", "target": "Menin-MLL1 protein-protein interaction interface", "scaffold_policy": "Macrocyclic peptides of 8-12 amino acids cyclized via head-to-tail backbone amide bond or disulfide bridge", "property_envelope": {"molecular_weight": [900, 1500], "clogp": [-1.5, 2.5], "tpsa_max": 450, "structural_motifs": ["hydrophobic core anchor motif targeting Menin central cavity"]}, "count": 15}

---

## [209] source=multitask_sft_big

**USER:** Please generate 10 de novo RNA aptamer sequences targeting human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692). Sequences must be between 35 and 45 nucleotides in length, possess a GC content between 40% and 60%, have a predicted folding minimum free energy (MFE) of -12.0 kcal/mol or lower, avoid G-runs longer than 4 consecutive nucleotides, and show predicted binding selectivity against VEGF-121.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 35, "max": 45}, "gc_content_range": [0.4, 0.6], "max_mfe_kcal_per_mol": -12.0, "max_homopolymer_g": 4, "counter_target": "VEGF-121"}, "count": 10}

---

## [210] source=multitask_sft_big

**USER:** Design 10 de novo CDR-H3 loop sequences grafted onto the trastuzumab variable heavy chain framework to target the domain IV epitope of human HER2 (PDB: 1N8Z). The CDR-H3 length should be strictly between 12 and 16 residues (Kabat definition). Filter for high predicted binding affinity, remove developability liabilities (no unpaired Cys, no N-linked glycosylation N-X-[S/T], no deamidation hotspots like NG/NS), and maintain a CDR-H3 net charge between 0 and +2 at physiological pH.

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 extracellular domain IV (PDB: 1N8Z)", "scaffold_policy": "Trastuzumab VH framework with native CDR-H1 and CDR-H2 preserved; variable CDR-H3 replacement", "property_envelope": {"cdr_h3_length": "12-16 amino acids (Kabat numbering)", "charge": "net charge between 0 and +2 at pH 7.4", "sequence_liabilities": ["unpaired Cys", "N-glycosylation (N-X-[S/T], X!=P)", "deamidation motifs (NG, NS)"], "predicted_binding": "high affinity to HER2 domain IV epitope"}, "count": 10}

---

## [211] source=multitask_sft_big

**USER:** Generate 10 novel RNA aptamer sequences designed de novo to bind human VEGF-165. Each candidate should be between 35 and 45 nucleotides in length with a GC content of 40-60%, a secondary structure folding free energy (ΔG) between -15.0 and -5.0 kcal/mol, and an estimated binding affinity (Kd) below 10 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor 165 (VEGF-165)", "scaffold_policy": "none", "property_envelope": {"length": [35, 45], "gc_content_pct": [40.0, 60.0], "folding_deltaG_kcal_mol": [-15.0, -5.0], "predicted_kd_nM": "<= 10.0"}, "count": 10}

---

## [212] source=multitask_sft_big

**USER:** Design 50 novel bifunctional PROTAC linkers connecting our CDK4/6 warhead (exit vector at the abemaciclib terminal piperazine nitrogen) to a VHL E3 ligase ligand (VH032 attached via the phenolic oxygen). Linkers should have an attachment-to-attachment length of 8 to 16 atoms and avoid simple linear PEG or polymethylene chains by incorporating rigidifying or sp3-rich heterocycles (such as azetidines, piperazines, or bicyclic motifs) to minimize conformational entropy. The resulting intact PROTACs must maintain MW < 1050 Da, linker clogP between 1.0 and 3.0, total PROTAC TPSA < 210 Å², rotatable bond count < 18, and be free of metabolically labile groups like esters, hydrazones, or Michael acceptors.

**ASSISTANT:** {"stage": "generate", "target": "CDK4/6-VHL PROTAC", "scaffold_policy": "link warhead (abemaciclib piperazine N) and E3 ligand (VH032 phenolic O) with semi-rigid linkers; prohibit linear alkyl/PEG homopolymers", "property_envelope": {"linker_atom_length": [8, 16], "linker_clogP": [1.0, 3.0], "protac_MW_max": 1050, "protac_TPSA_max": 210, "protac_rotatable_bonds_max": 18, "structural_alerts": ["ester", "hydrazone", "michael_acceptor"]}, "count": 50}

---

## [213] source=multitask_sft_big

**USER:** Design 50 novel, drug-like PROTAC linkers to connect a BRD4-targeting warhead (JQ1 analog, attachment vector via terminal amide) and an E3 ligase recruiter (VH032 VHL ligand, exit vector via phenolic ether). Linkers should feature 6 to 14 chain atoms, incorporate semi-rigid elements like piperazines, spirocycles, or oxetanes to limit conformational entropy, avoid simple polymethylene or repetitive PEG motifs, have linker MW between 100 and 300 Da, cLogP between 0.5 and 2.5, rotatable bonds <= 8, and SA score <= 4.0.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex", "scaffold_policy": "bifunctional_linker_design", "property_envelope": {"linker_chain_length": [6, 14], "molecular_weight": [100, 300], "clogP": [0.5, 2.5], "rotatable_bonds": "<= 8", "sa_score": "<= 4.0", "tpsa": [20.0, 80.0]}, "count": 50}

---

## [214] source=multitask_sft_big

**USER:** Design 20 novel small-molecule kinase inhibitor scaffolds targeting the ATP-binding site. The cores must be distinct from well-patented quinazoline, pyrazolopyrimidine, and indazole chemotypes to secure FTO. Compounds must fall within the following property profile: MW 350–480 Da, LogP 2.0–4.0, TPSA 60–95 Å², HBD <= 3, and HBA 4–8.

**ASSISTANT:** {"stage": "generate", "target": "kinase ATP-binding site", "scaffold_policy": {"type": "novel_core", "exclude": ["quinazoline", "pyrazolopyrimidine", "indazole"]}, "property_envelope": {"MW": [350, 480], "LogP": [2.0, 4.0], "TPSA": [60, 95], "HBD": {"max": 3}, "HBA": [4, 8]}, "count": 20}

---

## [215] source=multitask_sft_big

**USER:** Design 25 novel drug-like small molecules from scratch optimized for low cardiotoxicity risk and balanced lipophilicity. Predicted hERG pIC50 must be below 5.0 (IC50 > 10 µM), with LogP constrained between 1.5 and 3.0. Keep molecular weight under 450 Da and TPSA between 60 and 120 Å² while avoiding PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "hERG (cardiac safety anti-target)", "scaffold_policy": {"type": "de_novo", "core": null}, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 60, "max": 120}, "filters": ["PAINS", "reactive_functional_groups"]}, "count": 25}

---

## [216] source=multitask_sft_big

**USER:** Design 25 de novo drug-like small molecules optimized for metabolic stability and cardiovascular safety. Keep logP tightly controlled between 1.5 and 3.0, and minimize hERG liability (predicted hERG IC50 > 10 µM or pIC50 < 5.0). Compounds should have MW < 450 Da, TPSA between 60 and 110 Å², and explore novel chemical scaffolds suitable for lead generation.

**ASSISTANT:** {"stage": "generate", "target": "hERG (antitarget)", "scaffold_policy": "novel exploration", "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "hERG_IC50_uM": {"min": 10.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 60, "max": 110}}, "count": 25}

---

## [217] source=multitask_sft_big

**USER:** Design 20 structurally novel linkers to conjugate a JQ1-derived BRD4 warhead (via its free carboxyl group) to a Pomalidomide E3 ligase recruiter (via the 4-amino position). Linkers should feature rigidifying motifs such as piperazine, piperidine, or spirocyclic alkylene rings rather than purely flexible PEG or alkyl chains to reduce conformational entropy. Maintain linker length between 8 and 14 heavy atoms, linker logP between 1.0 and 3.5, and linker TPSA under 140 Å² while avoiding metabolically labile ester bonds.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN ternary complex linker", "scaffold_policy": "linker_design (connect JQ1 warhead carboxyl to pomalidomide 4-amino group, incorporating rigid/semirigid heterocycles)", "property_envelope": {"linker_heavy_atom_count": [8, 14], "logP": [1.0, 3.5], "TPSA": "<= 140", "rotatable_bonds": "<= 8", "forbidden_groups": ["esters", "hydrazones", "reactive halides"]}, "count": 20}

---

## [218] source=multitask_sft_big

**USER:** Design 25 de-novo linkers to conjugate our BRD4 warhead (JQ1-derived terminal carboxylic acid) to a CRBN E3 ligase recruiter (pomalidomide with a free 4-amino handle). Generate linkers spanning 6 to 14 heavy atoms containing combinations of alkyl, PEG, and rigid cycloalkyl or heteroaryl rings to avoid purely aliphatic chains. The resulting linkers should have a molecular weight between 120 and 320 Da, rotatable bond count between 4 and 10, linker cLogP between -0.5 and 3.0, and overall PROTAC cLogP < 5.0 with low predicted clearance.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN PROTAC linker", "scaffold_policy": {"warhead_handle": "carboxylic acid (amide coupling)", "e3_handle": "pomalidomide 4-amino", "linker_chemistry": "alkyl, PEG, cycloalkyl, and heteroaryl motifs; forbid purely linear unfunctionalized alkyl chains > 6 carbons"}, "property_envelope": {"linker_heavy_atom_length": [6, 14], "linker_mw": [120, 320], "linker_rotatable_bonds": [4, 10], "linker_clogp": [-0.5, 3.0], "protac_clogp_max": 5.0}, "count": 25}

---

## [219] source=multitask_sft_big

**USER:** Design 30 novel linkers connecting a JQ1-derived BRD4 warhead (via phenyl amino exit vector) to a CRBN pomalidomide ligand (via 4-amino exit vector). The designed PROTACs should balance permeability and degradation efficacy: incorporate rigid elements (such as piperazines, piperidines, or spirocycles) alongside flexible aliphatic or PEG segments. Target linker length between 8 to 14 heavy atoms, overall PROTAC MW < 1000 Da, cLogP between 2.0 and 5.0, TPSA < 190 Å², and rotatable bond count < 15 to maintain cell permeability.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN PROTAC", "scaffold_policy": "keep fixed warhead and E3 binder anchors, de-novo generate connecting linker", "property_envelope": {"linker_heavy_atoms": [8, 14], "molecular_weight": [700, 1000], "clogp": [2.0, 5.0], "tpsa": [100, 190], "rotatable_bonds": [6, 15]}, "count": 30}

---

## [220] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like linkers to conjugate our BRD4-targeting warhead (amine exit vector) to a VHL ligand (hydroxyproline derivative, phenol exit vector). Linkers should span between 8 to 14 heavy atoms to achieve ternary complex formation. Avoid pure flexible aliphatic chains; incorporate rigidifying motifs such as piperazine, spirocycles, or alkynes to reduce conformational entropy. Linker properties should adhere to: linker MW < 250 Da, cLogP between 0.5 and 2.5, rotatable bonds <= 7, and strictly exclude metabolically unstable groups like esters, peroxides, or reactive halides.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex (PROTAC linker design)", "scaffold_policy": "Bifunctional linker connecting Warhead-NH- to VHL-O- vector; span 8-14 heavy atoms; incorporate rigidifying motifs (piperazines, spirocycles, small heterocycles, alkynes); forbid purely unbranched polymethylene/PEG chains and labile bonds (esters, hydrazones)", "property_envelope": {"linker_heavy_atom_count": [8, 14], "linker_mw": "<= 250", "clogp": [0.5, 2.5], "rotatable_bonds": "<= 7"}, "count": 50}

---

## [221] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loops against the SARS-CoV-2 Spike receptor-binding domain (PDB: 6M0J, targeting epitope residues K417, E484, and N501). Keep the human IGHV3-23/IGHJ4 antibody framework and CDR-H1/CDR-H2 sequences fixed. The designed CDR-H3 loops should be 10 to 16 residues in length, lack unpaired cysteines, omit N-glycosylation motifs (Nx[S/T]), maintain a hydrophobic residue ratio below 35%, and show strong predicted binding affinity to the target epitope.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike RBD", "pdb_id": "6M0J", "epitope_residues": ["K417", "E484", "N501"]}, "scaffold_policy": {"framework": "IGHV3-23 / IGHJ4", "fixed_segments": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "redesign_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [10, 16], "unpaired_cysteines": 0, "n_glycosylation_motifs": 0, "max_hydrophobic_fraction": 0.35}, "count": 50}

---

## [222] source=multitask_sft_big

**USER:** Generate 20 de-novo macrocyclic peptides targeting the PD-1/PD-L1 protein-protein interaction interface on PD-L1. The peptides should be 8 to 14 amino acids in length, cyclized via head-to-tail backbone linkage or a disulfide bridge. Target candidates should have an estimated affinity Kd < 50 nM, molecular weight between 800 and 1600 Da, LogP between -1.0 and 3.0, and high predicted proteolytic stability in human serum.

**ASSISTANT:** {"stage": "generate", "target": "PD-L1 (PPI site blocking PD-1)", "scaffold_policy": "Macrocyclic peptide (8-14 amino acid residues; head-to-tail backbone or disulfide cyclization)", "property_envelope": {"molecular_weight": "800 - 1600 Da", "logP": "-1.0 to 3.0", "affinity_Kd": "< 50 nM", "stability": "high predicted serum proteolytic stability"}, "count": 20}

---

## [223] source=multitask_sft_big

**USER:** Design 15 novel, semi-rigid PROTAC linkers to conjugate a VHL ligand (VH032 with phenolic attachment) to an AR warhead (enzalutamide derivative). Replace extended alkyl/PEG chains with heterocyclic or spiro-alkane rigidifying units to favor productive ternary complex formation. The full PROTAC assembly must maintain MW < 1050 Da, cLogP between 2.5 and 5.5, TPSA < 210 Å², and the linker fragment itself should have a path length of 8 to 14 atoms with no more than 8 rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "VHL-AR PROTAC linker", "scaffold_policy": "Connect VH032 phenolic handle to enzalutamide warhead derivative using rigid or semi-rigid heterocyclic/spiro scaffolds; avoid purely linear aliphatic or PEG chains", "property_envelope": {"full_MW": "<1050", "cLogP": "2.5 - 5.5", "TPSA": "<210", "linker_atom_length": "8 - 14", "linker_rotatable_bonds": "<= 8"}, "count": 15}

---

## [224] source=multitask_sft_big

**USER:** Please design 15 de novo macrocyclic peptide inhibitors targeting the Menin-MLL protein-protein interaction interface (PDB: 4OG7). Peptides should be 8-13 residues long, head-to-tail cyclized or hydrocarbon-stapled, incorporating canonical or non-canonical amino acids. Ensure the designs have MW < 1600 Da, cLogP between 0.0 and 4.0, TPSA < 350 Å², and fewer than 15 rotatable bonds to favor cell permeability and pre-organization.

**ASSISTANT:** {"stage": "generate", "target": "Menin-MLL interface (PDB: 4OG7)", "scaffold_policy": "Macrocyclic peptides (head-to-tail cyclized or stapled, 8-13 residues, canonical and non-canonical amino acids)", "property_envelope": {"molecular_weight": "< 1600 Da", "clogp": "0.0 - 4.0", "tpsa": "< 350 \u00c5\u00b2", "rotatable_bonds": "< 15"}, "count": 15}

---

## [225] source=multitask_sft_big

**USER:** Generate 50 de-novo single-stranded RNA aptamer candidates targeting human alpha-thrombin exosite I (PDB: 1HAO). Sequences should be between 30 and 45 nucleotides in length, with a GC content strictly between 45% and 65%. Exclude homopolymer tracts longer than 4 consecutive uridines (poly-U <= 4). Target an RNA secondary structure minimum free energy (MFE) <= -12.0 kcal/mol to ensure thermodynamic stability, favoring stem-loop or G-quadruplex conformations compatible with exosite I binding.

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin (exosite I, PDB: 1HAO)", "scaffold_policy": "free_de_novo", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content_pct": {"min": 45.0, "max": 65.0}, "mfe_kcal_mol": {"max": -12.0}, "motif_constraints": {"max_homopolymer_u": 4, "preferred_secondary_structure": ["stem-loop", "G-quadruplex"]}}, "count": 50}

---

## [226] source=multitask_sft_big

**USER:** Design 50 novel PROTAC linkers to conjugate a JQ1-derived BRD4 warhead (exit vector at the pendant carboxylic acid) to a VH032-based VHL ligand (terminal phenol exit vector). The linkers should be 8-14 Å in end-to-end length, avoid metabolically labile ester bonds, and avoid simple repetitive PEG or pure alkyl chains. Prioritize semi-rigid motifs such as piperazine, azetidine, or spirocyclic heterocycles to control conformational entropy. The intact PROTAC molecules must satisfy: MW < 1100 Da, cLogP 2.5–5.5, TPSA < 210 Å², and rotatable bond count in the linker ≤ 8.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL PROTAC", "scaffold_policy": "rigid_linker_conjugation_with_fixed_anchors", "property_envelope": {"linker_length_A": [8.0, 14.0], "protac_mw_max": 1100.0, "protac_clogp": [2.5, 5.5], "protac_tpsa_max": 210.0, "linker_rotatable_bonds_max": 8, "excluded_motifs": ["ester", "unbranched_polyethylene_glycol_gt_3", "linear_alkyl_gt_6"]}, "count": 50}

---

## [227] source=multitask_sft_big

**USER:** Design 20 de novo CDR-H3 loop sequences (lengths 10-16 residues) grafted onto the Trastuzumab heavy-chain framework targeting the human HER2 extracellular domain IV (PDB: 1N8Z). Ensure the designs exhibit favorable developability: exclude N-glycosylation (NxS/T), deamidation (DG/DS), and isomerization/cleavage (DP) motifs, maintain CDR-H3 GRAVY score between -0.8 and +0.2, and keep candidate net pI within 6.0-8.5.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain IV", "pdb_id": "1N8Z", "uniprot_id": "P04626"}, "scaffold_policy": {"framework": "Trastuzumab (anti-HER2 IgG1) heavy chain framework", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "redesign_region": "CDR-H3", "cdr_definition": "Chothia"}, "property_envelope": {"cdr_h3_length": [10, 16], "gravy_range": [-0.8, 0.2], "isoelectric_point_range": [6.0, 8.5], "excluded_sequence_motifs": ["N[^P][ST]", "DG", "DS", "DP"]}, "count": 20}

---

## [228] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide binders targeting the Keap1 Kelch domain (PPI partner of Nrf2, PDB: 2FLU). Peptides should be cyclized (head-to-tail or hydrocarbon/thioether staple) with a length of 7-12 amino acids. Ensure high predicted affinity (Kd < 50 nM), MW between 800 and 1500 Da, cLogP between -1.5 and 2.5, and polar surface area (tPSA) < 400 Å².

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (PDB: 2FLU)", "scaffold_policy": "Macrocyclic peptide (head-to-tail or staple cyclization, 7-12 residues)", "property_envelope": {"affinity_Kd": "< 50 nM", "molecular_weight": [800, 1500], "clogP": [-1.5, 2.5], "tPSA": "< 400 \u00c5\u00b2", "peptide_length": [7, 12]}, "count": 20}

---

## [229] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loop candidates to replace the heavy chain CDR3 of the humanized antibody scaffold targeting SARS-CoV-2 Omicron Spike RBD (PDB ID: 7TN0). The generated CDR-H3 loops should have lengths between 11 and 16 residues, optimize interface packing, maintain an overall net loop charge between -1 and +2 at pH 7.4, keep pI within 6.0–8.5, and completely exclude sequence motifs prone to post-translational liabilities (specifically deamidation motifs NG/NS and isomerization motifs DG/DS).

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Omicron Spike RBD", "pdb_id": "7TN0"}, "scaffold_policy": {"scaffold": "PDB: 7TN0 Fab heavy chain framework", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "redesign_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [11, 16], "isoelectric_point": [6.0, 8.5], "net_charge_at_pH_7_4": [-1, 2], "avoid_motifs": ["NG", "NS", "DG", "DS"]}, "count": 50}

---

## [230] source=multitask_sft_big

**USER:** Please generate 50 novel, drug-like small molecules with optimal lipophilicity and a low risk of cardiotoxicity. Specifically, ensure compounds have a clogP between 1.5 and 3.0, a predicted hERG IC50 > 30 µM, molecular weight below 450 Da, and TPSA between 60 and 110 Å². Explore diverse chemotypes without fixing a specific core scaffold.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "diverse", "property_envelope": {"clogP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 30.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 110.0}}, "count": 50}

---

## [231] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptides targeting the p53-binding pocket of human MDM2 (UniProt Q00987) to disrupt the MDM2-p53 interaction. The macrocycles should contain between 8 and 14 amino acid residues, utilizing either head-to-tail amide cyclization or a hydrocarbon stapling architecture. Candidates must have predicted binding affinity Kd < 100 nM, molecular weight under 1600 Da, clogP between -1.0 and 2.5, at least 2 hydrogen bond donors, and high predicted serum stability (half-life > 4 hours).

**ASSISTANT:** {"stage": "generate", "target": {"protein": "MDM2", "uniprot_id": "Q00987", "binding_site": "p53 transactivation domain binding cleft"}, "scaffold_policy": {"modality": "macrocyclic peptide", "sequence_length": {"min": 8, "max": 14}, "cyclization_type": ["head-to-tail", "hydrocarbon_staple"]}, "property_envelope": {"affinity_kd_nM": {"max": 100}, "molecular_weight": {"max": 1600}, "clogP": {"min": -1.0, "max": 2.5}, "hbd": {"min": 2}, "serum_half_life_hours": {"min": 4.0}}, "count": 20}

---

## [232] source=multitask_sft_big

**USER:** Design 20 novel, drug-like core scaffolds targeting the kinase ATP-binding pocket (specifically EGFR L858R/T790M). The new scaffolds must be structurally distinct from known kinase inhibitor chemotypes, explicitly avoiding quinazoline, pyrazolopyrimidine, and indolinone cores. All candidates must include a hinge-binding donor-acceptor feature, adhere to MW 350-480 Da, LogP 1.5-3.8, TPSA 60-100 Å², HBD <= 3, HBA 4-8, RotB <= 7, and be free of PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP-binding site (EGFR L858R/T790M)", "scaffold_policy": {"type": "novel", "excluded_cores": ["quinazoline", "pyrazolopyrimidine", "indolinone"], "required_pharmacophore": "hinge-binding motif (donor-acceptor pair)"}, "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "logP": {"min": 1.5, "max": 3.8}, "tpsa": {"min": 60.0, "max": 100.0}, "hbd": {"max": 3}, "hba": {"min": 4, "max": 8}, "rotatable_bonds": {"max": 7}, "exclude_pains": true, "exclude_reactive_warheads": true}, "count": 20}

---

## [233] source=multitask_sft_big

**USER:** Design 50 de novo small molecule candidates with balanced lipophilicity and a low risk of cardiotoxicity. The molecules should have a cLogP between 1.5 and 3.0, hERG IC50 > 10 µM (pIC50 < 5.0), MW < 450 Da, and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"cLogP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 120.0}}, "count": 50}

---

## [234] source=multitask_sft_big

**USER:** Design 20 de-novo linkers connecting a VHL E3 ligase ligand (VH032 derivative via terminal hydroxyl/amine attachment) to a BRD4 warhead (JQ1-derived carboxylic acid exit vector). The linkers should feature 8 to 14 linear connecting atoms, incorporating semi-rigid elements like piperazine, azetidine, or bicyclic motifs to avoid floppy polyethylene glycol (PEG) chains. Linker logP should be restricted to 0.5–2.5, rotatable bonds in the linker between 5 and 10, total PROTAC MW < 950 Da, and exclude labile functional groups such as esters, hydrazones, or unstable acetals.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex", "scaffold_policy": "fixed_warheads_variable_linker", "property_envelope": {"linker_chain_length_atoms": [8, 14], "linker_clogP": [0.5, 2.5], "linker_rotatable_bonds": [5, 10], "full_protac_mw_max": 950, "excluded_substructures": ["ester", "hydrazone", "acetal", "long_aliphatic_chain_gt_6"], "preferred_motifs": ["piperazine", "azetidine", "oxetane", "rigid_heterocycles"]}, "count": 20}

---

## [235] source=multitask_sft_big

**USER:** Please design 8 de novo RNA aptamer sequences targeting the human vascular endothelial growth factor 165 (VEGF-165, UniProt: P15692). The aptamers should be 30 to 45 nucleotides in length, possess a GC content between 45% and 60%, fold into stable secondary structures with a predicted minimum free energy (MFE) <= -12.0 kcal/mol, and demonstrate high predicted target binding affinity with a KD < 20 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "de_novo", "property_envelope": {"polymer_type": "RNA", "sequence_length": {"min": 30, "max": 45}, "gc_content": {"min": 0.45, "max": 0.6}, "mfe_kcal_per_mol": {"max": -12.0}, "kd_nm": {"max": 20.0}}, "count": 8}

---

## [236] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loops grafted into a humanized Trastuzumab-like VH framework (IGHV3-23*01 / IGHJ4*01) targeting the receptor-binding domain (RBD) of SARS-CoV-2 (PDB: 6M0J). The new CDR-H3 loops should have a length between 12 and 16 amino acids, establish complementary contacts at the ACE2-binding interface (specifically targeting residues Lys417, Tyr449, and Gln493), and display zero sequence liabilities (eliminate N-linked glycosylation N-X-S/T, NG deamidation, and DP cleavage motifs). Filter for candidates with predicted high binding affinity (pKd > 8.5) and low hydrophobic patch surface area (SAP score < 35).

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike Receptor-Binding Domain (RBD)", "structure_reference": "PDB 6M0J", "epitope_residues": ["Lys417", "Tyr449", "Gln493"]}, "scaffold_policy": {"framework": "Human germline IGHV3-23*01 / IGHJ4*01", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "loop_length_range": [12, 16]}, "property_envelope": {"predicted_pKd": {"min": 8.5}, "spatial_aggregation_propensity_score": {"max": 35.0}, "motif_exclusions": ["N[^P][ST]", "NG", "DP"]}, "count": 50}

---

## [237] source=multitask_sft_big

**USER:** We are initiating a hit-discovery campaign for a novel Type I kinase inhibitor targeting CDK2. Please generate 50 de-novo central scaffolds capable of engaging the hinge region (forming 1-3 donor/acceptor hydrogen bonds). Scaffolds must be distinct from common classical kinase chemotypes such as 4-anilinoquinazolines, pyrazolopyrimidines, or staurosporine derivatives. Maintain drug-like properties: MW between 250 and 380 Da, cLogP between 1.5 and 3.5, TPSA between 60 and 100 Å², rotatable bonds <= 4, and exclude PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "CDK2", "scaffold_policy": "Novel heterocyclic cores distinct from 4-anilinoquinazolines, pyrazolopyrimidines, and staurosporine analogs, containing suitable vectors and donor/acceptor pairs for hinge-region binding", "property_envelope": {"MW": [250, 380], "cLogP": [1.5, 3.5], "TPSA": [60, 100], "rotatable_bonds_max": 4, "structural_filters": ["PAINS", "reactive_functional_groups"]}, "count": 50}

---

## [238] source=multitask_sft_big

**USER:** Design 15 de-novo CDR-H3 loops grafted onto the Trastuzumab variable heavy chain framework to target the extracellular domain of HER2 (PDB 1N8Z). Retain the existing framework and CDR-H1/H2 regions, generating only the CDR-H3 loop with lengths between 10 and 16 residues. Ensure candidates lack N-glycosylation motifs (N-X-S/T), exhibit low hydrophobic surface patches to minimize aggregation, maintain a net charge between 0 and +3 at neutral pH, and show high predicted binding affinity to the target epitope.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain", "pdb_id": "1N8Z"}, "scaffold_policy": {"scaffold": "Trastuzumab VH", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "redesign_region": "CDR-H3 (Kabat residues 95-102)"}, "property_envelope": {"cdr_h3_length": [10, 16], "net_charge_ph7": [0, 3], "motifs_excluded": ["N[^P][ST]"], "aggregation_propensity": "low", "predicted_binding_affinity": "high"}, "count": 15}

---

## [239] source=multitask_sft_big

**USER:** Generate 10 novel drug-like small molecules designed de novo. The designs must demonstrate reduced cardiotoxicity risk with hERG inhibition IC50 > 10 µM (pIC50 < 5.0), an optimal lipophilicity profile with LogP between 1.5 and 3.0, MW ≤ 450 Da, and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "novel", "property_envelope": {"LogP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 10}

---

## [240] source=multitask_sft_big

**USER:** Design 25 de-novo drug-like small molecules targeting the Dopamine D2 receptor that optimize lipophilicity and mitigate cardiotoxicity risks. The compounds should possess a balanced LogP between 1.5 and 3.0 to ensure good oral bioavailability, with minimized hERG inhibition demonstrated by an anticipated hERG IC50 > 10 µM. Keep molecular weight between 300 and 450 Da, TPSA between 50 and 90 Å², and generate diverse novel cores while avoiding classic hERG-inducing basic lipophilic amine motifs.

**ASSISTANT:** {"stage": "generate", "target": "Dopamine D2 receptor", "scaffold_policy": {"diversity": "high", "core_type": "novel", "exclude_motifs": ["lipophilic basic amines", "promiscuous hERG pharmacophores"]}, "property_envelope": {"LogP": {"min": 1.5, "max": 3.0}, "hERG_IC50": {"min": 10.0, "unit": "uM"}, "molecular_weight": {"min": 300, "max": 450, "unit": "Da"}, "TPSA": {"min": 50, "max": 90, "unit": "\u00c5\u00b2"}}, "count": 25}

---

## [241] source=multitask_sft_big

**USER:** We are designing PROTAC degraders targeting BRD4 using a JQ1-derived targeting moiety and a VHL E3 ligase ligand (VH032-derived). Please generate 50 novel, semi-rigid linkers connecting the designated exit vectors on the warhead and E3 ligase binder. Avoid generic aliphatic PEG chains in favor of linkers containing saturated heterocycles or sp3-rich bioisosteric motifs. The linker chain length should span 10 to 16 atoms. The resulting linkers must have a cLogP between 1.0 and 3.5, TPSA <= 80 Å², no more than 9 rotatable bonds, and exclude unstable groups such as esters, hydrazones, or peroxides.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linker", "scaffold_policy": {"linker_design": true, "warhead": "JQ1-derivative vector", "e3_ligand": "VH032-derivative vector", "preferred_motifs": ["piperazine", "spirocyclic", "azetidine", "sp3-rich aliphatic heterocycles"], "excluded_motifs": ["polyethylene_glycol_chains", "ester", "hydrazone", "peroxide"]}, "property_envelope": {"linker_atom_length": {"min": 10, "max": 16}, "clogp": {"min": 1.0, "max": 3.5}, "tpsa": {"max": 80.0}, "rotatable_bonds": {"max": 9}}, "count": 50}

---

## [242] source=multitask_sft_big

**USER:** Design 50 de novo linkers connecting a JQ1-derived warhead (BRD4 binder, phenolic exit vector) to a VHL E3 ligase recruiter (VH032 derivative, terminal amine exit vector). The resulting linkers should span 8 to 14 linear heavy atoms, prioritize drug-like heterocycles and alkynes over purely aliphatic or poly-PEG motifs (maximum 2 PEG units), avoid labile bonds such as esters, and keep the linker fragment MW below 250 Da, cLogP between 0.5 and 2.5, and linker tPSA under 50 Å² to improve overall PROTAC cell permeability.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC", "scaffold_policy": "Bifunctional linker joining JQ1 phenolic oxygen and VH032 amine; restrict to <= 2 PEG repeats, exclude hydrolyzable esters, incorporate rigidifying motifs", "property_envelope": {"linker_heavy_atom_length": [8, 14], "linker_mw_max": 250, "linker_clogp": [0.5, 2.5], "linker_tpsa_max": 50, "max_peg_units": 2}, "count": 50}

---

## [243] source=multitask_sft_big

**USER:** Design 25 de-novo lead-like small molecules optimized for metabolic stability and cardiovascular safety. Target a balanced logP between 1.5 and 3.0 and minimize hERG liabilities with predicted hERG IC50 > 10 µM (pIC50 < 5.0). Maintain MW under 450 Da, TPSA between 60 and 120 Å², and avoid strongly basic tertiary amines.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "free", "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 120.0}}, "count": 25}

---

## [244] source=multitask_sft_big

**USER:** Generate 15 novel core scaffolds targeting the ATP-binding site of EGFR (T790M/C797S) that diverge from traditional quinazoline and pyrimidine chemotypes. The structures should be non-covalent, drug-like, and satisfy: MW between 300 and 450 Da, LogP 2.0-4.0, tPSA <= 100 Å², HBD <= 3, and HBA 3-7. Filter out PAINS and reactive functional groups.

**ASSISTANT:** {"stage": "generate", "target": "EGFR (T790M/C797S) kinase ATP-binding site", "scaffold_policy": "novel core divergent from quinazoline and pyrimidine", "property_envelope": {"MW": [300, 450], "LogP": [2.0, 4.0], "tPSA": [0, 100], "HBD": [0, 3], "HBA": [3, 7], "filter_PAINS": true, "reactive_groups": false}, "count": 15}

---

## [245] source=multitask_sft_big

**USER:** Design 20 novel, synthetically tractable kinase inhibitor scaffolds targeting CDK2 that explore new intellectual property space. Avoid common aminopyrimidine, quinazoline, and indolin-2-one cores. The molecules must present a classical donor-acceptor hinge-binding motif compatible with the Leu83 backbone. Maintain drug-like properties: MW between 300 and 450 Da, cLogP <= 3.5, TPSA between 60 and 110 Å², rotatable bonds <= 6, and synthetic accessibility score (SAS) < 4.0, with no PAINS or reactive groups.

**ASSISTANT:** {"stage": "generate", "target": "CDK2 kinase hinge region", "scaffold_policy": {"novelty": "Novel chemotypes; exclude aminopyrimidine, quinazoline, and indolin-2-one cores", "pharmacophore": "Donor-acceptor hinge-binding motif targeting Leu83"}, "property_envelope": {"molecular_weight": [300, 450], "clogp": "<= 3.5", "tpsa": [60, 110], "rotatable_bonds": "<= 6", "synthetic_accessibility_score": "< 4.0", "filters": ["PAINS", "reactive_toxicophores"]}, "count": 20}

---

## [246] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human VEGF-165 (P15692). The sequences should be between 35 and 45 nucleotides in length, possess a predicted minimum folding free energy (ΔG) below -12.0 kcal/mol to ensure a stable secondary structure (hairpin/stem-loop motifs), maintain a GC content between 40% and 60%, and exhibit high predicted binding affinity (Kd < 50 nM) against the heparin-binding domain of VEGF-165.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "de novo unconstrained single-stranded RNA", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "gc_content_pct": {"min": 40.0, "max": 60.0}, "mfe_folding_dG_kcal_mol": {"max": -12.0}, "predicted_binding_affinity_kd_nM": {"max": 50.0}, "target_domain": "Heparin-binding domain"}, "count": 5}

---

## [247] source=multitask_sft_big

**USER:** Design 20 de novo CDR-H3 loop sequences for the trastuzumab framework scaffold targeting the human HER2 extracellular domain (PDB: 1N8Z, Chain A). Keep the VH/VL framework residues and CDR-H1, CDR-H2, CDR-L1, CDR-L2, and CDR-L3 fixed, generating only the CDR-H3 loop (Chothia definitions: H95-H102). The designed loops must have a length between 11 and 15 amino acids, predicted interface binding energy (dG_separated) < -35.0 REU, net charge between -1 and +2 at pH 7.4, maximum hydrophobic patch size under 250 Å², zero unpaired cysteines, and OAS humanness score > 0.82.

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 (ErbB2) extracellular domain (PDB: 1N8Z, Chain A)", "scaffold_policy": {"framework": "Trastuzumab (anti-HER2) variable heavy and light chains", "fixed_regions": ["VH framework", "VL framework", "CDR-H1", "CDR-H2", "CDR-L1", "CDR-L2", "CDR-L3"], "design_region": "CDR-H3 (Chothia positions H95 to H102)"}, "property_envelope": {"cdr_h3_length": [11, 15], "predicted_binding_energy_reu": {"max": -35.0}, "net_charge_ph7_4": {"min": -1.0, "max": 2.0}, "hydrophobic_patch_area_sq_angstrom": {"max": 250.0}, "unpaired_cysteines": 0, "humanness_score": {"min": 0.82}}, "count": 20}

---

## [248] source=multitask_sft_big

**USER:** Design 50 novel kinase inhibitor scaffolds targeting the ATP-binding site of EGFR (L858R/T790M). Exclude classical quinazoline and 2,4-diaminopyrimidine chemotypes to maximize IP novelty. Aim for the following physicochemical profile: MW between 350 and 480 Da, LogP 2.0–4.2, TPSA 60–110 Å², HBD ≤ 3, HBA ≤ 7, rotatable bonds ≤ 6, and no PAINS or reactive substructures.

**ASSISTANT:** {"stage": "generate", "target": "EGFR kinase domain (L858R/T790M mutant)", "scaffold_policy": "novel non-quinazoline, non-diaminopyrimidine core", "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "logP": {"min": 2.0, "max": 4.2}, "tpsa": {"min": 60, "max": 110}, "hbd": {"max": 3}, "hba": {"max": 7}, "rotatable_bonds": {"max": 6}, "exclude_alerts": ["PAINS", "reactive_groups"]}, "count": 50}

---

## [249] source=multitask_sft_big

**USER:** Please generate 15 de novo RNA aptamer sequences targeting the exosite I of human alpha-thrombin. Candidates should be 30 to 45 nucleotides in length, maintain a GC content between 40% and 60%, and exhibit folded minimum free energy (MFE) between -18.0 and -6.0 kcal/mol to balance conformational flexibility and stable tertiary structure. Ensure sequences do not contain homopolymer tracts longer than 4 identical nucleotides (especially poly-U) and prioritize predicted high binding affinity (target Kd < 50 nM).

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin exosite I (UniProt: P00734)", "scaffold_policy": "de novo single-stranded RNA sequences composed of canonical ribonucleotides (A, C, G, U) without pre-defined fixed primer cassettes", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "minimum_free_energy_kcal_mol": {"min": -18.0, "max": -6.0}, "max_homopolymer_run": 4, "target_binding_affinity_kd_nm": {"max": 50.0}}, "count": 15}

---

## [250] source=multitask_sft_big

**USER:** Generate 50 novel small-molecule candidates with optimized lipophilicity, targeting a clogP between 1.5 and 3.0, while minimizing hERG cardiotoxicity liability (predicted hERG IC50 > 10 µM). Keep molecular weight under 450 Da and TPSA within 60 to 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 50}

---

## [251] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamers targeting human VEGF-165 (UniProt: P15692). The sequences should be generated de novo with a length between 35 and 45 nucleotides. Each aptamer should have a predicted binding affinity (Kd) below 50 nM, a minimum free energy (MFE) of secondary structure folding below -10.0 kcal/mol, a GC content between 40% and 60%, and avoid homopolymer tracts longer than 4 consecutive identical bases.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor A (VEGF-165, UniProt: P15692)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "affinity_kd_nM": {"max": 50}, "mfe_folding_kcal_mol": {"max": -10.0}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "max_homopolymer_length": 4}, "count": 10}

---

## [252] source=multitask_sft_big

**USER:** Design 10 novel de-novo RNA aptamers targeting the human thrombin exosite I. Sequences should be between 30 and 45 nucleotides, have a GC content between 40% and 60%, achieve an estimated binding affinity (Kd) < 50 nM, and contain no homopolymer tracts of G or U longer than 4 nt to prevent synthesis issues.

**ASSISTANT:** {"stage": "generate", "target": "Human thrombin (exosite I)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content_percent": {"min": 40, "max": 60}, "affinity_kd_nm": {"max": 50}, "max_homopolymer_run": {"G": 4, "U": 4}}, "count": 10}

---

## [253] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loop candidates targeted against the HER2 extracellular domain (PDB: 1N8Z) using the Trastuzumab heavy-chain framework. The redesigned CDR-H3 loops should have a length between 10 and 16 residues, predicted binding affinity with Kd < 5 nM, a net CDR charge between -1 and +2 at pH 7.4, and zero sequence liabilities including deamidation (NG, NS), isomerization (DG), or unpaired cysteines.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain", "pdb_id": "1N8Z"}, "scaffold_policy": {"scaffold": "Trastuzumab humanized VH framework", "redesign_region": "CDR-H3", "length_range": [10, 16], "preserve_framework": true}, "property_envelope": {"binding_affinity_Kd_max_nM": 5.0, "net_charge_range": [-1, 2], "unpaired_cysteines": 0, "forbidden_motifs": ["NG", "NS", "DG"]}, "count": 50}

---

## [254] source=multitask_sft_big

**USER:** Please design 8 novel RNA aptamers targeting human alpha-thrombin (PDB: 1HAP). The candidates should be between 30 and 45 nucleotides in length, composed of standard ribonucleotides (A, C, G, U), have an estimated binding affinity Kd < 50 nM, a predicted minimum free energy (MFE) between -18.0 and -8.0 kcal/mol, and a GC content within 40% to 65%.

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin (PDB: 1HAP)", "scaffold_policy": "De novo RNA sequences, length 30-45 nt, canonical ribonucleotides (A, C, G, U) without predefined primer-binding regions", "property_envelope": {"binding_affinity_Kd": "< 50 nM", "minimum_free_energy_kcal_mol": "[-18.0, -8.0]", "gc_content_pct": "[40, 65]"}, "count": 8}

---

## [255] source=multitask_sft_big

**USER:** Generate 8 novel RNA aptamers targeting human VEGF-165 (Vascular Endothelial Growth Factor). The sequences must be designed de novo without pre-defined scaffold constraints. Each aptamer should have a length between 35 and 50 nucleotides, a predicted binding affinity Kd < 50 nM, a GC content ranging from 40% to 60%, and a secondary structure minimum free energy (MFE) below -12.0 kcal/mol to ensure thermodynamic stability.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 35, "max": 50, "unit": "nt"}, "Kd": {"max": 50, "unit": "nM"}, "gc_content": {"min": 40.0, "max": 60.0, "unit": "%"}, "minimum_free_energy": {"max": -12.0, "unit": "kcal/mol"}}, "count": 8}

---

## [256] source=multitask_sft_big

**USER:** Design 15 de novo CDR-H3 loops to graft onto a human VH3-23 framework to bind the SARS-CoV-2 Spike Receptor Binding Domain (PDB: 6M0J). CDR-H3 length should be between 11 and 16 amino acids. Ensure high predicted binding affinity (pKd > 8.0), loop stability, net charge between 0 and +2 at pH 7.4, and filter out sequence liabilities including N-glycosylation motifs (N-X-S/T), free cysteines, and high hydrophobic patch density.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike RBD", "pdb_id": "6M0J", "target_type": "protein"}, "scaffold_policy": {"framework": "human IGHV3-23 / IGHJ4", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [11, 16], "predicted_pKd": {"min": 8.0}, "net_charge_pH_7_4": {"min": 0, "max": 2}, "excluded_motifs": ["N[^P][ST]", "C"], "max_hydrophobic_patch_fraction": 0.3}, "count": 15}

---

## [257] source=multitask_sft_big

**USER:** Generate 50 novel bifunctional PROTAC linkers to connect a BRD4-binding moiety (JQ1 derivative via terminal carboxylate) and a VHL E3 ligase binder (VH032 derivative via terminal amine). The linkers should have an extended chain length of 8 to 14 atoms, prioritize semi-rigid motifs such as piperazines or spirocycles to limit conformational entropy, maintain linker molecular weight between 100 and 280 Da, linker TPSA below 75 Å², and avoid hydrolytically unstable or metabolically labile moieties (e.g., unhindered esters, hydrazones).

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL", "scaffold_policy": "linker_design_between_fixed_warhead_and_e3", "property_envelope": {"linker_chain_length_atoms": "8-14", "linker_molecular_weight": "100-280", "linker_tpsa": "<= 75", "rotatable_bond_limit": "semi-rigid preferred (<= 8 rotatable bonds)", "reactive_group_filter": "exclude esters, hydrazones, acyl hydrazides, alkyl halides"}, "count": 50}

---

## [258] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loops targeting the receptor-binding domain (RBD) of the SARS-CoV-2 Spike protein (PDB: 6M0J, Chain E). Graft the new CDR-H3 designs onto a human IGHV3-53 framework, keeping CDR-H1, CDR-H2, and the light chain constant. The CDR-H3 length should be restricted to 12-16 amino acids. Ensure high predicted affinity (predicted pKd > 8.0), a CDR-H3 net charge between -1 and +2, GRAVY score < 0.0, and eliminate developability liabilities including N-glycosylation motifs (N-X-[S/T]), free cysteines, and poly-aromatic runs (>=3 consecutive Phe/Trp/Tyr).

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike RBD", "pdb_id": "6M0J", "target_chain": "E"}, "scaffold_policy": {"antibody_scaffold": "human IGHV3-53", "region_to_design": "CDR-H3", "length_range": [12, 16], "fixed_regions": ["CDR-H1", "CDR-H2", "FR1-FR4", "VL"]}, "property_envelope": {"predicted_pKd_min": 8.0, "net_charge_range": [-1, 2], "gravy_score_max": 0.0, "forbidden_motifs": ["N[^P][ST]", "C", "[FWY]{3,}"]}, "count": 50}

---

## [259] source=multitask_sft_big

**USER:** Please design 50 de novo macrocyclic peptide binders targeting the human Keap1 Kelch domain to disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should contain 7 to 12 amino acid residues with head-to-tail backbone or sidechain-to-tail cyclization, incorporating a beta-turn motif mimicking the native Nrf2 ETGE loop. Filter for predicted binding affinity Kd < 50 nM, molecular weight between 800 and 1500 Da, cLogP between -2.5 and 2.0, and polar surface area (tPSA) < 450 Å² to optimize for target-site complementarity and proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "human Keap1 Kelch domain (disrupting Keap1-Nrf2 PPI)", "scaffold_policy": "Macrocyclic peptide (7-12 amino acids) with head-to-tail backbone or sidechain-to-tail cyclization, incorporating an ETGE-mimetic beta-turn motif", "property_envelope": {"MW": "800 - 1500 Da", "cLogP": "-2.5 to 2.0", "tPSA": "< 450 \u00c5\u00b2", "predicted_Kd": "< 50 nM", "sequence_length": "7 - 12 residues"}, "count": 50}

---

## [260] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops targeting the LDLR-binding interface of human PCSK9 (PDB ID: 2P4E, Chain A). Graft the designs onto a humanized VH3-23/JH4 framework scaffold, keeping framework regions, CDR-H1, and CDR-H2 invariant. The CDR-H3 loop length should range between 12 and 16 residues. Designs must show high predicted binding complementarity to PCSK9, avoid liability motifs (N-linked glycosylation N-X-[S/T], unpaired cysteines, and DP/DG cleavage sites), maintain a net charge between -1 and +2 at pH 7.4, and demonstrate low hydrophobic patch exposure to minimize polyreactivity risks.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human Proprotein Convertase Subtilisin/Kexin Type 9 (PCSK9)", "pdb_id": "2P4E", "target_chain": "A", "binding_site": "LDLR EGF-A binding domain interface (residues Arg194, Phe216, Arg218, Asp374)"}, "scaffold_policy": {"framework": "IGHV3-23*01 / IGHJ4*01", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "redesign_region": "CDR-H3 (IMGT positions 105-117)"}, "property_envelope": {"cdr_h3_length": [12, 16], "net_charge_pH_7_4": [-1.0, 2.0], "max_hydrophobic_patch_area_A2": 400.0, "sequence_liabilities": {"unpaired_cysteines": false, "n_glycosylation": false, "aspartate_isomerization": false, "acid_cleavage": false}, "predicted_binding_affinity": "sub-micromolar (< 100 nM)"}, "count": 50}

---

## [261] source=multitask_sft_big

**USER:** Design 25 de-novo drug-like small molecules with balanced lipophilicity (clogP between 1.5 and 2.8) and high hERG safety (predicted hERG IC50 > 10 µM / pIC50 < 5.0). Ensure molecular weight is below 450 Da and polar surface area (TPSA) is between 60 and 110 Å² to minimize cardiotoxicity risks.

**ASSISTANT:** {"stage": "generate", "target": "hERG (antitarget)", "scaffold_policy": null, "property_envelope": {"clogP": {"min": 1.5, "max": 2.8}, "hERG_pIC50": {"max": 5.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 110.0}}, "count": 25}

---

## [262] source=multitask_sft_big

**USER:** Generate 50 novel PROTAC linkers connecting a JQ1-derived BRD4 warhead (amine exit vector) to a VH032-derived VHL ligase binder. Focus on semi-rigid linkers incorporating sp3-rich heterocycles (such as piperazine, azetidine, or morpholine motifs) rather than purely flexible aliphatic or PEG chains to reduce conformational entropy. Constrain linker length to 8–14 heavy atoms, linker cLogP to 0.5–3.0, linker rotatable bonds to <= 8, and overall PROTAC molecular weight to < 1100 Da.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linkers", "scaffold_policy": "de-novo semi-rigid linkers connecting specified warhead and E3 exit vectors", "property_envelope": {"linker_heavy_atom_count": [8, 14], "linker_clogP": [0.5, 3.0], "linker_rotatable_bonds": "<= 8", "total_protac_mw": "< 1100"}, "count": 50}

---

## [263] source=multitask_sft_big

**USER:** Generate 25 novel drug-like small molecules with optimized lipophilicity and a low risk of cardiotoxicity. Compounds should have a calculated logP (cLogP) strictly between 1.5 and 3.0, and minimal hERG channel inhibition (predicted hERG IC50 > 10 µM or pIC50 < 5.0). Keep molecular weight under 450 Da, topological polar surface area (TPSA) between 60 and 110 Å², and avoid strong basic tertiary amines prone to hERG pharmacophore matching.

**ASSISTANT:** {"stage": "generate", "target": "hERG (anti-target)", "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 110.0}}, "count": 25}

---

## [264] source=multitask_sft_big

**USER:** Design 20 novel small-molecule kinase inhibitor scaffolds targeting the ATP-binding site of EGFR T790M/C797S. We require structurally diverse, non-traditional hinge-binding cores avoiding quinazoline and aminopyrimidine chemotypes. Candidates should strictly comply with drug-like property criteria: MW 350-500 Da, cLogP 2.0-4.5, TPSA <= 110 Å², HBD <= 3, and rotatable bonds <= 6.

**ASSISTANT:** {"stage": "generate", "target": "EGFR (T790M/C797S)", "scaffold_policy": "novel non-quinazoline, non-aminopyrimidine hinge-binding scaffolds", "property_envelope": {"mw": [350, 500], "clogp": [2.0, 4.5], "tpsa": [0, 110], "hbd": [0, 3], "rotatable_bonds": [0, 6]}, "count": 20}

---

## [265] source=multitask_sft_big

**USER:** Generate 5 de novo RNA aptamer candidates targeting human VEGF-165 (UniProt: P15692-4). Sequences should be 35 to 45 nucleotides in length, maintain a GC content between 45% and 60%, avoid homopolymer runs longer than 3 nucleotides (especially poly-G), and exhibit predicted strong binding affinity with Kd < 20 nM while adopting a stable secondary structure.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692-4)", "scaffold_policy": "none", "property_envelope": {"length": [35, 45], "gc_content": [0.45, 0.6], "max_homopolymer_run": 3, "predicted_kd_nm": {"max": 20}}, "count": 5}

---

## [266] source=multitask_sft_big

**USER:** Generate 10 novel RNA aptamer candidates targeting the extracellular domain of human HER2 (ERBB2). The library design requires a central 40-nucleotide randomized region flanked by 5'-GGGAGAGAGGAAGAGGGA-3' and 3'-UAAUAACGACUCACUAUA-5' constant primer sites. Sequences must have a GC content between 45% and 60%, a minimum free energy (MFE) of secondary structure folding less than -14 kcal/mol to ensure stable hairpin/pseudoknot formation, avoid G-quadruplex-disrupting poly-G tracts longer than 4 nt, and show high predicted binding affinity (target Kd < 50 nM).

**ASSISTANT:** {"stage": "generate", "target": "Human epidermal growth factor receptor 2 (HER2/ERBB2) extracellular domain", "scaffold_policy": {"variable_length": 40, "5_prime_flank": "GGGAGAGAGGAAGAGGGA", "3_prime_flank": "AUAUCAUCACUCAUAAU"}, "property_envelope": {"gc_content_min": 0.45, "gc_content_max": 0.6, "mfe_max_kcal_per_mol": -14.0, "max_homopolymer_g": 4, "target_kd_nM": 50}, "count": 10}

---

## [267] source=multitask_sft_big

**USER:** Design 50 novel bifunctional linkers to bridge our VHL E3 ligase ligand (VH032 derivative exit vector at the 4-hydroxyproline terminal amide) to an Androgen Receptor (AR) warhead. Please prioritize semi-rigid motifs containing piperazine, piperidine, or bridged bicyclic scaffolds over linear PEG chains to limit conformational entropy, targeting an attachment vector distance of 9 to 14 Å. For the linker core alone, keep MW under 280 Da, clogP between 1.0 and 3.0, TPSA <= 75 Å², and rotatable bond count <= 7.

**ASSISTANT:** {"stage": "generate", "target": "AR / VHL PROTAC ternary complex", "scaffold_policy": "Semi-rigid bifunctional linkers incorporating heterocyclic or bridged rings; avoid unbranched aliphatic/PEG chains", "property_envelope": {"linker_MW": "<= 280", "clogP": "1.0 - 3.0", "TPSA": "<= 75", "rotatable_bonds": "<= 7", "vector_distance_angstroms": "9 - 14"}, "count": 50}

---

## [268] source=multitask_sft_big

**USER:** Design 20 de-novo CDR-H3 loops (12-16 amino acids) targeting the human TIGIT extracellular domain (PDB: 3UDW, chain A) using the human VH3-23 framework from trastuzumab (PDB: 1N8Z) as the fixed scaffold. The engineered loops should achieve an interface Rosetta energy score (dG_separated) < -35 REU, CDR-H3 net charge between -1 and +2, OASis humanness score >= 0.75, and contain zero sequence liabilities (exclude motifs: N-glycosylation N[^P][ST], deamidation NG/NS, isomerization DG, and unpaired cysteines).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human T-cell immunoreceptor with Ig and ITIM domains (TIGIT)", "structure_source": "PDB: 3UDW", "target_chain": "A"}, "scaffold_policy": {"scaffold": "Human VH3-23 / trastuzumab VH framework (PDB: 1N8Z)", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4"], "redesign_region": "CDR-H3", "loop_length_range": [12, 16]}, "property_envelope": {"interface_energy_score": "< -35 REU", "cdr_h3_net_charge": "[-1, +2]", "humanness_oas_score": ">= 0.75", "excluded_motifs": ["N[^P][ST]", "NG", "NS", "DG", "C"]}, "count": 20}

---

## [269] source=multitask_sft_big

**USER:** Generate 10 novel RNA aptamers targeting human VEGF-165 with high binding affinity (predicted Kd < 50 nM). Each candidate must contain a 40-nucleotide variable loop region flanked by fixed primer regions (5'-GGGAAGUGAAGCCUG-3' and 5'-CUCGUUGUGCGUG-3'). The central region should have a GC content between 40% and 60%, with a predicted minimum free energy (MFE) of <= -15.0 kcal/mol to guarantee stable secondary structure.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "Fixed 5' and 3' primer-binding handles with a 40-nt de novo variable region", "property_envelope": {"Kd_nM": "<= 50", "GC_content": [0.4, 0.6], "MFE_kcal_mol": "<= -15.0", "variable_length_nt": 40}, "count": 10}

---

## [270] source=multitask_sft_big

**USER:** Design 50 novel, rigidified linkers to conjugate a VHL E3 ligase ligand (exit vector: terminal amine of VH032) to an AR antagonist warhead (exit vector: aryl ether position). The linkers must span between 8 and 14 contiguous atoms, incorporate partially rigid rings (e.g., piperazines, piperidines, or azetidines) to reduce conformational entropy, keep linker fragment MW below 250 Da, have a linker cLogP between 0.5 and 2.5, and exclude metabolically labile ester, hydrazone, or unstable acetal linkages.

**ASSISTANT:** {"stage": "generate", "target": "VHL-AR PROTAC linker", "scaffold_policy": "Bifunctional linker design connecting defined exit vectors on VH032 and AR antagonist; requires semi-rigid heterocycles (piperazine, piperidine, azetidine)", "property_envelope": {"linker_chain_length": [8, 14], "linker_MW": "<250", "linker_cLogP": [0.5, 2.5], "unwanted_substructures": ["ester", "hydrazone", "acetal", "peroxide", "aliphatic_thioether"]}, "count": 50}

---

## [271] source=multitask_sft_big

**USER:** Design 25 novel, diverse linkers connecting our BRD4 warhead (exit vector at JQ1-derived carboxylate: [*:1]C(=O)O) to a CRBN E3 ligase ligand (exit vector at pomalidomide 4-amino: [*:2]Nc1cccc2C(=O)N(C3CCC(=O)NC3=O)C(=O)c12). Linkers should span between 6 and 14 linear heavy atoms, include rigidifying motifs (e.g., piperazines, piperidines, spirocycles, or alkynes) to reduce conformational entropy, and avoid metabolically labile ester or disulfide bonds. Overall conjugate linker properties should maintain drug-like PROTAC profiles: linker MW between 100 and 250 Da, linker clogP between 0.0 and 2.5, and TPSA < 60 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN heterobifunctional degrader (PROTAC)", "scaffold_policy": "linker", "property_envelope": {"linker_heavy_atom_length": [6, 14], "linker_molecular_weight": [100.0, 250.0], "linker_clogP": [0.0, 2.5], "linker_tpsa_max": 60.0, "forbidden_moieties": ["ester", "disulfide", "hydrazine", "peroxide"]}, "count": 25}

---

## [272] source=multitask_sft_big

**USER:** Generate 20 de-novo macrocyclic peptides targeting the p53 binding cleft of MDM2 (PDB: 1YCR) to disrupt the MDM2-p53 interaction. The peptides should be 8-14 amino acids in length, cyclized via head-to-tail or sidechain-to-sidechain stapling, and incorporate non-canonical amino acids to enhance metabolic stability. Target an estimated Kd < 1 µM, molecular weight between 800 and 1600 Da, clogP between 0 and 4.0, and tPSA < 400 Å².

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding site, PDB: 1YCR)", "scaffold_policy": "macrocyclic peptide backbone (8-14 residues, head-to-tail or sidechain-to-sidechain cyclization, non-canonical residues permitted)", "property_envelope": {"MW": "800 - 1600 Da", "clogP": "0 - 4.0", "tPSA": "< 400 \u00c5\u00b2", "predicted_Kd": "< 1 \u00b5M", "peptide_length": "8-14 residues"}, "count": 20}

---

## [273] source=multitask_sft_big

**USER:** Design 25 novel, semi-rigid PROTAC linkers connecting a BRD4-targeting warhead (JQ1 derivative via amide exit vector) to a CRBN E3 ligase ligand (pomalidomide 4-amino exit vector). Avoid repetitive PEG or purely aliphatic chains by incorporating diverse heterocyclic or spirocyclic motifs to improve cooperativity. The linker length should span 8 to 14 heavy atoms. The resulting chimeras must maintain an overall MW < 950 Da, cLogP between 2.0 and 5.0, TPSA < 180 Å², and rotatable bond count <= 12 within the linker segment.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / CRBN", "scaffold_policy": "Fix BRD4 warhead and pomalidomide exit vectors; generate de-novo linkers connecting the two defined attachment points", "property_envelope": {"linker_heavy_atom_count": "8-14", "linker_rotatable_bonds": "<= 12", "chimera_mw": "< 950", "chimera_clogp": "2.0 - 5.0", "chimera_tpsa": "< 180", "structural_motifs": "heterocyclic, spirocyclic, non-PEG, non-aliphatic"}, "count": 25}

---

## [274] source=multitask_sft_big

**USER:** Generate 50 de novo macrocyclic peptide binders targeting the p53-interaction groove of human MDM2. Peptides should consist of 8 to 12 amino acids, cyclized via head-to-tail peptide bonds or hydrocarbon stapling, with molecular weight < 1600 Da, clogP between -0.5 and 3.5, and tPSA < 450 Å² to favor target engagement and cellular permeability.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53 binding interface)", "scaffold_policy": "Macrocyclic peptides, 8-12 residues, head-to-tail or hydrocarbon stapled cyclization", "property_envelope": {"MW": "<= 1600 Da", "clogP": "[-0.5, 3.5]", "tPSA": "< 450 \u00c5\u00b2", "sequence_length": "8-12 residues"}, "count": 50}

---

## [275] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamer sequences targeting the receptor-binding domain of human VEGF-165 (UniProt: P15692). The aptamers must be designed de novo without relying on existing known scaffolds, with a length restricted to 35-45 nucleotides. Each candidate should have a predicted folding free energy (ΔG) below -10.0 kcal/mol at 37 °C, a GC content between 40% and 60%, a stable stem-loop structural motif, and no homopolymeric runs of 4 or more consecutive guanines or uridines.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 receptor-binding domain (UniProt: P15692)", "scaffold_policy": "de-novo", "property_envelope": {"sequence_length": {"min": 35, "max": 45, "unit": "nucleotides"}, "delta_G_folding_37C": {"max": -10.0, "unit": "kcal/mol"}, "gc_content": {"min": 0.4, "max": 0.6}, "secondary_structure": "stem-loop", "forbidden_motifs": ["GGGG", "UUUU"]}, "count": 5}

---

## [276] source=multitask_sft_big

**USER:** Design 10 novel CDR-H3 loop sequences to be grafted onto a human IGHV3-23 / IGHJ4 framework targeting the receptor-binding domain of human PD-L1 (PDB: 4ZQK). The CDR-H3 length must be strictly between 12 and 16 residues. Ensure low developability risk by filtering out N-glycosylation sites (N-X-[S/T]), Asp isomerization motifs (DG), and unpaired cysteines, with a net loop charge between 0 and +2 and hydrophobic surface area under 350 Å².

**ASSISTANT:** {"stage": "generate", "target": {"name": "human PD-L1", "structure_id": "4ZQK", "epitope": "receptor-binding domain"}, "scaffold_policy": {"framework_heavy": "IGHV3-23 / IGHJ4", "design_region": "CDR-H3", "framework_status": "fixed"}, "property_envelope": {"cdr_h3_length": [12, 16], "net_charge": [0, 2], "hydrophobic_surface_area_max": 350.0, "avoid_motifs": ["N[^P][ST]", "DG", "C"]}, "count": 10}

---

## [277] source=multitask_sft_big

**USER:** Design 20 novel chemical scaffolds targeting the ATP-binding site of EGFR kinase. We want to avoid classic quinazoline, pyrimidine, and indazole cores to secure fresh IP. Target compounds should exhibit drug-like physical properties: MW between 320 and 460 Da, LogP 2.0 to 4.2, TPSA between 65 and 100 Å², no more than 5 rotatable bonds, and feature appropriate hydrogen bonding motifs (at least 1 donor and 2 acceptors) for hinge-region engagement.

**ASSISTANT:** {"stage": "generate", "target": "EGFR kinase ATP-binding site", "scaffold_policy": "novel core, exclude quinazoline, pyrimidine, and indazole chemotypes", "property_envelope": {"molecular_weight": [320, 460], "logP": [2.0, 4.2], "tpsa": [65, 100], "rotatable_bonds": "<= 5", "hbd": ">= 1", "hba": ">= 2"}, "count": 20}

---

## [278] source=multitask_sft_big

**USER:** Generate 50 novel drug-like small molecules from scratch designed to mitigate cardiotoxicity risks. Specifically, optimize lipophilicity to an ideal logP range of 1.5 to 3.0 while maintaining a clean hERG safety profile (predicted hERG pIC50 < 5.0, or IC50 > 10 µM). Keep MW under 450 Da and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "free", "property_envelope": {"logP": [1.5, 3.0], "hERG_pIC50": "< 5.0", "MW": "<= 450", "TPSA": [60, 120]}, "count": 50}

---

## [279] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops targeting the extracellular domain of human TIGIT (PDB ID: 3U5D). Graft the designs onto a humanized IGHV3-23*01 / IGHJ4*01 framework scaffold while keeping CDR-H1 and CDR-H2 invariant. The CDR-H3 loop length should be restricted to 12–16 amino acids. Filter out sequences containing unpaired cysteines, N-glycosylation sites (N-X-S/T, X!=P), and contiguous hydrophobic patches (>3 aromatic residues in a row). Ensure the CDR-H3 net charge is between -1 and +2 at physiological pH (7.4), with predicted complex interface metrics of ipTM >= 0.80 and CDR-H3 pLDDT >= 80.

**ASSISTANT:** {"stage": "generate", "target": "Human T cell immunoreceptor with Ig and ITIM domains (TIGIT) extracellular domain (PDB: 3U5D)", "scaffold_policy": "Fixed human IGHV3-23*01 / IGHJ4*01 framework with invariant CDR-H1 and CDR-H2; redesign CDR-H3 region only", "property_envelope": {"cdr_h3_length": [12, 16], "net_charge_at_ph_7_4": [-1, 2], "max_consecutive_aromatics": 3, "forbidden_motifs": ["N[^P][ST]", "C"], "min_iptm": 0.8, "min_plddt": 80}, "count": 50}

---

## [280] source=multitask_sft_big

**USER:** Generate 50 novel de-novo kinase inhibitor scaffolds targeting the ATP-binding site of EGFR. Scaffolds must not contain classical quinazoline or pyrrolopyrimidine cores, should maintain a hydrogen-bond donor-acceptor motif for the hinge region (Met793), and must conform to drug-like space: MW 300-450, cLogP 1.5-3.5, TPSA 60-90 Å², and rotatable bonds ≤ 5.

**ASSISTANT:** {"stage": "generate", "target": "EGFR kinase domain (ATP-binding site)", "scaffold_policy": {"type": "novel_core", "required_motifs": ["hinge_donor_acceptor_pair"], "excluded_substructures": ["quinazoline", "pyrrolo[2,3-d]pyrimidine"]}, "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "clogp": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 60, "max": 90}, "rotatable_bonds": {"max": 5}}, "count": 50}

---

## [281] source=multitask_sft_big

**USER:** Design 50 de novo macrocyclic peptides (8 to 14 amino acids, head-to-tail or sidechain-to-tail cyclization) targeting the p53 binding pocket of MDM2 (PDB: 1YCR) to disrupt the MDM2-p53 protein-protein interaction. The designs should include both canonical and at least one non-canonical or D-amino acid to enhance proteolytic stability. Ensure a predicted binding affinity (pKd) > 8.0, molecular weight between 900 and 1600 Da, topological polar surface area (tPSA) < 350 Å², and high predicted plasma stability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 p53-binding pocket (PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptide (8-14 residues, head-to-tail or sidechain-to-tail cyclized, incorporating at least one non-canonical or D-amino acid)", "property_envelope": {"molecular_weight": [900, 1600], "tPSA_max": 350, "min_affinity_pKd": 8.0, "proteolytic_stability": "high"}, "count": 50}

---

## [282] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops targeting the receptor-binding domain (RBD) of SARS-CoV-2 Spike glycoprotein (PDB: 6M0J). Graft the new CDR-H3 sequences onto the human IGHV3-53 / IGHJ6 framework (preserving canonical CDR-H1 and CDR-H2). The designed loops should be 11 to 15 amino acids long, achieve high predicted binding affinity with an interface pLDDT >= 82 and ipTM >= 0.80, and strictly exclude developability liabilities (no N-linked glycosylation sequons N-X-S/T, no unpaired cysteines, and no Asp-Gly or Asn-Gly motifs).

**ASSISTANT:** {"stage": "generate", "target": "SARS-CoV-2 Spike receptor-binding domain (RBD, PDB: 6M0J)", "scaffold_policy": "Fixed human IGHV3-53/IGHJ6 framework and CDR-H1/H2; de-novo redesign localized entirely to CDR-H3 (Kabat residues 95-102)", "property_envelope": {"cdr_h3_length": [11, 15], "interface_plddt": ">= 82", "iptm": ">= 0.80", "exclude_motifs": ["N[^P][ST]", "C", "DG", "NG"], "max_hydrophobic_patch_percentile": 20}, "count": 50}

---

## [283] source=multitask_sft_big

**USER:** Design 10 de-novo CDR-H3 loops targeted against the human HER2 extracellular domain IV (PDB: 1N8Z). Keep the Trastuzumab VH framework (IGHV3-23/IGHJ4) and CDR-H1/CDR-H2 fixed, along with the full light chain. The redesigned CDR-H3 loop length should be constrained to 12-16 amino acids. Ensure high predicted binding affinity to epitope residues surrounding Thr309 and Lys311, with CDR-H3 net charge between -1 and +2 at pH 7.4, no unpaired cysteines, and strict avoidance of developability liabilities including N-glycosylation motifs (N-X-S/T) and deamidation motifs (NG, NS).

**ASSISTANT:** {"stage": "generate", "target": "Human HER2 (ErbB2) extracellular domain IV (PDB: 1N8Z, epitope focusing on residues Thr309 and Lys311)", "scaffold_policy": "Trastuzumab VH scaffold (IGHV3-23/IGHJ4) with fixed CDR-H1, CDR-H2, and full light chain; de-novo generation restricted to CDR-H3 (Kabat residues 95-102)", "property_envelope": {"cdr_h3_length": "12-16 amino acids", "net_charge_pH_7_4": "[-1.0, 2.0]", "unpaired_cysteines": 0, "forbidden_motifs": ["N[^P][ST]", "NG", "NS"], "predicted_binding_affinity": "high (epitope-directed toward HER2 Thr309/Lys311)"}, "count": 10}

---

## [284] source=multitask_sft_big

**USER:** Generate 50 novel, diverse small molecules from scratch that display low cardiotoxicity liability and optimal lipophilicity for oral bioavailability. The compounds must have a calculated logP (cLogP) strictly between 1.5 and 2.8, and predicted hERG IC50 greater than 10 µM (or low hERG inhibition risk). Ensure molecular weight is within 300–450 Da, TPSA is between 50 and 110 Å², and structures are free of PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": "none", "property_envelope": {"clogP": {"min": 1.5, "max": 2.8}, "hERG_IC50_uM": {"min": 10.0}, "molecular_weight": {"min": 300, "max": 450}, "tpsa": {"min": 50, "max": 110}, "pains_free": true, "reactive_groups": false}, "count": 50}

---

## [285] source=multitask_sft_big

**USER:** Design 50 novel, drug-like kinase inhibitor scaffolds targeting the ATP-binding pocket of CDK2. The scaffolds must feature an adenine-mimetic hinge-binding motif (acting as donor-acceptor or donor-acceptor-donor) but remain structurally distinct from conventional purine, quinazoline, and pyrazolopyrimidine cores. Please filter for good physicochemical properties: MW between 350 and 480 Da, cLogP 2.0-4.0, TPSA between 60 and 100 Å², HBD ≤ 3, and no more than 6 rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "CDK2 ATP-binding site", "scaffold_policy": {"diversity": "high", "novelty": "de novo non-canonical cores", "required_features": ["hinge-binding motif"], "excluded_cores": ["purine", "quinazoline", "pyrazolopyrimidine"]}, "property_envelope": {"MW": [350, 480], "cLogP": [2.0, 4.0], "TPSA": [60, 100], "HBD": [1, 3], "RotB": [0, 6]}, "count": 50}

---

## [286] source=multitask_sft_big

**USER:** Please generate 50 novel, drug-like small molecules with a favorable safety profile regarding cardiotoxicity. Specifically, ensure high hERG safety (predicted hERG pIC50 < 5.0 / IC50 > 10 µM) combined with optimal lipophilicity (ClogP between 1.5 and 3.0). Keep molecular weight under 450 Da and maintain synthetic tractability (SAScore <= 4.0).

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"clogP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450}, "sa_score": {"max": 4.0}}, "count": 50}

---

## [287] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamer sequences targeting human VEGF-165 (UniProt P15692-4). The aptamers should be 35 to 45 nucleotides in length, exhibit strong predicted secondary structure stability with an MFE ΔG below -10.0 kcal/mol at 37°C, maintain a GC content between 40% and 60%, avoid homopolymer runs longer than 4 consecutive identical nucleotides, and have a predicted dissociation constant (Kd) under 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor 165 (VEGF-165, UniProt: P15692-4)", "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 35, "max": 45, "unit": "nt"}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "mfe_delta_g": {"max": -10.0, "unit": "kcal/mol", "temperature": "37C"}, "max_homopolymer_length": 4, "binding_affinity_kd": {"max": 50, "unit": "nM"}}, "count": 10}

---

## [288] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers from scratch targeting human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692-4). Sequences should be between 35 and 45 nucleotides in length, possess predicted binding affinities (Kd) below 50 nM, and maintain GC content between 40% and 60%. Filter out sequences with homopolymer runs longer than 4 nucleotides (especially poly-G tracts) and require a predicted folding minimum free energy (dG) below -8.0 kcal/mol.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt P15692-4)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "predicted_kd_nM": "< 50", "gc_content_pct": {"min": 40.0, "max": 60.0}, "max_homopolymer_length": 4, "mfe_folding_dG_kcal_per_mol": "< -8.0"}, "count": 5}

---

## [289] source=multitask_sft_big

**USER:** Please design 25 novel drug-like small molecules from scratch that prioritize cardiovascular safety and optimal physicochemical properties. The molecules must have a calculated logP between 1.5 and 2.8 and low predicted hERG liability with an estimated hERG IC50 greater than 10 µM. Additionally, restrict molecular weight to under 450 Da and filter out any PAINS substructures.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"clogP": {"min": 1.5, "max": 2.8}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450.0}, "pains_alerts": 0}, "count": 25}

---

## [290] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamers targeting human VEGF-165 (UniProt P15692) for anti-angiogenic therapeutic development. The sequences should be de novo single-stranded RNA between 35 and 50 nucleotides in length, with an expected binding affinity (Kd) below 20 nM against the heparin-binding domain of VEGF-165. Ensure sequences have a GC content between 40% and 60%, predict stable secondary structures (minimum free energy <= -15 kcal/mol at 37 °C), avoid homopolymer runs greater than 4 nt, and be compatible with standard 2'-fluoro pyrimidine chemical stabilization.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (Vascular Endothelial Growth Factor A, UniProt P15692)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 35, "max": 50}, "affinity_kd_nm": {"max": 20.0}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_kcal_mol": {"max": -15.0}, "max_homopolymer_length": 4, "target_epitope": "Heparin-binding domain (exons 6a/7)", "monomer_alphabet": ["A", "C", "G", "U"]}, "count": 10}

---

## [291] source=multitask_sft_big

**USER:** Please design 8 novel RNA aptamers targeting human VEGF-165 with high affinity (predicted Kd < 20 nM). The aptamers should be 30 to 45 nucleotides in length, have a GC content between 40% and 60%, and show stable secondary folding with an MFE <= -12 kcal/mol at 37°C.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "de_novo", "property_envelope": {"length_nt": [30, 45], "predicted_Kd_nM": "<= 20", "gc_content_percent": [40, 60], "mfe_kcal_per_mol": "<= -12"}, "count": 8}

---

## [292] source=multitask_sft_big

**USER:** Design 20 novel PROTAC linkers connecting our VHL ligand (anchored via the terminal hydroxyl/phenol) and a CDK4/6 warhead (anchored via the solvent-exposed piperazine NH). Linkers should span between 9 and 14 contiguous atoms in length, incorporate semi-rigid moieties such as piperazine, pyrrolidine, or 1,4-disubstituted rings to restrict conformational flexibility, and avoid labile motifs like esters or hydrazones. Maintain linker-specific MW < 280 Da, linker cLogP between 0.5 and 2.5, and topological polar surface area (TPSA) between 40 and 90 Å².

**ASSISTANT:** {"stage": "generate", "target": "CDK4/6 - VHL ternary complex", "scaffold_policy": "Bifunctional linker joining fixed VHL ligand (phenol oxygen attachment) and CDK4/6 warhead (piperazine N attachment); incorporates rigidifying saturated or heteroaromatic rings; exclude labile functionalities (esters, hydrazones)", "property_envelope": {"linker_chain_length_atoms": "9 - 14", "linker_MW": "< 280", "linker_cLogP": "0.5 - 2.5", "linker_TPSA": "40 - 90"}, "count": 20}

---

## [293] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptide candidates targeting the Kelch domain of human Keap1 to disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should be head-to-tail or thioether-cyclized peptides spanning 7 to 11 amino acid residues, incorporating standard canonical residues with a maximum of 2 non-canonical amino acids (such as N-methylated residues or D-amino acids) to improve proteolytic resistance. Filter for designs with predicted binding affinity Kd < 50 nM, LogP between -3.0 and 1.5 for favorable aqueous solubility, and no reactive or aggregator motifs.

**ASSISTANT:** {"stage": "generate", "target": "Human Keap1 Kelch domain (Nrf2 PPI site)", "scaffold_policy": "Macrocyclic peptide via head-to-tail or thioether linkage, length 7-11 residues, at most 2 non-canonical amino acids", "property_envelope": {"predicted_Kd_nM": "< 50", "logP": [-3.0, 1.5], "peptide_length": [7, 11], "max_unnatural_residues": 2, "exclude_reactive_and_aggregator_motifs": true}, "count": 20}

---

## [294] source=multitask_sft_big

**USER:** Please generate 15 de-novo CDR-H3 loop sequences for a therapeutic antibody scaffold targeting the HER2 extracellular domain (PDB: 1N8Z). The designed loops should have a length between 10 and 16 residues, grafted onto the trastuzumab heavy chain framework while maintaining canonical anchor residues (C92 and W103). The designs should exhibit high predicted interface binding confidence (ipTM >= 0.85), favorable net charge at pH 7.4 (-2 to +2), hydrophobic patch area < 800 Å², and be completely devoid of common sequence liabilities such as N-glycosylation motifs (N-X-[S/T]) and Asp isomerization motifs (DG, DS).

**ASSISTANT:** {"stage": "generate", "target": "HER2 extracellular domain (PDB: 1N8Z)", "scaffold_policy": "Trastuzumab heavy chain variable domain framework with fixed flanking anchors C92/W103; CDR-H3 replaced de-novo", "property_envelope": {"cdr_h3_length": [10, 16], "ipTM": ">= 0.85", "net_charge_pH_7_4": [-2, 2], "hydrophobic_patch_area_A2": "< 800", "sequence_liabilities": {"exclude_motifs": ["N[^P][ST]", "DG", "DS"]}}, "count": 15}

---

## [295] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human PCSK9 (UniProt Q8NBP7) with high binding affinity (estimated Kd < 50 nM). The aptamers should be completely de novo (no fixed flanking primer scaffolds), with sequence lengths strictly between 35 and 45 nucleotides, GC content between 40% and 60%, and high secondary structure stability (minimum free energy MFE <= -12.0 kcal/mol).

**ASSISTANT:** {"stage": "generate", "target": "Human PCSK9 (UniProt Q8NBP7)", "scaffold_policy": "none", "property_envelope": {"length": {"min": 35, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "affinity_kd_nm": {"max": 50}, "mfe_kcal_mol": {"max": -12.0}}, "count": 5}

---

## [296] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops targeting the PD-1 binding interface of human PD-L1 (PDB: 4Z18). Use the human IGHV3-23 / IGHJ4 framework with CDR-H1 and CDR-H2 kept as germline. CDR-H3 lengths should be constrained between 11 and 16 residues. Generated candidates must have an AF2-multimer/ESMFold ipTM >= 0.75, CDR-H3 pLDDT >= 80, net charge between -1 and +2 at pH 7.4, and no more than 3 aromatic residues to minimize developability risks.

**ASSISTANT:** {"stage": "generate", "target": "Human PD-L1 (receptor-binding surface for PD-1, PDB: 4Z18)", "scaffold_policy": "Human germline IGHV3-23 / IGHJ4 framework with native CDR-H1 and CDR-H2 held fixed; de-novo loop generation restricted strictly to CDR-H3 (Chothia/Kabat definition)", "property_envelope": {"cdr_h3_length_range": [11, 16], "min_iptm": 0.75, "min_cdr_h3_plddt": 80.0, "net_charge_range": [-1.0, 2.0], "max_aromatic_count": 3}, "count": 50}

---

## [297] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptide inhibitors targeting the human Keap1 Kelch domain to disrupt its interaction with Nrf2. Peptides should be 8 to 13 amino acids in length, cyclized via head-to-tail amide bond or a stable thioether/disulfide crosslink. Incorporate natural amino acids with option for up to two N-methylated or D-amino acid substitutions to enhance proteolytic stability. Target a predicted binding affinity (Kd) below 100 nM, net charge between -2 and +1 at pH 7.4, and peptide molecular weight under 1600 Da.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Nrf2 binding site)", "scaffold_policy": "Macrocyclic peptide, length 8-13 residues, cyclization via head-to-tail backbone or sidechain thioether/disulfide staple, up to 2 non-canonical/D-amino acids permitted", "property_envelope": {"predicted_affinity_Kd": "< 100 nM", "molecular_weight": "< 1600 Da", "net_charge_at_pH_7_4": "[-2, +1]", "proteolytic_stability": "high"}, "count": 20}

---

## [298] source=multitask_sft_big

**USER:** Design 15 de novo macrocyclic peptide binders targeting the p53-binding cleft of human MDM2 to inhibit the MDM2-p53 protein-protein interaction. Peptides should be 7 to 11 amino acids in length, cyclized via either head-to-tail backbone cyclization or an intramolecular thioether staple. Retain critical pharmacophoric features mimicking the p53 hot-spot triad (Phe19, Trp23, Leu26). Filter for molecular weight between 800 and 1400 Da, polar surface area (tPSA) under 350 Å², low conformational strain, and predicted binding affinity with a docking score < -9.5 kcal/mol.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (p53-binding pocket, PPI interface)", "scaffold_policy": "Macrocyclic peptides of 7-11 residues with head-to-tail amide or thioether cyclization; must incorporate structural mimetics of the Phe-Trp-Leu binding triad", "property_envelope": {"peptide_length": "7-11 residues", "molecular_weight": "800 - 1400 Da", "tPSA": "< 350 \u00c5\u00b2", "docking_score": "< -9.5 kcal/mol"}, "count": 15}

---

## [299] source=multitask_sft_big

**USER:** Design 50 de-novo linkers to generate PROTAC degraders connecting our BTK warhead (ibrutinib derivative, exit vector at piperidine N) and a CRBN E3 ligase ligand (pomalidomide 4-amino derivative). The linkers should span an end-to-end chain length of 8 to 14 heavy atoms, balancing flexibility with rigidifying motifs (e.g., piperazine, piperidine, azetidine, or bicyclic diamines) to mitigate entropy penalty. Overall bifunctional property constraints: MW < 950 Da, cLogP between 2.5 and 5.0, TPSA < 210 Å², and rotatable bonds in the linker ≤ 10, favoring commercially feasible coupling handles (e.g., alkylation, amide bond formation).

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN ternary complex", "scaffold_policy": "fragment_linking (fix BTK warhead and CRBN pomalidomide core; generate bridging linkers)", "property_envelope": {"linker_heavy_atom_count": "8-14", "linker_rotatable_bonds": "<=10", "protac_mw": "<950", "protac_clogP": "2.5-5.0", "protac_tpsa": "<210"}, "count": 50}

---

## [300] source=multitask_sft_big

**USER:** Generate 50 de-novo macrocyclic peptide binders targeting the p53-binding hydrophobic cleft of human MDM2 (PDB ID: 1YCR). Candidates should be 8–12 amino acids in length with a backbone lactam cyclization (head-to-tail) or sidechain-to-tail staple, functionally presenting the canonical Phe-Trp-Leu interaction triad. Restrict candidates to a molecular weight of 900–1400 Da, cLogP between 0.5 and 4.0, topological polar surface area (tPSA) ≤ 320 Å², and no more than 6 rotatable bonds outside the macrocyclic core.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-interaction cleft, PDB 1YCR)", "scaffold_policy": "Macrocyclic peptide (8\u201312 residues, head-to-tail lactam or sidechain-to-tail cyclized, constrained to display the Phe-Trp-Leu pharmacophore motif)", "property_envelope": {"molecular_weight": "900-1400 Da", "clogp": "0.5 to 4.0", "tpsa": "<= 320 A^2", "exocyclic_rotatable_bonds": "<= 6", "peptide_length": "8-12 residues"}, "count": 50}

---

## [301] source=multitask_sft_big

**USER:** Design 20 novel bifunctional PROTAC linkers connecting a VHL ligand (VH032 terminal amine) to a BRD4-targeting warhead (JQ1 carboxylic acid derivative). The linkers should explore diverse chemotypes beyond standard flexible aliphatic/PEG chains, incorporating rigid or semi-rigid motifs such as piperazines, spirocycles, or alkynes to reduce conformational entropy. Linker atom count must range from 8 to 14 linear atoms. Ensure drug-like physical properties suitable for cellular permeability: overall conjugate calculated logP < 5.5, linker-only TPSA between 20 and 70 Å², linker rotatable bonds ≤ 8, and synthetic accessibility score (SAS) ≤ 4.5.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC", "scaffold_policy": "keep fixed warhead (JQ1 derivative) and E3 recruiter (VH032 derivative), generate novel connecting linker scaffold", "property_envelope": {"linker_chain_length_atoms": [8, 14], "linker_tpsa_angstrom2": [20.0, 70.0], "linker_rotatable_bonds": "<=8", "linker_sa_score": "<=4.5", "conjugate_clogp": "<5.5"}, "count": 20}

---

## [302] source=multitask_sft_big

**USER:** Design 8 de novo RNA aptamer sequences targeting the human vascular endothelial growth factor 165 (VEGF-165, UniProt: P15692). The aptamers should have lengths between 40 and 60 nucleotides, predicted binding affinity (Kd) below 15 nM, secondary structure minimum free energy (MFE) lower than -18 kcal/mol, and a GC content between 40% and 65%. Avoid continuous G-quadruplex runs greater than 4 guanines unless structured within a stable stem-loop.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "free de novo generation without fixed primer-binding arms or scaffolds", "property_envelope": {"length_nt": {"min": 40, "max": 60}, "predicted_Kd_nM": "< 15", "MFE_kcal_mol": "< -18", "gc_content_percent": {"min": 40, "max": 65}, "max_homopolymer_run_G": 4}, "count": 8}

---

## [303] source=multitask_sft_big

**USER:** Design 20 novel, distinct small-molecule core scaffolds for reversible kinase inhibition targeting the Bruton's tyrosine kinase (BTK) hinge region. The scaffolds must contain a viable hinge-binding motif (at least one hydrogen bond donor and one acceptor). Avoid standard quinazoline, purine, and pyrrolopyrimidine cores to ensure novel IP. Keep the molecular weight between 250 and 400 Da, clogP between 1.5 and 3.5, TPSA between 60 and 90 Å², rotatable bonds <= 4, and filter out PAINS and reactive functionalities.

**ASSISTANT:** {"stage": "generate", "target": "Bruton's tyrosine kinase (BTK) ATP-binding site", "scaffold_policy": {"action": "novel_core", "forbidden_classes": ["quinazoline", "purine", "pyrrolopyrimidine"], "required_motifs": ["hinge-binding donor-acceptor feature"], "mechanism": "reversible"}, "property_envelope": {"molecular_weight": {"min": 250.0, "max": 400.0}, "clogp": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 60.0, "max": 90.0}, "rotatable_bonds": {"max": 4}, "structural_filters": ["PAINS", "reactive_functional_groups"]}, "count": 20}

---

## [304] source=multitask_sft_big

**USER:** Design 15 de novo RNA aptamers targeting the human vascular endothelial growth factor 165 (VEGF-165, UniProt: P15692). Sequences should be between 30 and 45 nucleotides in length, feature a GC content between 40% and 60%, possess a secondary structure minimum free energy (MFE) below -10.0 kcal/mol, and have high predicted binding affinity (Kd < 50 nM). Please avoid homopolymer runs longer than 4 nucleotides.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human vascular endothelial growth factor A (VEGF-165)", "uniprot_id": "P15692", "type": "protein"}, "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "mfe_secondary_structure_kcal_mol": {"max": -10.0}, "predicted_kd_nM": {"max": 50.0}, "max_homopolymer_run": 4}, "count": 15}

---

## [305] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide binders targeting the p53 interaction cleft of MDM2 (UniProt: Q00987). The peptides must be head-to-tail cyclized, composed of 8 to 12 residues, and permit non-canonical or N-methylated residues to enhance proteolytic stability. Aim for predicted binding affinity Kd < 50 nM, molecular weight between 800 and 1500 Da, LogP between -1.0 and 3.5, and topological polar surface area (tPSA) under 400 Å².

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 interaction cleft, UniProt: Q00987)", "scaffold_policy": "macrocyclic peptide (head-to-tail cyclization, 8-12 amino acid residues)", "property_envelope": {"length": [8, 12], "molecular_weight": [800, 1500], "logP": [-1.0, 3.5], "tPSA": {"max": 400}, "affinity_kd_nm": {"max": 50}}, "count": 20}

---

## [306] source=multitask_sft_big

**USER:** Design 50 novel, drug-like linkers to conjugate our AR (androgen receptor) antagonist warhead to a VHL E3 ligase recruiter (VH032 derivative). The attachment vectors are fixed at the designated phenolic oxygen on the AR ligand and the terminal amide methyl group on the VHL ligand. Please avoid repetitive straight PEG or aliphatic chains; instead, incorporate semi-rigid motifs such as piperazines, spirocycles, or bicyclic rings to restrict conformational entropy while maintaining linker lengths between 9 to 15 atoms. The overall PROTAC assemblies must maintain cLogP between 2.5 and 5.5, total TPSA under 220 Å², and total molecular weight under 1050 Da.

**ASSISTANT:** {"stage": "generate", "target": "AR-VHL ternary complex linker design", "scaffold_policy": "Fix AR antagonist and VH032 recruiter attachment vectors; generate de-novo linkers incorporating semi-rigid or spirocyclic motifs while disallowing poly-PEG and unbranched alkyl chains", "property_envelope": {"linker_atom_length": "9-15 atoms", "protac_mw": "<= 1050 Da", "protac_clogp": "2.5-5.5", "protac_tpsa": "<= 220 \u00c5\u00b2"}, "count": 50}

---

## [307] source=multitask_sft_big

**USER:** Please design 20 de-novo, drug-like central scaffolds for targeting the kinase ATP-binding pocket of EGFR T790M/L858R. The scaffolds must strictly avoid common quinazoline, pyrimidine, and pyrrolopyrimidine hinge-binding cores to establish novel intellectual property. Ensure all generated cores fit a standard small-molecule oral profile: MW between 300 and 450 Da, cLogP 2.0–3.8, TPSA 60–90 Å², HBD 1–2, HBA 4–7, and no more than 4 rotatable bonds, with clear vectors for hinge-binding and solvent-exposed decoration.

**ASSISTANT:** {"stage": "generate", "target": "EGFR kinase (T790M/L858R)", "scaffold_policy": {"action": "novel_core_generation", "excluded_substructures": ["c1nc2ccccc2nc1", "c1cncnc1", "c1cc2c(n1)ccnc2"], "description": "Novel hinge-binding kinase inhibitor scaffolds excluding quinazoline, pyrimidine, and pyrrolopyrimidine motifs with defined synthetic exit vectors"}, "property_envelope": {"molecular_weight": {"min": 300.0, "max": 450.0}, "clogp": {"min": 2.0, "max": 3.8}, "tpsa": {"min": 60.0, "max": 90.0}, "hbd": {"min": 1, "max": 2}, "hba": {"min": 4, "max": 7}, "rotatable_bonds": {"max": 4}}, "count": 20}

---

## [308] source=multitask_sft_big

**USER:** Generate 25 novel drug-like small molecules with balanced lipophilicity and minimal cardiac liability. The designs should have a LogP between 1.5 and 3.0, hERG IC50 > 30 µM (or pIC50 < 4.5), molecular weight under 450 Da, and TPSA between 60 and 120 Å² without reusing known commercial kinase inhibitor cores.

**ASSISTANT:** {"stage": "generate", "target": "hERG (cardiac safety / anti-target avoidance)", "scaffold_policy": "novel / unconstrained (avoid known commercial kinase cores)", "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_IC50_uM": {"min": 30.0}, "MW": {"max": 450.0}, "TPSA": {"min": 60.0, "max": 120.0}}, "count": 25}

---

## [309] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamers targeting human VEGF-165 with high affinity (predicted Kd < 50 nM). The aptamers should be 30-45 nucleotides in length, have a GC content between 45% and 65%, and display a stable predicted secondary structure with folding free energy (ΔG) <= -10.0 kcal/mol at 37°C while avoiding homopolymer tracts longer than 4 nt.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "de novo RNA aptamer, length 30-45 nt, no homopolymers > 4 nt", "property_envelope": {"predicted_kd": "< 50 nM", "length": [30, 45], "gc_content": [0.45, 0.65], "folding_delta_g": "<= -10.0 kcal/mol"}, "count": 10}

---

## [310] source=multitask_sft_big

**USER:** Design 10 novel small molecules with low cardiac liability and balanced lipophilicity. Specifically, molecules must show minimal hERG inhibition (predicted hERG IC50 > 10 µM), a clogP between 1.5 and 3.0, MW under 450 Da, and TPSA between 60 and 110 Å². No specific core scaffold is required.

**ASSISTANT:** {"stage": "generate", "target": "hERG", "scaffold_policy": "none", "property_envelope": {"clogP": [1.5, 3.0], "hERG_IC50_uM": "> 10", "MW": "< 450", "TPSA": [60, 110]}, "count": 10}

---

## [311] source=multitask_sft_big

**USER:** Design 50 novel, diverse small-molecule scaffolds targeting the ATP-binding pocket of LRRK2 kinase. The cores should incorporate novel hinge-binding motifs distinct from standard aminopyrimidine and indazole classes. Ensure high drug-likeness and CNS permeability potential: MW 320-450 Da, cLogP 2.0-3.8, TPSA 50-85 Å², HBD <= 2, RotB <= 5, with no PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 kinase", "scaffold_policy": "novel hinge-binding scaffolds structurally distinct from aminopyrimidines and indazoles", "property_envelope": {"molecular_weight": {"min": 320, "max": 450}, "clogp": {"min": 2.0, "max": 3.8}, "tpsa": {"min": 50, "max": 85}, "hbd": {"max": 2}, "rotatable_bonds": {"max": 5}, "structural_filters": ["PAINS", "reactive_groups"]}, "count": 50}

---

## [312] source=multitask_sft_big

**USER:** Please generate 50 de-novo CDR-H3 loop candidates targeting human HER2 (PDB: 1N8Z, Chain A) using the trastuzumab variable fragment framework (Chains H and L). Keep all framework regions and CDRs H1, H2, L1, L2, and L3 fixed, designing only CDR-H3 (Kabat positions H95-H102). The CDR-H3 length should be restricted to 10-16 amino acids. Filter for predicted binding affinity pKd >= 8.5, OAS-based humanness score >= 0.80, zero unpaired cysteines, and no N-linked glycosylation sequons (N-X-[S/T], X!=P).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human HER2", "pdb_id": "1N8Z", "chain": "A"}, "scaffold_policy": {"scaffold": "Trastuzumab Fv (PDB 1N8Z, Chains H and L)", "fixed_regions": ["Framework 1-4", "CDR-H1", "CDR-H2", "CDR-L1", "CDR-L2", "CDR-L3"], "design_region": "CDR-H3 (Kabat H95-H102)"}, "property_envelope": {"cdr_h3_length": {"min": 10, "max": 16}, "predicted_pKd": {"min": 8.5}, "humanness_score": {"min": 0.8}, "unpaired_cysteines": 0, "n_glycosylation_motifs": 0}, "count": 50}

---

## [313] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers targeting human VEGF-165 with high binding affinity (target Kd < 20 nM). The sequences should be 30 to 45 nucleotides long, with a GC content between 40% and 60%, a secondary structure minimum free energy (dG) <= -10 kcal/mol, and no homopolymer runs longer than 4 nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "none", "property_envelope": {"length": {"min": 30, "max": 45}, "affinity_kd_nM": {"max": 20.0}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_dG_kcal_mol": {"max": -10.0}, "max_homopolymer_length": 4}, "count": 5}

---

## [314] source=multitask_sft_big

**USER:** Generate 30 novel macrocyclic peptides targeting the MDM2-p53 protein-protein interaction interface. The sequences should be 8 to 12 residues in length, cyclized via head-to-tail amide or side-chain lactam/thioether crosslinks. Target a molecular weight between 850 and 1400 Da, cLogP between 0.5 and 4.5, polar surface area under 350 Å², and prioritize candidates with predicted binding affinity Kd < 50 nM and high serum stability.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 interaction groove)", "scaffold_policy": {"monomer_type": "peptide", "length_range": [8, 12], "topology": "macrocycle", "cyclization_types": ["head-to-tail", "side-chain-to-side-chain lactam", "thioether"]}, "property_envelope": {"molecular_weight": {"min": 850, "max": 1400}, "clogp": {"min": 0.5, "max": 4.5}, "tpsa_max": 350.0, "predicted_kd_nm_max": 50.0, "serum_stability": "high"}, "count": 30}

---

## [315] source=multitask_sft_big

**USER:** Design 15 de-novo CDR-H3 loop sequences grafted onto a human VH3-23/JH4 scaffold framework targeting the Receptor Binding Domain (RBD) of the SARS-CoV-2 Omicron BA.5 spike protein (PDB: 7XWA). The CDR-H3 loops should have lengths between 13 and 17 amino acids, exclude liabilities such as N-glycosylation motifs (N-X-[S/T]) and DP/DG deamidation/cleavage hotspots, maintain an overall loop net charge between -1 and +2 at pH 7.4, and keep hydrophobic residue content under 40%.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Omicron BA.5 Spike RBD", "pdb_id": "7XWA", "epitope": "ACE2-binding interface"}, "scaffold_policy": {"framework": "Human IGHV3-23/IGHJ4", "redesign_region": "CDR-H3 (Chothia H95-H102 / IMGT 105-117)", "framework_status": "fixed"}, "property_envelope": {"length_range": [13, 17], "net_charge_range": [-1, 2], "max_hydrophobic_fraction": 0.4, "forbidden_motifs": ["N[^P][ST]", "DG", "DP"]}, "count": 15}

---

## [316] source=multitask_sft_big

**USER:** Design 30 novel, semi-rigid PROTAC linkers to connect our BTK-targeting aminopyrazole warhead to a pomalidomide-based CRBN ligand. The linker should span an optimal distance of 11 to 15 Å between the defined attachment vectors (aryl-C on the warhead and C4-amine on pomalidomide). Avoid long, completely flexible unbranched alkyl/PEG chains; incorporate conformationally constrained motifs such as spirocyclic piperidines, azetidines, or disubstituted cycloalkyl rings to favor ternary complex stability. Keep total PROTAC MW under 900 Da, cLogP between 2.5 and 5.0, TPSA below 170 Å², and rotatable bonds under 10.

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN ternary complex degradation", "scaffold_policy": "keep aminopyrazole warhead and pomalidomide E3 ligand fixed; generate novel bridging linker between specified exit vectors", "property_envelope": {"linker_atom_length": "8-14 atoms", "linker_end_to_end_distance_angstrom": "11.0-15.0", "full_protac_mw_max": 900, "full_protac_clogp": [2.5, 5.0], "full_protac_tpsa_max": 170, "rotatable_bonds_max": 10, "structural_motifs": ["spirocycles", "azetidine", "piperidine", "alicyclic rings"], "unwanted_features": ["polyethylene glycol (>2 repeat units)", "unbranched alkyl chains (>5 carbons)", "esters", "hydrazine"]}, "count": 30}

---

## [317] source=multitask_sft_big

**USER:** Generate 50 novel, diverse small-molecule candidates designed de novo with balanced lipophilicity and minimal cardiac toxicity risk. Compounds must exhibit a calculated LogP between 1.5 and 3.0, and demonstrate high hERG safety with a predicted hERG pIC50 < 5.0 (IC50 > 10 µM). Please maintain drug-likeness with MW < 450 Da and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 50}

---

## [318] source=multitask_sft_big

**USER:** Design 5 de-novo RNA aptamer sequences targeting human VEGF-165 (UniProt: P15692) for therapeutic anti-angiogenic applications. The aptamers should be 35 to 45 nucleotides in length, possess a predicted binding affinity (Kd) below 50 nM, have a minimum free energy (MFE) secondary structure stability between -10.0 and -22.0 kcal/mol, maintain a GC content between 40% and 65%, and avoid homopolymeric runs of 4 or more consecutive identical bases (especially poly-U stretches) to ensure chemical synthesis yield.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor A (VEGF-165, UniProt: P15692)", "scaffold_policy": "de_novo", "property_envelope": {"length": [35, 45], "predicted_kd_nM": "< 50", "mfe_kcal_mol": [-22.0, -10.0], "gc_content_pct": [40, 65], "max_homopolymer_run": 3}, "count": 5}

---

## [319] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamer sequences targeting the receptor-binding domain of human VEGF-165. The sequences should be between 35 and 45 nucleotides in length, have a GC content between 40% and 60%, exhibit a predicted secondary structure minimum free energy (MFE) below -12 kcal/mol, and target an estimated binding affinity (Kd) under 25 nM without requiring fixed terminal primer scaffolds.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (receptor-binding domain)", "scaffold_policy": "none", "property_envelope": {"length": {"min": 35, "max": 45, "unit": "nt"}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe": {"max": -12.0, "unit": "kcal/mol"}, "predicted_kd": {"max": 25.0, "unit": "nM"}}, "count": 8}

---

## [320] source=multitask_sft_big

**USER:** Design 40 de novo macrocyclic peptide binders targeting the human Keap1 Kelch domain to disrupt the Keap1-Nrf2 protein-protein interaction interface. Candidates should consist of 8 to 12 amino acids, constrained via head-to-tail or thioether cyclization, with predicted Kd < 100 nM. Maintain molecular weight between 800 and 1500 Da, cLogP between -1.5 and 2.5, and topological polar surface area (tPSA) under 400 Å².

**ASSISTANT:** {"stage": "generate", "target": "human Keap1 Kelch domain (Keap1-Nrf2 PPI interface)", "scaffold_policy": {"type": "macrocyclic peptide", "sequence_length": [8, 12], "cyclization_chemistry": ["head-to-tail", "thioether"]}, "property_envelope": {"predicted_Kd_nM": "< 100", "molecular_weight": [800, 1500], "cLogP": [-1.5, 2.5], "tPSA_A2": "<= 400"}, "count": 40}

---

## [321] source=multitask_sft_big

**USER:** Design 50 de-novo linkers to bridge a BRD4-binding JQ1 derivative to a VHL E3 ligase binder (VH032 derivative). The linkers must span between 8 and 14 heavy atoms in length, contain drug-like motifs (PEG, alkyl, or rigidifying piperazine/piperidine elements), and avoid metabolically unstable groups like esters or hydrazones. Ensure the intact PROTACs retain acceptable physicochemical properties: linker MW < 250 Da, linker cLogP between 0.5 and 3.0, and linker TPSA < 60 Å².

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC", "scaffold_policy": "linker_design_between_defined_vectors", "property_envelope": {"linker_heavy_atom_count": {"min": 8, "max": 14}, "linker_mw": {"max": 250}, "linker_clogp": {"min": 0.5, "max": 3.0}, "linker_tpsa": {"max": 60}, "excluded_substructures": ["ester", "hydrazone"]}, "count": 50}

---

## [322] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamer sequences targeting human VEGF-165 with high binding affinity (predicted KD < 25 nM). The aptamers should be 40 to 50 nucleotides in length, have a GC content between 45% and 60%, and fold into stable stem-loop architectures with a minimum free energy (MFE) <= -14 kcal/mol. Avoid long homopolymer runs (no more than 4 consecutive Gs) to reduce G-quadruplex heterogeneity while maintaining serum stability.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692-4)", "scaffold_policy": "de novo design; single-stranded RNA; length 40-50 nt; no fixed primer sequences", "property_envelope": {"predicted_KD_nM": "<= 25", "length_nt": [40, 50], "gc_content_pct": [45, 60], "minimum_free_energy_kcal_per_mol": "<= -14.0", "max_homopolymer_g": 4, "secondary_structure": "stable stem-loop motif"}, "count": 10}

---

## [323] source=multitask_sft_big

**USER:** Design 25 de novo macrocyclic peptide binders targeting the Kelch domain of Keap1 (PDB: 2FLU) to disrupt the Keap1-Nrf2 protein-protein interaction. The cyclic peptides should contain 6 to 10 amino acid residues utilizing either head-to-tail or sidechain-to-sidechain lactam cyclization, and incorporate a DxETGE-mimicking binding motif. Maintain molecular weight between 700 and 1300 Da, clogP between -1.0 and 3.0, topological polar surface area (TPSA) < 320 Å², and predicted binding affinity Kd < 50 nM with favorable cell permeability profiles.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Keap1-Nrf2 interaction, PDB: 2FLU)", "scaffold_policy": "Macrocyclic peptides (6-10 residues, head-to-tail or sidechain-to-sidechain lactam cyclization containing DxETGE-derived or isosteric PPI motifs)", "property_envelope": {"molecular_weight": "700 - 1300 Da", "clogP": "-1.0 to 3.0", "tpsa": "< 320 \u00c5\u00b2", "binding_affinity_kd": "< 50 nM", "cell_permeability": "enhanced / cell-permeable"}, "count": 25}

---

## [324] source=multitask_sft_big

**USER:** Generate 25 novel drug-like small molecules designed de novo with optimized logP and minimal hERG liability to avoid cardiotoxicity. Please ensure compounds have a logP between 1.5 and 3.0, hERG IC50 > 10 µM, molecular weight under 450 Da, and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"logP": [1.5, 3.0], "hERG_IC50_uM": "> 10", "MW": "<= 450", "TPSA": [60, 120]}, "count": 25}

---

## [325] source=multitask_sft_big

**USER:** We are designing novel CDR-H3 loops targeting the extracellular domain IV of human HER2 using the Trastuzumab VH/VL framework as a scaffold (reference structure PDB: 1N8Z). Please generate 20 de-novo CDR-H3 loop sequences (lengths 12 to 16 residues) grafted into the Trastuzumab heavy chain. The designed loops should have high predicted shape complementarity and binding affinity (predicted Kd < 10 nM / pKd > 8.0), avoid developability liabilities such as N-glycosylation (N-X-S/T) and unpaired cysteines, maintain a net charge between -1 and +2 at pH 7.4, and demonstrate low spatial aggregation propensity (SAP score < 5.0).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human Epidermal Growth Factor Receptor 2 (HER2)", "domain": "Extracellular Domain IV", "reference_pdb": "1N8Z"}, "scaffold_policy": {"framework": "Trastuzumab (anti-HER2 IgG1)", "fixed_regions": ["VH framework 1-3", "CDR-H1", "CDR-H2", "framework 4", "VL full"], "design_region": "CDR-H3", "loop_length_range": [12, 16]}, "property_envelope": {"predicted_pKd": {"min": 8.0}, "spatial_aggregation_propensity": {"max": 5.0}, "net_charge_pH_7_4": {"min": -1.0, "max": 2.0}, "forbidden_motifs": ["N[^P][ST]", "C"]}, "count": 20}

---

## [326] source=multitask_sft_big

**USER:** Design 25 novel, patentable small-molecule scaffolds targeting the ATP-binding pocket of EGFR (specifically addressing the T790M/C797S resistance mutation). The scaffolds must diverge from standard 4-anilinoquinazoline and 2,4-diaminopyrimidine cores. Ensure drug-like properties suitable for oral bioavailability: molecular weight between 320 and 450 Da, cLogP between 1.5 and 3.8, TPSA between 65 and 110 Å², HBD ≤ 2, HBA ≤ 7, and no more than 5 rotatable bonds. Each core must feature an identifiable hinge-binding donor-acceptor motif and at least two distinct exit vectors for optimization.

**ASSISTANT:** {"stage": "generate", "target": "EGFR (T790M/C797S ATP-binding pocket)", "scaffold_policy": "De novo novel cores; strictly exclude 4-anilinoquinazoline and 2,4-diaminopyrimidine chemotypes; require clear hinge-binding motifs and dual exit vectors", "property_envelope": {"MW": [320, 450], "cLogP": [1.5, 3.8], "TPSA": [65, 110], "HBD": "<= 2", "HBA": "<= 7", "rotatable_bonds": "<= 5"}, "count": 25}

---

## [327] source=multitask_sft_big

**USER:** Design 25 novel small molecules from scratch with favorable lipophilicity and low cardiotoxicity risk. Compounds should have a calculated logP between 1.5 and 3.0, molecular weight between 300 and 450 Da, and demonstrate minimal hERG inhibition (predicted hERG IC50 > 10 µM or pIC50 < 5.0).

**ASSISTANT:** {"stage": "generate", "target": "hERG", "scaffold_policy": "de novo", "property_envelope": {"logP": [1.5, 3.0], "MW": [300, 450], "hERG_pIC50": "< 5.0", "hERG_IC50_uM": "> 10"}, "count": 25}

---

## [328] source=multitask_sft_big

**USER:** Design 50 novel de-novo small-molecule scaffolds as Type-I kinase inhibitors targeting the ATP-binding pocket of EGFR (T790M/C797S mutant). The cores must be chemically novel to establish fresh IP, specifically avoiding canonical quinazoline, pyrazolopyrimidine, and indolin-2-one cores, while retaining a 1- or 2-point hinge-binding motif. Ensure standard drug-like properties: MW between 380 and 480 Da, LogP 2.0 to 4.0, TPSA 60-100 Å², HBD ≤ 3, RotB ≤ 7, and filter out PAINS and reactive functionalities.

**ASSISTANT:** {"stage": "generate", "target": {"protein": "EGFR", "mutation": "T790M/C797S", "pocket": "ATP-binding site (Type-I)"}, "scaffold_policy": {"type": "novel", "exclude_scaffolds": ["quinazoline", "pyrazolopyrimidine", "indolin-2-one"], "pharmacophore_feature": "hinge-binding motif (1-2 H-bonds)"}, "property_envelope": {"MW": [380, 480], "LogP": [2.0, 4.0], "TPSA": [60, 100], "HBD": [0, 3], "RotB": [0, 7], "filter_pains": true, "filter_reactive": true}, "count": 50}

---

## [329] source=multitask_sft_big

**USER:** Generate 10 novel small molecules targeting human Nav1.7 with reduced cardiotoxic risk. Maintain a logP between 1.5 and 3.0, ensure predicted hERG pIC50 < 5.0 (IC50 > 10 µM), keep molecular weight below 450 Da, and TPSA between 60 and 110 Å² with no fixed scaffold constraints.

**ASSISTANT:** {"stage": "generate", "target": "Nav1.7", "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 110}}, "count": 10}

---

## [330] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide candidates targeting the Kelch domain of Keap1 (PDB: 2FLU) to disrupt the Keap1-Nrf2 protein-protein interaction. Peptides must contain 7 to 12 residues cyclized via head-to-tail backbone cyclization or a disulfide bridge, utilizing natural amino acids with optional standard N-methylation for metabolic stability. Target molecular weight should be 800-1400 Da, cLogP between -1.0 and 3.0, TPSA <= 450 Å², and predicted binding affinity Ki < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human Keap1 Kelch domain (disrupting Keap1-Nrf2 PPI, PDB: 2FLU)", "scaffold_policy": "Macrocyclic peptide (7-12 amino acid residues, head-to-tail or disulfide cyclization, natural amino acids with optional N-methylation)", "property_envelope": {"molecular_weight": "800 - 1400 Da", "clogp": "-1.0 to 3.0", "tpsa": "<= 450 \u00c5\u00b2", "predicted_affinity_ki": "< 50 nM"}, "count": 20}

---

## [331] source=multitask_sft_big

**USER:** Generate 30 novel de-novo macrocyclic peptides targeting the Kelch domain of human Keap1 to inhibit the Keap1-Nrf2 protein-protein interaction. The peptides should be 6 to 12 amino acids in length, macrocyclized via head-to-tail backbone amide or sidechain disulfide/thioether bridges. Incorporate up to 2 non-canonical residues (such as D-amino acids or N-methylated residues) to enhance proteolytic stability. Filter for candidates with predicted binding affinity Kd < 1 µM, molecular weight between 800 and 1500 Da, cLogP between -1.0 and 3.0, and topological polar surface area (tPSA) below 350 Å².

**ASSISTANT:** {"stage": "generate", "target": "Human Keap1 Kelch domain (Keap1-Nrf2 PPI inhibitor)", "scaffold_policy": "Macrocyclic peptide (head-to-tail backbone or sidechain cyclized), length 6-12 residues, maximum 2 non-canonical residues", "property_envelope": {"MW": [800, 1500], "cLogP": [-1.0, 3.0], "tPSA": {"max": 350}, "length": [6, 12], "max_non_canonical_residues": 2, "predicted_Kd_uM": {"max": 1.0}}, "count": 30}

---

## [332] source=multitask_sft_big

**USER:** Design 20 de-novo CDR-H3 loop sequences and conformations grafting into the human IGHV3-23/IGHJ4 germline framework to target the catalytic domain of PCSK9 (PDB: 2P4E, Chain A). Keep CDR-H1, CDR-H2, and the light chain fixed. The CDR-H3 length must be between 12 and 16 residues. Ensure candidates lack chemical liabilities (no N-glycosylation motifs N-X-[S/T], no unpaired cysteines, no DG/DS deamidation motifs), maintain a net charge between 0 and +2 at pH 7.4, have a grand average of hydropathicity (GRAVY) below 0.0, and exhibit high predicted binding affinity (ddG < -35.0 REU).

**ASSISTANT:** {"stage": "generate", "target": {"name": "PCSK9", "pdb_id": "2P4E", "chain": "A", "region": "catalytic domain"}, "scaffold_policy": {"framework": "IGHV3-23/IGHJ4", "design_region": "CDR-H3", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4", "Light Chain"], "cdr_h3_length_range": [12, 16]}, "property_envelope": {"net_charge_range": [0.0, 2.0], "max_gravy_score": 0.0, "max_binding_ddg_reu": -35.0, "excluded_motifs": ["N[^P][ST]", "C", "DG", "DS"]}, "count": 20}

---

## [333] source=multitask_sft_big

**USER:** Design 30 novel de novo small molecules for the A2A adenosine receptor that maintain favorable lipophilicity (logP between 1.5 and 3.0) while minimizing cardiac toxicity risk (predicted hERG IC50 > 10 µM). Keep molecular weight under 450 Da and explore diverse scaffolds.

**ASSISTANT:** {"stage": "generate", "target": "A2A adenosine receptor", "scaffold_policy": "diverse", "property_envelope": {"logP": [1.5, 3.0], "hERG_IC50_uM": ">10", "MW": "<=450"}, "count": 30}

---

## [334] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptides (8–13 residues, head-to-tail or thioether-cyclized) targeting the p53-binding pocket of MDM2 (PDB: 1YCR) to disrupt the MDM2-p53 interaction. Include non-canonical amino acids where beneficial to enhance proteolytic stability and mimic the Phe19-Trp23-Leu26 hydrophobic triad. Filter candidates for MW < 1500 Da, calculated logP between -0.5 and 3.0, and predicted binding affinity Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding pocket, PDB: 1YCR)", "scaffold_policy": {"modality": "macrocyclic peptide", "ring_closure": ["head-to-tail amide", "thioether bridge"], "sequence_length": "8-13 residues", "allow_non_canonical_amino_acids": true, "key_pharmacophore_features": "Hydrophobic triad mimicking Phe19, Trp23, Leu26 of p53"}, "property_envelope": {"molecular_weight_max": 1500, "clogP": {"min": -0.5, "max": 3.0}, "predicted_Kd_nM": 50, "proteolytic_stability": "high"}, "count": 20}

---

## [335] source=multitask_sft_big

**USER:** Please design 15 de-novo CDR-H3 loop sequences targeted against the SARS-CoV-2 Omicron BA.5 Receptor Binding Domain (RBD). Use the standard human IGHV3-23/IGHJ4 heavy chain framework, fixing the anchor residues at C92 and W103. Keep loop lengths between 10 and 16 amino acids. Ensure high predicted binding affinity (<50 nM), a net charge between -1.0 and +2.0 at pH 7.4, no N-linked glycosylation sequons (NxS/T), and low hydrophobic patch area (SAP score < 40) to minimize aggregation risk.

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Omicron BA.5 RBD", "structure_source": "PDB ID or AlphaFold model of BA.5 RBD epitope"}, "scaffold_policy": {"framework": "IGHV3-23*01 / IGHJ4*01", "region_to_design": "CDR-H3", "fixed_anchors": {"N_terminal": "C92", "C_terminal": "W103"}}, "property_envelope": {"length_range": [10, 16], "predicted_kd_nm": {"max": 50}, "net_charge_ph7_4": {"min": -1.0, "max": 2.0}, "unwanted_motifs": ["N[^P][ST]"], "aggregation_risk": {"max_sap_score": 40.0}}, "count": 15}

---

## [336] source=multitask_sft_big

**USER:** Generate 50 novel small molecules targeting human dopamine D2 receptor while mitigating cardiac safety risks. Ensure molecules have an optimized lipophilicity with cLogP between 2.0 and 3.5, and low hERG liability (predicted hERG IC50 > 10 µM). Keep molecular weight under 450 Da and TPSA between 40 and 90 Å².

**ASSISTANT:** {"stage": "generate", "target": "Dopamine D2 receptor (anti-target: hERG)", "scaffold_policy": "novel", "property_envelope": {"cLogP": {"min": 2.0, "max": 3.5}, "hERG_IC50_uM": {"min": 10.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 40, "max": 90}}, "count": 50}

---

## [337] source=multitask_sft_big

**USER:** Design 50 de novo drug-like small molecules featuring favorable hERG safety profiles (predicted hERG IC50 > 10 µM) and controlled lipophilicity with clogP strictly between 1.5 and 3.0. Please exclude strong basic lipophilic amine pharmacophores to minimize cardiotoxicity risk, and ensure MW <= 450 Da with TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": "hERG (KCNH2)", "scaffold_policy": "novel", "property_envelope": {"clogP": [1.5, 3.0], "hERG_IC50_uM": ">10", "MW": "<=450", "TPSA": [60, 110]}, "count": 50}

---

## [338] source=multitask_sft_big

**USER:** Generate 8 novel RNA aptamer sequences (length 30-50 nt) designed de novo to bind the human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692). The designs must not incorporate existing SELEX primer scaffold regions, should have a GC content between 40% and 60%, a minimum free energy (MFE) secondary structure stability <= -10 kcal/mol, and high predicted affinity with an estimated Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692)", "scaffold_policy": "de_novo", "property_envelope": {"length_nt": [30, 50], "gc_content_percent": [40, 60], "mfe_kcal_per_mol": {"max": -10.0}, "estimated_kd_nm": {"max": 50.0}}, "count": 8}

---

## [339] source=multitask_sft_big

**USER:** Design 50 de-novo CDR-H3 loops for a human IgG1 heavy-chain framework (grafted onto the Atezolizumab VH scaffold) to target the receptor-binding surface of human PD-L1 (PDB: 5X8M, Chain A). Loop length must be between 11 and 16 residues (IMGT positions 105–117). Filter candidates for high target interface confidence (ipTM >= 0.80, CDR pLDDT >= 82), favorable interface energy (predicted dG < -35 kcal/mol), no N-linked glycosylation sequons (N-X-S/T where X!=P), and net paratope charge between -1 and +2 at pH 7.4.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Programmed death-ligand 1 (PD-L1)", "pdb_id": "5X8M", "chain": "A", "epitope": "Receptor-binding surface (PD-1 competitive interface)"}, "scaffold_policy": {"framework": "Atezolizumab VH scaffold (humanized IgG1)", "region_to_design": "CDR-H3", "definition_scheme": "IMGT", "length_range": [11, 16], "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"]}, "property_envelope": {"ipTM": {"min": 0.8}, "cdr_plddt": {"min": 82.0}, "predicted_binding_energy_kcal_mol": {"max": -35.0}, "sequence_liabilities": {"exclude_motifs": ["N[^P][ST]"]}, "paratope_net_charge_pH7_4": {"min": -1.0, "max": 2.0}}, "count": 50}

---

## [340] source=multitask_sft_big

**USER:** Please design 5 novel RNA aptamers targeting the exosite-1 of human alpha-thrombin (UniProt: P00734). The candidate sequences should be between 30 and 45 nucleotides in length, have a GC content between 45% and 65%, feature a predicted secondary structure stability with MFE Delta G <= -8.0 kcal/mol, and contain no homopolymeric runs longer than 3 identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin (UniProt: P00734)", "scaffold_policy": "none", "property_envelope": {"sequence_length": {"min": 30, "max": 45}, "gc_content": {"min": 0.45, "max": 0.65}, "mfe_delta_g": {"max": -8.0, "unit": "kcal/mol"}, "max_homopolymer_length": 3}, "count": 5}

---

## [341] source=multitask_sft_big

**USER:** Please design 5 novel de novo RNA aptamers targeting human VEGF-165 with high binding affinity (target Kd < 20 nM). The sequences should be between 30 and 50 nucleotides in length, exhibit a minimum free energy (dG) below -10.0 kcal/mol for secondary structure stability, and maintain a GC content between 40% and 65%. Avoid any fixed constant primer scaffold regions.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "none", "property_envelope": {"molecule_type": "RNA", "sequence_length": {"min": 30, "max": 50}, "affinity_kd_nM": {"max": 20}, "mfe_kcal_mol": {"max": -10.0}, "gc_content_pct": {"min": 40.0, "max": 65.0}}, "count": 5}

---

## [342] source=multitask_sft_big

**USER:** Design 30 novel bifunctional PROTAC linkers connecting a BTK-targeting warhead (attached via an amino handle) to a VHL ligand (VH032 attached at the terminal acetyl handle). The linkers should span 8 to 14 heavy atoms in chain length, incorporate rigidifying heterocycles (such as piperazine, piperidine, or azetidine) to reduce conformational entropy, keep overall molecular weight under 1000 Da, cLogP between 2.0 and 4.5, tPSA < 190 Å², and strictly exclude hydrolytically unstable or metabolically labile groups like esters, hydrazones, and aliphatic disulfides.

**ASSISTANT:** {"stage": "generate", "target": "BTK-VHL PROTAC", "scaffold_policy": "linker_generation_between_warhead_and_e3", "property_envelope": {"linker_chain_length_heavy_atoms": [8, 14], "molecular_weight": "<= 1000", "clogp": [2.0, 4.5], "tpsa": "<= 190", "required_substructures": ["piperazine|piperidine|azetidine"], "excluded_substructures": ["ester", "hydrazone", "disulfide"]}, "count": 30}

---

## [343] source=multitask_sft_big

**USER:** Please design 15 novel heterocyclic core scaffolds for an ATP-competitive kinase inhibitor targeting LRRK2. The designs should deviate structurally from classical quinazoline, indolinone, and staurosporine motifs while retaining a plausible hinge-binding feature (at least one hydrogen bond donor and one acceptor). Please filter the generated candidates to keep molecular weight between 350 and 480 Da, cLogP between 2.0 and 4.0, TPSA <= 95 Å², and rotatable bonds <= 6, while excluding any PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 kinase", "scaffold_policy": {"type": "novel_core", "must_include": ["hinge_binding_donor_acceptor_motif"], "must_exclude": ["quinazoline", "indolinone", "staurosporine_derivatives"]}, "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "clogp": {"min": 2.0, "max": 4.0}, "tpsa": {"max": 95}, "rotatable_bonds": {"max": 6}, "exclude_pains": true, "exclude_reactive_warheads": true}, "count": 15}

---

## [344] source=multitask_sft_big

**USER:** Generate 20 de novo macrocyclic peptide binders targeting the p53 interaction pocket of MDM2 (PDB: 1YCR). The peptides should be head-to-tail cyclized with a sequence length of 8 to 12 residues, mimicking the critical p53 hot-spot triad (Phe19, Trp23, Leu26). Prioritize designs with high predicted target affinity (estimated Kd < 50 nM), stable alpha-helical conformation, CLogP between -1.0 and 3.0, and topological polar surface area (TPSA) < 250 Å² to balance aqueous solubility and conformational rigidity.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 p53-binding domain (PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptide, head-to-tail amide cyclization, 8-12 amino acids, structural mimicry of the p53 amphipathic alpha-helix", "property_envelope": {"predicted_kd_nm": "< 50", "clogp": [-1.0, 3.0], "tpsa": "< 250", "length": [8, 12]}, "count": 20}

---

## [345] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamer sequences targeting human Interleukin-6 (IL-6) for therapeutic neutralization. The aptamers should have lengths between 35 and 45 nucleotides, a GC content of 40-60%, a predicted minimum free energy (MFE) secondary structure stability with delta G < -10.0 kcal/mol, and a target binding affinity (Kd) below 20 nM with no non-specific binding to human serum albumin.

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (IL-6) [UniProt: P05231]", "scaffold_policy": "de novo single-stranded RNA without invariant flanking primer sequences", "property_envelope": {"length_nt": {"min": 35, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "predicted_mfe_deltaG_kcal_mol": {"max": -10.0}, "affinity_kd_nm": {"max": 20.0}, "counter_targets": ["Human Serum Albumin (HSA)"]}, "count": 10}

---

## [346] source=multitask_sft_big

**USER:** I need to design novel linkers connecting our BTK warhead (exit vector via a pendant phenolic oxygen) to a Cereblon E3 ligand (pomalidomide 4-amino derivative). Please generate 20 structurally diverse, semi-rigid linkers. Avoid standard extended PEG or pure unbranched alkyl chains; instead, incorporate motifs such as piperazine, spirocycles, or alkynes to restrain conformation. The linker chain length must be between 8 and 14 contiguous atoms. The resulting PROTACs should have a total MW < 950 Da (linker MW around 100-250 Da), calculated LogP between 2.0 and 4.5, tPSA < 220 Å², and contain no metabolically labile ester or hydrazone groups.

**ASSISTANT:** {"stage": "generate", "target": "BTK-Cereblon PROTAC linker", "scaffold_policy": "Bifunctional linker joining phenolic BTK warhead to 4-amino pomalidomide; enforce semi-rigid motifs (piperazines, spirocycles, alkynes); forbid pure polymethylene or straight PEG linkers; exclude esters and hydrazones", "property_envelope": {"linker_atom_length": [8, 14], "linker_mw": [100, 250], "protac_mw_max": 950, "protac_clogp": [2.0, 4.5], "protac_tpsa_max": 220}, "count": 20}

---

## [347] source=multitask_sft_big

**USER:** Generate 10 de-novo single-stranded RNA aptamers targeting human VEGF-165 (UniProt P15692). Each sequence should be between 35 and 45 nucleotides in length, with a predicted dissociation constant (Kd) under 15 nM, GC content within 40% to 60%, and folding minimum free energy (MFE) <= -12.0 kcal/mol at 37°C. Avoid homopolymeric stretches of 5 or more consecutive identical bases.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human VEGF-165", "uniprot_id": "P15692"}, "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "predicted_kd_nM": {"max": 15.0}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_folding_kcal_mol": {"max": -12.0}, "max_homopolymer_run": 4}, "count": 10}

---

## [348] source=multitask_sft_big

**USER:** Design 25 de novo macrocyclic peptide binders targeting the oncogenic Menin-MLL protein-protein interaction surface. The candidates should be 8 to 13 residues in length, cyclized via head-to-tail backbone linkage or a hydrocarbon staple (i, i+4 or i, i+7), with molecular weight under 1600 Da, net charge between 0 and +2 to favor passive/active cell permeability, and predicted nanomolar binding affinity with high shape complementarity to the Menin interface pocket.

**ASSISTANT:** {"stage": "generate", "target": "Menin-MLL interface pocket (PDB: 4OG7 / 4X5Z)", "scaffold_policy": "macrocyclic peptide (8-13 residues), head-to-tail amide cyclization or i, i+4 / i, i+7 hydrocarbon staple, canonical and non-canonical amino acids permitted", "property_envelope": {"molecular_weight": "<= 1600", "peptide_length": "8-13 residues", "net_charge": "0 to +2", "cLogP": "-1.0 to 4.0", "rotatable_bonds": "<= 20", "interface_buried_surface_area": ">= 600 A^2"}, "count": 25}

---

## [349] source=multitask_sft_big

**USER:** Design 20 novel, partially rigidified linkers to connect a BRD4 warhead (JQ1 derivative via amide exit vector) to a CRBN E3 ligase ligand (pomalidomide via C4-amino exit vector). The linkers must span 9 to 14 heavy atoms to enable productive ternary complex formation, favor aliphatic/piperazine/alkyne motifs over flexible homo-PEG chains, keep linker rotatable bonds <= 6, maintain linker cLogP between 0.5 and 2.5, and ensure the resulting intact PROTAC has a molecular weight <= 900 Da.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-CRBN PROTAC Linker", "scaffold_policy": "Bifunctional linker generation connecting fixed JQ1 amide attachment vector and Pomalidomide C4-amino vector", "property_envelope": {"linker_chain_heavy_atoms": {"min": 9, "max": 14}, "linker_rotatable_bonds": {"max": 6}, "linker_clogp": {"min": 0.5, "max": 2.5}, "intact_protac_mw": {"max": 900}, "disallowed_motifs": ["homo-PEG >= 3 units"]}, "count": 20}

---

## [350] source=multitask_sft_big

**USER:** Generate 10 novel, non-quinazoline heterocyclic scaffolds for de novo kinase inhibitor design. The cores should possess a distinct hinge-binding hydrogen bond donor-acceptor motif, MW < 400 Da, cLogP between 1.5 and 3.5, TPSA 50-90 Å², rotatable bonds <= 5, and strictly avoid PAINS or reactive functionalities.

**ASSISTANT:** {"stage": "generate", "target": "Kinase hinge region", "scaffold_policy": "novel heterocyclic cores, strictly avoid known quinazolines, must contain hinge-binding donor-acceptor motif", "property_envelope": {"MW": "< 400", "cLogP": "1.5 - 3.5", "TPSA": "50 - 90 \u00c5\u00b2", "rotatable_bonds": "<= 5", "PAINS": false, "reactive_groups": false}, "count": 10}

---

## [351] source=multitask_sft_big

**USER:** Please generate 15 novel CDR-H3 loop sequences grafted onto the Trastuzumab (Herceptin) VH framework (IGHV3-23/IGHJ4) targeting domain IV of the HER2 extracellular domain (PDB: 1N8Z). The CDR-H3 loop length should be constrained between 10 and 16 residues. Ensure the designs have predicted high binding affinity (pKd > 8.5), net charge between -1.0 and +2.0 at pH 7.4, zero N-linked glycosylation motifs (N-X-[S/T]), and low predicted aggregation propensity.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain (Domain IV)", "pdb_id": "1N8Z"}, "scaffold_policy": {"framework": "Trastuzumab VH (IGHV3-23 / IGHJ4)", "redesign_region": "CDR-H3", "framework_fixed": true}, "property_envelope": {"cdr_h3_length": [10, 16], "predicted_pKd": {"min": 8.5}, "net_charge_pH_7_4": {"min": -1.0, "max": 2.0}, "forbidden_motifs": ["N[^P][ST]"], "aggregation_propensity": "low"}, "count": 15}

---

## [352] source=multitask_sft_big

**USER:** Design 5 de-novo RNA aptamer sequences targeting human VEGF-165 (UniProt P15692) for potential anti-angiogenic therapeutic applications. The candidate aptamers should have a length between 35 and 45 nucleotides, a predicted folding free energy (ΔG) below -12.0 kcal/mol at 37°C in physiological buffer, and a predicted binding affinity (Kd) < 50 nM. Maintain a GC content between 40% and 60%, avoid homopolymer runs of 4 or more identical nucleotides (especially poly-G to prevent unintended G-quadruplex aggregation unless explicitly structured), and ensure diverse secondary structural motifs including hairpin loops and internal bulges.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor 165 (VEGF-165, UniProt: P15692)", "scaffold_policy": "free de-novo sequence generation without mandatory fixed primer binding arms", "property_envelope": {"length_nt": [35, 45], "predicted_kd_nM": "< 50", "mfe_delta_g_kcal_mol": "< -12.0", "gc_content_percent": [40.0, 60.0], "max_homopolymer_run": 3, "temperature_celsius": 37.0}, "count": 5}

---

## [353] source=multitask_sft_big

**USER:** Design 50 de novo macrocyclic peptide binders targeting the p53-binding cleft of MDM2 (PDB: 1YCR). Peptides should be 7 to 12 residues in length, stabilized via head-to-tail or side-chain-to-side-chain cyclization (avoiding labile disulfide bridges), and present hydrophobic side chains mimicking the Phe19, Trp23, and Leu26 hot-spot triad. Maintain a molecular weight < 1500 Da, clogP between 1.0 and 4.0, and predicted low-nanomolar binding affinity.

**ASSISTANT:** {"stage": "generate", "target": {"name": "MDM2", "binding_site": "p53 transactivation domain interaction groove (Phe19, Trp23, Leu26 pocket)", "pdb_id": "1YCR"}, "scaffold_policy": {"topology": "macrocyclic peptide", "cyclization_type": "head-to-tail or non-disulfide side-chain-to-side-chain staple", "length_range": [7, 12], "disallowed_motifs": ["disulfide"]}, "property_envelope": {"molecular_weight": "< 1500 Da", "clogP": [1.0, 4.0], "affinity_target": "< 100 nM", "hotspot_mimetics": ["Phe", "Trp", "Leu"]}, "count": 50}

---

## [354] source=multitask_sft_big

**USER:** Design 10 de novo RNA aptamer sequences targeting human VEGF-165 (UniProt: P15692). Sequences must be 35 to 45 nucleotides in length with high predicted binding affinity (Kd < 20 nM). Ensure a GC content between 40% and 60%, a minimum folding free energy (ΔG) below -8.0 kcal/mol at 37°C for stable secondary structure, and avoid poly-G runs longer than 4 consecutive nucleotides to prevent non-specific G-quadruplex aggregation.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": "de_novo", "property_envelope": {"sequence_length": {"min": 35, "max": 45}, "affinity_kd_nm": "< 20", "gc_content_percent": {"min": 40.0, "max": 60.0}, "folding_mfe_kcal_mol": "< -8.0", "motif_exclusions": ["GGGGG"]}, "count": 10}

---

## [355] source=multitask_sft_big

**USER:** Generate 10 de novo macrocyclic peptide binders targeting the Kelch domain of Keap1 to inhibit the Keap1-Nrf2 protein-protein interaction. The candidates must be head-to-tail cyclized peptides of 7 to 10 amino acid residues incorporating natural and non-canonical residues. Filter for predicted binding affinity Kd < 50 nM, molecular weight under 1200 Da, TPSA between 250 and 350 Å², and human plasma proteolytic stability with half-life > 4 hours.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (Keap1-Nrf2 PPI)", "scaffold_policy": "Head-to-tail macrocyclic peptide (7-10 residues, canonical and non-canonical amino acids)", "property_envelope": {"predicted_Kd": "< 50 nM", "molecular_weight": "< 1200 Da", "tpsa": "250-350 \u00c5\u00b2", "plasma_half_life": "> 4 h"}, "count": 10}

---

## [356] source=multitask_sft_big

**USER:** Please design 5 de-novo RNA aptamer sequences targeting the human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692). The aptamers should have a length between 40 and 50 nucleotides, a GC content between 40% and 60%, predicted folding free energy (dG) of -10 kcal/mol or lower to ensure stable secondary structure, avoid continuous runs of identical nucleotides longer than 4 (no poly-G/poly-U > 4), and exhibit high predicted binding affinity (Kd < 20 nM) to VEGF-165.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor 165 (VEGF-165, UniProt P15692)", "scaffold_policy": "de novo single-stranded RNA aptamers (40-50 nt) without predefined primer-binding scaffolds", "property_envelope": {"length": [40, 50], "gc_content_pct": [40, 60], "mfe_folding_dG_kcal_mol": {"max": -10.0}, "max_homopolymer_run": 4, "target_binding_affinity_Kd_nM": {"max": 20.0}}, "count": 5}

---

## [357] source=multitask_sft_big

**USER:** Design 25 de novo macrocyclic peptide binders targeting the p53-binding pocket of human MDM2 to inhibit the MDM2-p53 protein-protein interaction. The designs should feature cyclic constrained scaffolds (8–13 amino acids in length, utilizing either head-to-tail cyclization or an i, i+4 hydrocarbon staple to stabilize an alpha-helical conformation). Filter for high predicted affinity (Kd < 50 nM), minimal aggregation propensity, improved serum proteolytic stability, and moderate cell permeability. Exclude peptides with more than 2 net negative charges or free reactive thiols.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 (disrupting MDM2-p53 interaction)", "scaffold_policy": "Macrocyclic peptide (8\u201313 amino acids, head-to-tail cyclized or i, i+4 hydrocarbon-stapled alpha-helical constraint)", "property_envelope": {"length": "8-13 residues", "binding_affinity_Kd": "< 50 nM", "secondary_structure": "alpha-helical mimic", "serum_stability": "high", "cellular_permeability": "moderate", "net_charge": ">= -2", "free_cysteines": "<= 0"}, "count": 25}

---

## [358] source=multitask_sft_big

**USER:** We need to design 15 novel PROTAC linkers connecting our BRD4 warhead (amine exit vector, [Warhead]-NH2) to a VHL ligand (phenolic attachment point, [VHL]-OH). To improve oral bioavailability and cellular permeability compared to standard alkyl/PEG linkers, generate semi-rigid linkers containing small heterocycles or spirocycles (e.g., piperazine, azetidine, or 2,6-diazaspiro[3.3]heptane). Linker length must be between 8 and 14 heavy atoms. Constrain the linker fragment MW to < 250 Da, linker cLogP to 0.5–2.5, rotatable bonds <= 6, and ensure the overall estimated intact PROTAC MW stays below 950 Da.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 degradation via VHL E3 ligase", "scaffold_policy": "Keep BRD4 warhead and VHL binder fixed; grow linker between [Warhead]-NH2 and [VHL]-OH; incorporate rigidifying heterocycles/spirocycles; exclude purely linear PEG chains (max 1 PEG unit)", "property_envelope": {"linker_heavy_atom_count": [8, 14], "linker_mw_max": 250, "linker_clogp": [0.5, 2.5], "linker_rotatable_bonds_max": 6, "total_protac_mw_max": 950}, "count": 15}

---

## [359] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptides targeting the Kelch domain of Keap1 to disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should contain between 8 and 13 amino acids, incorporate a head-to-tail or disulfide/thioether cyclization, exhibit high predicted binding affinity (Kd < 50 nM), maintain a molecular weight between 800 and 1600 Da, and feature at least 2 non-canonical amino acids to enhance proteolytic stability.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (disrupting Keap1-Nrf2 interaction)", "scaffold_policy": "Macrocyclic peptide, length 8-13 amino acids, head-to-tail or disulfide/thioether cyclized scaffold with >= 2 non-canonical amino acid substitutions", "property_envelope": {"molecular_weight": [800, 1600], "predicted_Kd_nM": "< 50", "peptide_length": [8, 13], "min_non_canonical_residues": 2}, "count": 20}

---

## [360] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamers targeting human alpha-thrombin (UniProt: P00734). The sequences should be between 30 and 45 nucleotides in length, have a GC content between 40% and 65%, and exhibit high predicted binding affinity with a Kd below 20 nM. Ensure structural stability with a predicted minimum free energy (MFE) lower than -10 kcal/mol, and avoid homopolymer tracts longer than 4 nucleotides. Do not bias or fix the sequences to known aptamer scaffolds.

**ASSISTANT:** {"stage": "generate", "target": "Human alpha-thrombin (UniProt: P00734)", "scaffold_policy": "free", "property_envelope": {"length": {"min": 30, "max": 45}, "gc_content_percent": {"min": 40, "max": 65}, "affinity_kd_nm": {"max": 20}, "mfe_kcal_mol": {"max": -10.0}, "max_homopolymer_length": 4}, "count": 10}

---

## [361] source=multitask_sft_big

**USER:** Generate 50 de novo macrocyclic peptide binders designed to disrupt the human MDM2-p53 protein-protein interaction. The peptides should be head-to-tail cyclized or hydrocarbon-stapled with sequence lengths between 8 and 13 residues. Please ensure the compounds have a molecular weight between 900 and 1600 Da, cLogP between 0.0 and 4.0, topological polar surface area (TPSA) under 320 Å², and predicted binding affinity (Kd) below 100 nM against the p53-binding pocket of MDM2. Exclude strictly linear peptides and any sequences containing unstable chemical moieties or metabolically labile motifs.

**ASSISTANT:** {"stage": "generate", "target": "human MDM2 (p53-binding cleft, PPI disruption)", "scaffold_policy": "Macrocyclic peptides (head-to-tail cyclized or hydrocarbon stapled), length 8-13 residues, strictly non-linear, canonical and non-canonical amino acids allowed", "property_envelope": {"molecular_weight": {"min": 900, "max": 1600}, "clogp": {"min": 0.0, "max": 4.0}, "tpsa_max": 320, "predicted_kd_max_nM": 100, "structural_alerts": "Exclude unstable moieties and metabolically labile motifs"}, "count": 50}

---

## [362] source=multitask_sft_big

**USER:** Design 25 novel core scaffolds for ATP-competitive Type I kinase inhibitors targeting EGFR T790M/L858R. The scaffolds must present a novel heterocyclic hinge-binding motif distinct from quinazoline, pyrimidine, and purine templates, with synthetic exit vectors for the solvent front and back pocket. Ensure lead-like properties: MW 300-450, cLogP 2.0-3.8, TPSA 60-100 Å², HBD <= 2, HBA 4-7, and RotB <= 5.

**ASSISTANT:** {"stage": "generate", "target": "EGFR T790M/L858R", "scaffold_policy": "novel heterocyclic hinge-binding core; exclude quinazolines, pyrimidines, purines; preserve clear exit vectors", "property_envelope": {"MW": [300, 450], "cLogP": [2.0, 3.8], "TPSA": [60, 100], "HBD": "<= 2", "HBA": [4, 7], "RotB": "<= 5"}, "count": 25}

---

## [363] source=multitask_sft_big

**USER:** Design 25 de novo macrocyclic peptide inhibitors targeting the human MDM2 oncoprotein at the p53-binding interface (PDB: 1YCR). The macrocycles should consist of 6 to 10 amino acid residues, cyclized via head-to-tail backbone amide or a disulfide/thioether crosslink, allowing both canonical residues and common non-canonical building blocks (e.g., 6-chloro-Trp, N-methyl amino acids). Ensure candidates have a predicted Kd < 100 nM, molecular weight between 750 and 1350 Da, cLogP between -1.0 and 3.5, and TPSA < 320 Å² for membrane permeability potential.

**ASSISTANT:** {"stage": "generate", "target": "Human MDM2 p53-interaction pocket (PDB: 1YCR)", "scaffold_policy": "Macrocyclic peptides of 6-10 residues with head-to-tail backbone amide or disulfide/thioether cyclization; allows canonical and non-canonical amino acids", "property_envelope": {"Kd": "< 100 nM", "molecular_weight": "750 - 1350 Da", "cLogP": "-1.0 - 3.5", "TPSA": "< 320 \u00c5\u00b2"}, "count": 25}

---

## [364] source=multitask_sft_big

**USER:** Generate 25 novel drug-like small molecules targeting the 5-HT2A receptor with optimized lipophilicity and minimized cardiotoxicity risk. Keep LogP strictly between 1.5 and 3.0, ensure molecular weight is below 450 Da, and prioritize low hERG channel liability with a predicted hERG pIC50 < 5.0 (IC50 > 10 µM). Broad scaffold exploration is encouraged without requiring a specific starting core.

**ASSISTANT:** {"stage": "generate", "target": "5-HT2A", "scaffold_policy": {"type": "unconstrained", "diversity": "high"}, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "MW": {"max": 450}, "hERG_pIC50": {"max": 5.0}}, "count": 25}

---

## [365] source=multitask_sft_big

**USER:** Please design 10 de-novo RNA aptamer sequences targeting human alpha-thrombin (UniProt: P00734). The candidates should be 40 nucleotides in length, possess a predicted secondary structure minimum free energy (MFE) <= -14.0 kcal/mol, maintain a GC content between 45% and 65%, avoid homopolymeric runs of 4 or more identical nucleotides, and exhibit high predicted binding affinity (Kd < 50 nM).

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human alpha-thrombin", "uniprot_id": "P00734", "type": "protein"}, "scaffold_policy": {"molecule_type": "RNA", "mode": "de_novo", "length": 40, "fixed_regions": null}, "property_envelope": {"predicted_kd_nm": {"max": 50.0}, "mfe_kcal_per_mol": {"max": -14.0}, "gc_content_percent": {"min": 45.0, "max": 65.0}, "max_homopolymer_length": 3}, "count": 10}

---

## [366] source=multitask_sft_big

**USER:** Design 10 novel, non-quinazoline core scaffolds for ATP-competitive kinase inhibition targeting EGFR (L858R/T790M). Ensure each scaffold presents a standard hinge-binding donor-acceptor motif, distinct exit vectors for the ribose pocket and solvent-exposed channel, and maintains drug-like properties: MW 300-450, LogP 1.5-3.5, TPSA < 90 Å², and rotatable bonds <= 5.

**ASSISTANT:** {"stage": "generate", "target": "EGFR (L858R/T790M)", "scaffold_policy": "novel core, non-quinazoline, hinge-binding donor-acceptor pair, designated exit vectors", "property_envelope": {"MW": [300, 450], "LogP": [1.5, 3.5], "TPSA": [0, 90], "rotatable_bonds": "<= 5", "HBD": [1, 2]}, "count": 10}

---

## [367] source=multitask_sft_big

**USER:** Design 15 de novo macrocyclic peptide binders targeting the human Keap1 Kelch domain (PDB: 2FLU) to disrupt the Keap1-Nrf2 protein-protein interaction. The macrocycles should contain 8 to 14 amino acids with head-to-tail backbone or disulfide cyclization, incorporating natural or standard non-canonical residues. Aim for predicted Kd < 50 nM, molecular weight between 800 and 1600 Da, cLogP from -1.0 to 3.5, polar surface area (PSA) < 450 Å², and high projected serum stability.

**ASSISTANT:** {"stage": "generate", "target": "Human Keap1 Kelch domain (disrupting Keap1-Nrf2 interaction, PDB: 2FLU)", "scaffold_policy": "Macrocyclic peptides (8-14 amino acids, head-to-tail or disulfide/thioether cyclized, permitting canonical and non-canonical amino acids)", "property_envelope": {"Kd": "< 50 nM", "molecular_weight": "800-1600 Da", "clogP": "-1.0 - 3.5", "tPSA": "< 450 \u00c5\u00b2", "serum_stability": "high"}, "count": 15}

---

## [368] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamer sequences targeting human VEGF-165 (UniProt P15692) capable of inhibiting VEGFR2 binding. The aptamers must be between 30 and 45 nucleotides in length, have a GC content between 40% and 60%, a predicted folding minimum free energy (MFE) between -18.0 and -10.0 kcal/mol, and contain no homopolymeric runs exceeding 4 consecutive identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": null, "property_envelope": {"length": {"min": 30, "max": 45}, "gc_content": {"min": 0.4, "max": 0.6}, "mfe_kcal_per_mol": {"min": -18.0, "max": -10.0}, "max_homopolymer_run": 4}, "count": 8}

---

## [369] source=multitask_sft_big

**USER:** Please design 10 novel RNA aptamers from scratch targeting human vascular endothelial growth factor 165 (VEGF-165, UniProt P15692). The aptamers should be between 35 and 45 nucleotides in length, with predicted binding affinity Kd < 25 nM and robust secondary structure stability (folding minimum free energy ΔG < -12.0 kcal/mol at 37°C). Maintain a GC content between 45% and 65%, avoiding long homopolymer runs (poly-G >= 4 or poly-U >= 4). Ensure high specificity against off-targets like VEGF-B.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt P15692)", "scaffold_policy": "de_novo", "property_envelope": {"length": "35-45 nt", "predicted_binding_affinity_Kd_nM": "< 25", "mfe_folding_dG_kcal_mol": "< -12.0", "gc_content_percent": "45-65", "homopolymer_run_max": 3, "selectivity": "VEGF-165 over VEGF-B"}, "count": 10}

---

## [370] source=multitask_sft_big

**USER:** Design 10 novel CDR-H3 loop sequences grafted onto the Trastuzumab heavy chain scaffold targeting the HER2 extracellular domain (PDB ID: 1N8Z). Keep the framework regions, CDR-H1, CDR-H2, and the entire light chain fixed. The CDR-H3 loop length should be between 11 and 16 amino acids and maintain the canonical torso/stem motif anchoring at Cys92 and Trp103 (Chothia numbering). Optimize for predicted binding affinity (Kd < 10 nM), low self-aggregation propensity (SAP score < 15), and avoid common developability liabilities such as N-linked glycosylation sites (NxS/T), unpaired cysteines, and high-frequency deamidation motifs (NG, NN).

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 (ErbB2) extracellular domain", "pdb_id": "1N8Z", "chain": "C"}, "scaffold_policy": {"scaffold": "Trastuzumab (Fab)", "fixed_regions": ["Heavy_Chain_FR1-4", "CDR-H1", "CDR-H2", "Light_Chain"], "design_region": "CDR-H3", "anchor_residues": ["Cys92", "Trp103"]}, "property_envelope": {"length": {"min": 11, "max": 16}, "affinity_kd_nm": {"max": 10}, "spatial_aggregation_propensity": {"max": 15}, "liabilities_excluded": ["N-linked glycosylation (N[^P][ST])", "Unpaired cysteines", "Deamidation hotspots (NG, NN)"]}, "count": 10}

---

## [371] source=multitask_sft_big

**USER:** Design 20 de-novo macrocyclic peptide binders targeting the MDM2-p53 protein-protein interaction interface. The peptides should have a sequence length of 8-14 amino acids, be constrained via head-to-tail or disulfide cyclization, achieve predicted binding affinity Kd < 50 nM, exhibit high proteolytic stability, and have a clogP between -2.0 and 3.0.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53 binding site)", "scaffold_policy": "macrocycle (8-14 amino acids, head-to-tail or disulfide cyclization)", "property_envelope": {"binding_affinity_Kd_nM": "< 50", "sequence_length": "8-14", "clogP": "[-2.0, 3.0]", "proteolytic_stability": "high", "cyclization_type": ["head-to-tail", "disulfide"]}, "count": 20}

---

## [372] source=multitask_sft_big

**USER:** Generate 40 novel small molecules designed de novo with low cardiotoxicity liability, specifically requiring hERG IC50 > 10 uM (or pIC50 < 5.0) and an optimal LogP between 1.5 and 3.0. Ensure drug-like properties with molecular weight between 250 and 450 Da and TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "MW": {"min": 250, "max": 450}, "TPSA": {"min": 60, "max": 110}}, "count": 40}

---

## [373] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small molecule core scaffolds targeting the ATP-binding pocket of protein kinases. The molecules must feature a novel hinge-binding motif distinct from classic 4-anilinoquinazolines and pyrazolopyrimidines, with at least one viable exit vector for R-group diversification. Property requirements: MW 300-450 Da, LogP 1.5-3.5, TPSA 60-100 Å², HBD 1-3, HBA 3-7, and rotatable bonds ≤ 6.

**ASSISTANT:** {"stage": "generate", "target": "Protein kinase ATP-binding site", "scaffold_policy": {"novelty": "novel hinge-binding motif", "excluded_scaffolds": ["4-anilinoquinazoline", "pyrazolopyrimidine"], "features": ["hinge-binding capability", "at least one synthetic exit vector"]}, "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "logP": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 60.0, "max": 100.0}, "hbd": {"min": 1, "max": 3}, "hba": {"min": 3, "max": 7}, "rotatable_bonds": {"max": 6}}, "count": 50}

---

## [374] source=multitask_sft_big

**USER:** Design 15 novel small molecule candidates targeting LRRK2 with a low cardiac toxicity profile. Ensure optimized lipophilicity with a clogP between 1.5 and 2.8, minimized hERG liability (predicted hERG IC50 > 10 µM / pIC50 < 5.0), MW under 450 Da, and avoid typical hERG-inducing basic lipophilic amine pharmacophores.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2", "scaffold_policy": "novel core scaffolds lacking basic lipophilic amine motifs", "property_envelope": {"clogP": [1.5, 2.8], "hERG_pIC50": "< 5.0", "hERG_IC50_uM": "> 10.0", "MW": "<= 450"}, "count": 15}

---

## [375] source=multitask_sft_big

**USER:** Design 50 de novo CDR-H3 loop sequences and conformations to bind the human HER2 extracellular domain (subdomain IV, PDB 1N8Z). Graft these designs into a fixed Trastuzumab-derived VH3-23/JH4 heavy chain scaffold while keeping CDR-H1, CDR-H2, and the light chain unchanged. CDR-H3 length should range between 11 and 16 residues. Designs must demonstrate predicted binding affinity (Kd < 20 nM or interface dG < -35 REU), maintain loop stability, have a CDR-H3 net charge between -1 and +2 at pH 7.4, and exclude sequence liabilities including N-linked glycosylation sites (NxS/T), deamidation motifs (NG, NN), and unpaired cysteines.

**ASSISTANT:** {"stage": "generate", "target": "Human epidermal growth factor receptor 2 (HER2) extracellular domain IV (PDB 1N8Z)", "scaffold_policy": {"framework": "Human IGHV3-23/IGHJ4 (Trastuzumab heavy/light chain)", "fixed_regions": ["FR-H1", "CDR-H1", "FR-H2", "CDR-H2", "FR-H3", "FR-H4", "VL"], "design_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [11, 16], "predicted_kd_nm": "<= 20", "interface_dg_reu": "<= -35.0", "net_charge_ph7_4": [-1, 2], "sequence_liabilities_excluded": ["N[^P][ST]", "NG", "NN", "DG", "C"]}, "count": 50}

---

## [376] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamer candidates targeting human thrombin (exosite I). Each aptamer must be exactly 40 nucleotides long, flanked by 5'-GGGAU and 3'-UCCC terminal motifs to support stem stability. The variable core should be optimized for target affinity (predicted Kd < 50 nM), maintain a GC content between 45% and 65%, have a predicted secondary structure minimum free energy (MFE) below -12.0 kcal/mol, and contain no homopolymer tracts longer than 3 consecutive identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human Thrombin", "binding_site": "Exosite I", "uniprot_id": "P00734"}, "scaffold_policy": {"fixed_5_prime": "GGGAU", "fixed_3_prime": "UCCC", "variable_length": 31, "total_length": 40}, "property_envelope": {"length": 40, "gc_content": {"min": 0.45, "max": 0.65}, "mfe_kcal_per_mol": {"max": -12.0}, "max_homopolymer_length": 3, "predicted_kd_nM": {"max": 50.0}}, "count": 10}

---

## [377] source=multitask_sft_big

**USER:** Design 50 novel, diverse small-molecule scaffolds for ATP-competitive inhibition of the EGFR kinase domain (L858R/T790M mutant). Ensure the scaffolds feature a hinge-binding motif distinct from canonical 4-anilinoquinazolines. Maintain lead-like drug properties: MW between 350 and 480 Da, LogP between 2.0 and 4.0, TPSA between 60 and 100 Å², HBD <= 3, HBA <= 8, and rotatable bonds <= 6.

**ASSISTANT:** {"stage": "generate", "target": "EGFR kinase (L858R/T790M)", "scaffold_policy": "novel core required; avoid canonical 4-anilinoquinazoline scaffolds", "property_envelope": {"MW": [350, 480], "LogP": [2.0, 4.0], "TPSA": [60.0, 100.0], "HBD": "<= 3", "HBA": "<= 8", "RotB": "<= 6"}, "count": 50}

---

## [378] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamer sequences targeting human vascular endothelial growth factor 165 (VEGF-165). The RNA sequences should be 35 to 50 nucleotides in length with a GC content between 40% and 60%. Sequences must fold into stable secondary structures with a predicted minimum free energy (MFE) between -18.0 and -8.0 kcal/mol, avoid homopolymer tracts longer than 4 consecutive identical nucleotides, and be optimized for high-affinity binding (predicted Kd < 10 nM) to VEGF-165.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt P15692-4)", "scaffold_policy": "none", "property_envelope": {"molecule_type": "ssRNA", "sequence_length": {"min": 35, "max": 50}, "gc_content": {"min": 0.4, "max": 0.6}, "folding_mfe_kcal_per_mol": {"min": -18.0, "max": -8.0}, "max_homopolymer_length": 4, "target_kd_nM": {"max": 10.0}}, "count": 8}

---

## [379] source=multitask_sft_big

**USER:** Generate 20 novel small-molecule scaffolds for an oncology program targeting the kinase ATP-binding site. The structures must present a novel hinge-binding motif, explicitly avoiding standard quinazoline, pyrazolopyrimidine, and indolin-2-one cores. Ensure the designs are drug-like with MW between 320 and 460 Da, cLogP between 1.5 and 3.5, TPSA between 60 and 95 Å², HBD 1-3, HBA 3-7, and at most 5 rotatable bonds.

**ASSISTANT:** {"stage": "generate", "target": "Kinase ATP-binding site", "scaffold_policy": {"novelty": "de novo novel hinge-binding motifs", "exclude": ["quinazoline", "pyrazolo[1,5-a]pyrimidine", "indolin-2-one"]}, "property_envelope": {"molecular_weight": {"min": 320, "max": 460}, "clogp": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 60, "max": 95}, "hbd": {"min": 1, "max": 3}, "hba": {"min": 3, "max": 7}, "rotatable_bonds": {"max": 5}}, "count": 20}

---

## [380] source=multitask_sft_big

**USER:** Design 50 de novo small molecule scaffolds that could serve as ATP-competitive inhibitors targeting the LRRK2 kinase domain. Ensure the cores are novel and distinct from common bis-anilino-pyrimidine or staurosporine chemotypes, incorporate a suitable hinge-binding motif (1-2 hydrogen bond donors/acceptors), keep molecular weight between 300 and 450 Da, cLogP between 1.5 and 4.0, tPSA below 90 Å², and rotatable bond count no greater than 6.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2 kinase domain", "scaffold_policy": "novel core, structurally distinct from bis-anilino-pyrimidine and staurosporine motifs, featuring hinge-binding donor-acceptor features", "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "clogp": {"min": 1.5, "max": 4.0}, "tpsa": {"max": 90.0}, "rotatable_bonds": {"max": 6}}, "count": 50}

---

## [381] source=multitask_sft_big

**USER:** Design 10 novel RNA aptamers targeting human Interleukin-6 (IL-6, UniProt P05231) with high affinity. Aptamers should be between 40 and 50 nucleotides in length, maintain a GC content between 40% and 60%, have an estimated binding affinity Kd under 50 nM, a secondary structure folding free energy (ΔG) between -15.0 and -5.0 kcal/mol at 37°C, and avoid homopolymer tracts longer than 4 consecutive bases.

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (IL-6, UniProt P05231)", "scaffold_policy": "none", "property_envelope": {"length": {"min": 40, "max": 50}, "gc_content": {"min": 0.4, "max": 0.6}, "predicted_kd_nM": {"max": 50}, "folding_delta_g_kcal_mol": {"min": -15.0, "max": -5.0}, "max_homopolymer_length": 4}, "count": 10}

---

## [382] source=multitask_sft_big

**USER:** Design 20 de novo CDR-H3 loops grafted into the humanized VH framework (IGHV3-23/JH4, Trastuzumab backbone) targeted against the domain III epitope of human EGFR (PDB: 1YY9). The CDR-H3 loop length should range from 12 to 16 residues. Generated sequences must have high predicted target binding affinity (Kd < 10 nM), maintain favorable loop structural stability (predicted folding free energy ΔG < 0 kcal/mol), and exhibit clean developability profiles by strictly avoiding N-glycosylation sites (N-X-[S/T], X!=P), unpaired cysteines, and hydrophobic patches (no more than 2 consecutive aromatic residues). Keep the net charge of the CDR-H3 between -2 and +1.

**ASSISTANT:** {"stage": "generate", "target": {"name": "Human Epidermal Growth Factor Receptor (EGFR) Domain III", "pdb_id": "1YY9", "target_type": "protein antigen"}, "scaffold_policy": {"framework": "IGHV3-23/JH4 humanized VH scaffold", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "length_range": [12, 16]}, "property_envelope": {"binding_affinity": {"predicted_kd_nM": "< 10"}, "stability": {"predicted_folding_delta_g_kcal_mol": "< 0"}, "net_charge": {"min": -2, "max": 1}, "sequence_motifs_to_exclude": ["N[^P][ST]", "C", "[FWY]{3,}"]}, "count": 20}

---

## [383] source=multitask_sft_big

**USER:** Design 10 novel CDR-H3 loop sequences grafted onto the human VH3-23/JH4 framework targeting the SARS-CoV-2 Spike receptor-binding domain (RBD, PDB: 6M0J, Chain E). Keep CDR-H3 loop length between 12 and 16 residues. Ensure predicted binding affinity (Kd) < 50 nM, humanness score (OAS-derived identity) >= 0.75, net charge between -1.0 and +1.5 at pH 7.4, hydrophobicity (GRAVY) between -0.4 and 0.2, and strictly eliminate sequence liabilities including free cysteines, N-linked glycosylation sites (N-X-[S/T]), and deamidation motifs (NG, NS).

**ASSISTANT:** {"stage": "generate", "target": {"name": "SARS-CoV-2 Spike RBD", "structure_reference": "PDB: 6M0J, Chain E", "epitope_focus": "Receptor binding motif (RBM)"}, "scaffold_policy": {"framework": "Human IGHV3-23*01 / IGHJ4*01", "region_to_design": "CDR-H3 (IMGT positions 105-117)", "framework_status": "fixed"}, "property_envelope": {"cdr_h3_length": [12, 16], "predicted_kd_nm": {"max": 50}, "humanness_score": {"min": 0.75}, "net_charge_ph7_4": [-1.0, 1.5], "gravy_index": [-0.4, 0.2], "liabilities_excluded": ["unpaired_cysteine", "N-linked_glycosylation", "deamidation_NG_NS", "isomerization_DG"]}, "count": 10}

---

## [384] source=multitask_sft_big

**USER:** Design 8 de-novo RNA aptamers targeting human Alpha-thrombin (PDB: 1HAP). The aptamers must be 30 to 45 nucleotides long, with predicted binding affinity Kd < 50 nM. They should fold into a stable stem-loop or hairpin motif with predicted minimum free energy (ΔG) between -15.0 and -5.0 kcal/mol at 37°C. Avoid homopolymeric stretches of more than 3 consecutive guanines (poly-G <= 3) to prevent nonspecific aggregation.

**ASSISTANT:** {"stage": "generate", "target": "Human Alpha-Thrombin (PDB: 1HAP)", "scaffold_policy": "de_novo", "property_envelope": {"length": [30, 45], "predicted_Kd_nM": "< 50", "mfe_delta_G_kcal_per_mol": [-15.0, -5.0], "motif": "stem-loop/hairpin", "max_consecutive_G": 3}, "count": 8}

---

## [385] source=multitask_sft_big

**USER:** Design 10 novel de-novo CDR-H3 loops targeting human IL-13 (PDB: 1IJZ) using the human VH3-23 framework. Keep CDR-H1, CDR-H2, and all framework residues fixed. The CDR-H3 length should be restricted to 11-15 residues, avoid N-linked glycosylation (NxS/T) and unpaired cysteines, maintain a net charge between 0 and +2 at pH 7.4, and exhibit low predicted hydrophobic patch area for optimal developability.

**ASSISTANT:** {"stage": "generate", "target": {"name": "human IL-13", "pdb_id": "1IJZ"}, "scaffold_policy": {"framework": "VH3-23", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3"}, "property_envelope": {"cdr_h3_length": [11, 15], "net_charge_ph7_4": [0, 2], "excluded_motifs": ["N[^P][ST]", "C"], "developability_filters": {"hydrophobic_patches": "low"}}, "count": 10}

---

## [386] source=multitask_sft_big

**USER:** Design 20 novel macrocyclic peptide binders targeting the p53-binding pocket of MDM2 to inhibit the MDM2-p53 protein-protein interaction. The peptides should have a length of 8 to 14 amino acids, utilize head-to-tail or hydrocarbon staple cyclization, incorporate at least one non-canonical or D-amino acid for proteolytic stability, exhibit molecular weight between 900 and 1600 Da, clogP between -1.0 and 3.5, and achieve predicted binding affinity (Kd) < 100 nM.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding cleft)", "scaffold_policy": "Macrocyclic peptide (8-14 amino acids; head-to-tail backbone or hydrocarbon stapling; at least 1 non-canonical/D-amino acid)", "property_envelope": {"molecular_weight": "900 - 1600 Da", "clogP": "-1.0 to 3.5", "predicted_binding_affinity": "Kd < 100 nM", "proteolytic_stability": "high"}, "count": 20}

---

## [387] source=multitask_sft_big

**USER:** Design 15 de novo macrocyclic peptide inhibitors targeting the human Keap1 Kelch domain (UniProt: Q14145) to competitively disrupt the Nrf2-Keap1 interaction. Peptides should have a cyclic backbone (head-to-tail or thioether-cyclized) of 6 to 12 residues, incorporate canonical and non-canonical residues, maintain a molecular weight between 800 and 1500 Da, clogP between -1.5 and 2.5, polar surface area (tPSA) under 450 Å², and an estimated binding Kd < 100 nM.

**ASSISTANT:** {"stage": "generate", "target": "Keap1 Kelch domain (UniProt: Q14145)", "scaffold_policy": "Macrocyclic peptide (head-to-tail or thioether bridge), length 6-12 amino acids, allowing non-canonical residues", "property_envelope": {"molecular_weight": "800 - 1500 Da", "clogP": "-1.5 - 2.5", "tPSA": "< 450 \u00c5\u00b2", "Kd": "< 100 nM"}, "count": 15}

---

## [388] source=multitask_sft_big

**USER:** I need de novo designed RNA aptamers targeting the catalytic domain of human PCSK9 (UniProt: Q8NBP7). Please generate 10 candidate RNA sequences, each between 35 and 45 nucleotides in length. Ensure they have a predicted binding affinity Kd < 50 nM, secondary structure minimum free energy (MFE) <= -12 kcal/mol, GC content between 40% and 60%, and no homopolymer tracts of G or U longer than 3 nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human PCSK9 catalytic domain (UniProt: Q8NBP7)", "scaffold_policy": null, "property_envelope": {"length": {"min": 35, "max": 45}, "affinity_kd_nM": {"max": 50}, "mfe_kcal_mol": {"max": -12.0}, "gc_content": {"min": 0.4, "max": 0.6}, "max_homopolymer_run": {"G": 3, "U": 3}}, "count": 10}

---

## [389] source=multitask_sft_big

**USER:** Please design 10 de novo RNA aptamer sequences targeting human VEGF-165 (Vascular Endothelial Growth Factor). The sequences should be 35 to 45 nucleotides in length, show high predicted binding affinity with a Kd below 50 nM, maintain a predicted secondary structure minimum free energy (MFE) <= -12.0 kcal/mol at 37°C, have a GC content between 40% and 60%, and contain no homopolymer tracts longer than 4 consecutive nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165", "scaffold_policy": "fully de novo generation without static primer binding arms; length between 35 and 45 nucleotides; max homopolymer length <= 4", "property_envelope": {"length_nt": {"min": 35, "max": 45}, "affinity_Kd_nM": {"max": 50}, "mfe_kcal_mol": {"max": -12.0}, "gc_content_percent": {"min": 40.0, "max": 60.0}, "max_homopolymer_run": 4}, "count": 10}

---

## [390] source=multitask_sft_big

**USER:** Design 20 de novo macrocyclic peptides targeting the p53-interaction pocket of human MDM2 (PDB: 1YCR). Peptides should be 8–12 amino acids in length, cyclized via head-to-tail backbone amide bonds or a disulfide bridge, and must present hydrophobic side chains mimicking the critical p53 triad (Phe19, Trp23, Leu26). Filter for predicted binding affinity Kd < 50 nM, molecular weight under 1600 Da, net charge between -1 and +2, and high predicted serum/protease stability.

**ASSISTANT:** {"stage": "generate", "target": "human MDM2 p53-binding pocket (PDB: 1YCR)", "scaffold_policy": "macrocyclic peptide backbone (8-12 residues, head-to-tail lactam or disulfide cyclization, displaying Phe-Trp-Leu-mimicking pharmacophore)", "property_envelope": {"peptide_length": "8-12 amino acids", "predicted_Kd": "< 50 nM", "molecular_weight": "< 1600 Da", "net_charge": "[-1, 2]", "protease_stability": "high"}, "count": 20}

---

## [391] source=multitask_sft_big

**USER:** Design 50 novel small molecules targeting human dopamine D2 receptor that optimize logP between 2.0 and 3.2 and mitigate cardiotoxicity by ensuring a clean hERG safety profile with an IC50 > 30 µM (pIC50 < 4.5), while keeping molecular weight under 450 Da.

**ASSISTANT:** {"stage": "generate", "target": "Dopamine D2 receptor", "scaffold_policy": "novel", "property_envelope": {"logP": {"min": 2.0, "max": 3.2}, "hERG_pIC50": {"max": 4.5}, "hERG_IC50_uM": {"min": 30.0}, "MW": {"max": 450}}, "count": 50}

---

## [392] source=multitask_sft_big

**USER:** Design 8 de novo RNA aptamers targeting human VEGF-165 (UniProt: P15692). The sequences should be 35 to 45 nucleotides long, with predicted binding affinity Kd < 20 nM. The secondary structure should feature stable stem-loop motifs with a folding free energy (ΔG at 37°C) between -12.0 and -6.0 kcal/mol, a GC content between 40% and 60%, and no homopolymer runs longer than 4 consecutive identical nucleotides.

**ASSISTANT:** {"stage": "generate", "target": "Human Vascular Endothelial Growth Factor A (VEGF-165, UniProt: P15692)", "scaffold_policy": "de novo RNA sequence design; length 35-45 nt; avoid homopolymer tracts > 4 nt", "property_envelope": {"binding_affinity_kd_nM": "< 20", "folding_delta_G_37C_kcal_per_mol": [-12.0, -6.0], "gc_content_percent": [40, 60], "max_homopolymer_run": 4}, "count": 8}

---

## [393] source=multitask_sft_big

**USER:** Design 30 novel linkers connecting a VHL ligand (phenolic attachment vector) to a BRD4 inhibitor (JQ1 carboxylate-derived vector). The linkers must span between 8 and 14 contiguous atoms, contain semi-rigid elements such as piperazines, spirocycles, or azetidines to balance entropy and flexibility, maintain linker-specific cLogP between 0.5 and 2.5, TPSA between 20 and 80 Å², and have no more than 7 rotatable bonds. Avoid linear PEG chains longer than 3 units and omit hydrolytically unstable groups like esters.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC", "scaffold_policy": "keep fixed warhead (JQ1-derivative) and E3 recruiter (VHL ligand); perform de-novo linker design between specified exit vectors", "property_envelope": {"linker_chain_length": "8-14 atoms", "clogP": "0.5 - 2.5", "tpsa": "20 - 80 \u00c5\u00b2", "rotatable_bonds": "<= 7", "preferred_motifs": ["piperazine", "azetidine", "spirocycle"], "unwanted_motifs": ["ester", "PEG_chain_gt_3"]}, "count": 30}

---

## [394] source=multitask_sft_big

**USER:** Generate 25 novel, synthetically accessible linkers to connect our BTK inhibitor warhead (attachment vector at terminal primary amine) to a Cereblon (CRBN) ligand (exit vector at pomalidomide 4-position). Linker length must span 8 to 14 heavy atoms and incorporate at least one semi-rigid motif (e.g., piperazine, piperidine, or azetidine) to avoid purely floppy PEG/alkyl chains. Target property envelope: linker-only MW < 250 Da, whole PROTAC cLogP between 3.0 and 5.5, overall TPSA < 180 Å², and strictly exclude hydrolyzable esters, hydrazones, and reactive functional groups.

**ASSISTANT:** {"stage": "generate", "target": "BTK / CRBN PROTAC linkers", "scaffold_policy": "bifunctional linker design connecting BTK warhead to CRBN recruiter with semi-rigid cyclic amine motifs (piperazine, piperidine, azetidine)", "property_envelope": {"linker_heavy_atom_count": [8, 14], "linker_molecular_weight": "<250", "clogp": [3.0, 5.5], "tpsa": "<180", "unwanted_substructures": ["ester", "hydrazone", "reactive_warheads"]}, "count": 25}

---

## [395] source=multitask_sft_big

**USER:** Design 50 novel PROTAC linkers connecting a BRD4-targeting JQ1 carboxylic acid warhead to a VHL E3 ligase recruiter (VH032). Linker length should range between 8 and 16 linear atoms. Avoid simple, unstructured PEG-only or purely aliphatic chains; instead, incorporate rigidifying motifs such as piperazines, piperidines, spirocycles, or alkynes to promote stable ternary complex formation. The full PROTAC conjugates should have a molecular weight under 1050 Da, clogP between 2.0 and 5.0, TPSA < 210 Å², and rotatable bond count < 15 to preserve drug-like permeability and synthetic tractability.

**ASSISTANT:** {"stage": "generate", "target": "BRD4 / VHL PROTAC", "scaffold_policy": "Connect JQ1 warhead and VH032 ligand at designated exit vectors; linkers must incorporate rigidifying heterocyclic or sp3/spirocyclic cores, avoiding pure unbranched PEG or polymethylene chains.", "property_envelope": {"linker_atom_length": "8-16 atoms", "full_protac_mw": "< 1050 Da", "clogP": "2.0 - 5.0", "tpsa": "< 210 \u00c5\u00b2", "rotatable_bonds": "< 15"}, "count": 50}

---

## [396] source=multitask_sft_big

**USER:** Please design 5 de novo RNA aptamers targeting human VEGF-165 (UniProt: P15692). Sequences should be between 40 and 50 nucleotides in length, with a predicted minimum free energy (ΔG) below -12.0 kcal/mol at 37°C, GC content between 45% and 60%, and no homopolymer runs of more than 3 consecutive guanines (poly-G < 4).

**ASSISTANT:** {"stage": "generate", "target": "Human VEGF-165 (UniProt: P15692)", "scaffold_policy": null, "property_envelope": {"sequence_length": {"min": 40, "max": 50}, "gc_content_percent": {"min": 45.0, "max": 60.0}, "folding_mfe_dG_kcal_mol": {"max": -12.0}, "max_homopolymer_g": 3}, "count": 5}

---

## [397] source=multitask_sft_big

**USER:** Design 50 de novo small-molecule scaffolds suitable for targeting the ATP-binding pocket of human CDK2. The designs should feature novel hinge-binding motifs distinct from standard purine and quinazoline cores, possessing at least one hydrogen bond donor and one acceptor properly oriented for hinge interaction. Keep the scaffold cores relatively rigid with no more than 3 rotatable bonds, a molecular weight between 300 and 450 Da, cLogP between 1.5 and 3.5, and TPSA under 100 Å².

**ASSISTANT:** {"stage": "generate", "target": "CDK2 ATP-binding site", "scaffold_policy": {"type": "novel", "exclude_classes": ["purine", "quinazoline"], "required_motifs": ["hinge_binding_donor_acceptor"]}, "property_envelope": {"molecular_weight": {"min": 300.0, "max": 450.0}, "clogp": {"min": 1.5, "max": 3.5}, "tpsa": {"max": 100.0}, "rotatable_bonds": {"max": 3}}, "count": 50}

---

## [398] source=multitask_sft_big

**USER:** Design 50 novel core scaffolds suitable for ATP-competitive kinase inhibition that deviate from standard chemotypes like purines, pyrrolopyrimidines, and 4-anilinoquinazolines. The scaffolds should feature suitable vectors for hinge-binding hydrogen bond donor/acceptor pairs, possess drug-like properties (MW 300-420 Da, clogP 1.5-3.5, TPSA 60-90 Å², HBD 1-2, HBA 2-5, rotatable bonds <= 6), maintain synthetic tractability with SA score < 4.0, and be free of PAINS or reactive warheads.

**ASSISTANT:** {"stage": "generate", "target": "kinase ATP-binding site", "scaffold_policy": {"novelty": "de_novo", "excluded_substructures": ["purine", "pyrrolo[2,3-d]pyrimidine", "4-anilinoquinazoline"]}, "property_envelope": {"molecular_weight": {"min": 300, "max": 420}, "clogP": {"min": 1.5, "max": 3.5}, "tpsa": {"min": 60, "max": 90}, "hbd": {"min": 1, "max": 2}, "hba": {"min": 2, "max": 5}, "rotatable_bonds": {"max": 6}, "synthetic_accessibility": {"max": 4.0}, "pains_filter": true}, "count": 50}

---

## [399] source=multitask_sft_big

**USER:** Design 15 novel core scaffolds for inhibiting LRRK2 at the ATP-binding hinge region. We need new chemical matter, so explicitly avoid common bis-anilino pyrimidine, indolinone, and pyrazolopyrimidine chemotypes. Molecules must exhibit CNS-compliant/drug-like features: MW 300-450 Da, cLogP 2.0-3.5, TPSA between 50 and 90 Å², HBD <= 2, HBA <= 6, and rotatable bonds <= 6, with high predicted synthetic accessibility.

**ASSISTANT:** {"stage": "generate", "target": "LRRK2", "scaffold_policy": {"action": "novelty_exploration", "exclude_scaffolds": ["bis-anilino pyrimidine", "indolinone", "pyrazolopyrimidine"], "required_pharmacophore": "hinge-binding donor-acceptor motif"}, "property_envelope": {"molecular_weight": {"min": 300, "max": 450}, "clogp": {"min": 2.0, "max": 3.5}, "tpsa": {"min": 50, "max": 90}, "hbd": {"max": 2}, "hba": {"max": 6}, "rotatable_bonds": {"max": 6}, "synthetic_accessibility": "high"}, "count": 15}

---

## [400] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like core scaffolds targeting the ATP-binding pocket of EGFR T790M/C797S. Avoid classic quinazoline or pyrimidine-based hinge-binder chemotypes. Target properties: MW 320-450 Da, LogP 2.0-3.5, TPSA 60-100 Å², HBD <= 2, HBA 3-7, and at least one exit vector suitable for medicinal chemistry elaboration.

**ASSISTANT:** {"stage": "generate", "target": "EGFR T790M/C797S", "scaffold_policy": {"type": "de_novo", "exclude": ["quinazoline", "pyrimidine"], "binding_mode": "ATP-competitive hinge binder"}, "property_envelope": {"mw": {"min": 320, "max": 450}, "logP": {"min": 2.0, "max": 3.5}, "tpsa": {"min": 60.0, "max": 100.0}, "hbd": {"max": 2}, "hba": {"min": 3, "max": 7}}, "count": 50}

---

## [401] source=multitask_sft_big

**USER:** Design 20 novel de-novo macrocyclic peptide inhibitors targeting the interaction interface of human PD-L1 (PDB: 5J89) to disrupt PD-1/PD-L1 binding. The peptides should be 9 to 13 residues in length, cyclized via head-to-tail amide bond or a stable thioether/hydrocarbon staple. Allowed residues include canonical amino acids and standard non-canonical residues (e.g., N-methyl amino acids, D-amino acids). Filter for candidates with predicted binding affinity Kd < 100 nM, molecular weight between 900 and 1600 Da, cLogP between -1.0 and 4.0, and topological polar surface area (tPSA) < 450 Å² to favor moderate solubility and membrane permeability.

**ASSISTANT:** {"stage": "generate", "target": "Human PD-L1 (PD-1 interaction interface, reference PDB: 5J89)", "scaffold_policy": "Macrocyclic peptides of 9\u201313 residues, cyclized via head-to-tail or side-chain staple (thioether or hydrocarbon), permitting natural, D-, and N-methylated amino acids", "property_envelope": {"molecular_weight": "900 - 1600 Da", "clogP": "[-1.0, 4.0]", "tPSA": "< 450 \u00c5\u00b2", "predicted_affinity": "Kd < 100 nM", "sequence_length": "9-13 residues"}, "count": 20}

---

## [402] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small molecules optimized for hERG safety with an IC50 > 10 µM (pIC50 < 5.0) and a balanced lipophilicity profile (cLogP between 1.5 and 3.0). The candidates should also conform to standard oral bioavailability rules: MW < 450 Da, TPSA between 60 and 120 Å², and no more than 5 hydrogen bond donors.

**ASSISTANT:** {"stage": "generate", "target": "hERG (antitarget)", "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "molecular_weight": {"max": 450}, "tpsa": {"min": 60, "max": 120}, "hbd": {"max": 5}}, "count": 50}

---

## [403] source=multitask_sft_big

**USER:** Design 5 novel RNA aptamers from scratch targeting the human Interleukin-6 (IL-6) protein to block its receptor binding interface. The candidates should be 40 to 60 nucleotides long, maintain a GC content between 45% and 60%, exhibit a predicted melting temperature (Tm) above 55°C, have at least one stable hairpin/stem-loop motif, and show high estimated target affinity with Kd < 50 nM.

**ASSISTANT:** {"stage": "generate", "target": "Human Interleukin-6 (IL-6)", "scaffold_policy": "de_novo", "property_envelope": {"length": {"min": 40, "max": 60, "unit": "nt"}, "gc_content": {"min": 0.45, "max": 0.6}, "melting_temperature_celsius": {"min": 55}, "predicted_kd_nm": {"max": 50}, "secondary_structure": "at least one hairpin/stem-loop motif"}, "count": 5}

---

## [404] source=multitask_sft_big

**USER:** Design 50 de novo linkers connecting a JQ1-derived BRD4 warhead (amide exit vector) to a VHL E3 ligase ligand (anchored at the terminal ether/alkyl carbon). We want to avoid conventional floppy alkyl or extended PEG chains in favor of rigidified, sp3-enriched bioisosteric linkers (e.g., incorporating piperazine, bicyclo[1.1.1]pentane, azetidine, or oxetane motifs) to enhance degradation cooperativity. The linker fragment itself should have a molecular weight between 100 and 280 Da, linker clogP between 0.0 and 2.5, no more than 6 rotatable bonds, TPSA under 75 Å², and Fsp3 >= 0.45.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC linker", "scaffold_policy": "Bifunctional linker joining fixed BRD4 warhead (acyl attachment) and VHL ligand (alkyl attachment); prohibit homobifunctional PEG/pure polyalkyl chains", "property_envelope": {"linker_mw": [100, 280], "linker_clogp": [0.0, 2.5], "linker_nrot": "<= 6", "linker_tpsa": "<= 75", "fsp3": ">= 0.45"}, "count": 50}

---

## [405] source=multitask_sft_big

**USER:** Generate 50 de-novo CDR-H3 loop sequences grafted onto the humanized Trastuzumab VH framework targeting the HER2 extracellular domain IV (PDB ID: 1N8Z). The CDR-H3 loops must range from 12 to 16 residues in length (Chothia definition: H95-H102). Filter candidates to ensure net charge is between -1.0 and +2.0 at pH 7.4, maximum CDR hydrophobicity does not exceed 35%, and sequences are free of labile sequence liabilities including NG, NS deamidation and DG isomerization motifs.

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2 extracellular domain", "pdb_id": "1N8Z", "epitope_region": "Domain IV"}, "scaffold_policy": {"framework": "Trastuzumab VH (IGHV3-66)", "region_to_design": "CDR-H3", "definition": "Chothia", "framework_fixed": true}, "property_envelope": {"cdr_length_range": [12, 16], "net_charge_range": [-1.0, 2.0], "max_hydrophobic_fraction": 0.35, "forbidden_motifs": ["NG", "NS", "DG"]}, "count": 50}

---

## [406] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small molecules with low cardiotoxicity liability. Ensure predicted hERG pIC50 is below 5.0 (IC50 > 10 µM) and optimize lipophilicity with a calculated LogP between 1.5 and 3.0. Maintain molecular weight under 450 Da and TPSA between 60 and 120 Å².

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"logP": {"min": 1.5, "max": 3.0}, "hERG_pIC50": {"max": 5.0}, "hERG_IC50_uM": {"min": 10.0}, "MW": {"max": 450}, "TPSA": {"min": 60, "max": 120}}, "count": 50}

---

## [407] source=multitask_sft_big

**USER:** Design 40 novel linkers connecting our BTK warhead (linked at the piperidine nitrogen) to a CRBN pomalidomide ligand (linked at the 4-amino position). Linkers should span 8 to 16 atoms in length, avoid extended poly-PEG chains, and incorporate semi-rigid elements such as piperazines, spirocycles, or alkynes to reduce conformational entropy. Keep the final PROTAC MW under 1000, cLogP between 2.5 and 5.0, rotatable bonds under 18, and ensure high synthetic feasibility (SA score < 4.5).

**ASSISTANT:** {"stage": "generate", "target": "BTK-CRBN PROTAC", "scaffold_policy": {"type": "linker_design", "warhead_anchor": "piperidine nitrogen", "e3_ligand_anchor": "pomalidomide C4-amino", "linker_length_atoms": [8, 16], "structural_motifs": {"favored": ["piperazines", "spirocycles", "alkynes", "small heterocycles"], "disfavored": ["long flexible PEG chains", "unstable functional groups"]}}, "property_envelope": {"mw_max": 1000, "clogp_range": [2.5, 5.0], "n_rotatable_bonds_max": 18, "sa_score_max": 4.5}, "count": 40}

---

## [408] source=multitask_sft_big

**USER:** Design 20 novel macrocyclic peptides targeting the p53-binding pocket of MDM2 to disrupt the MDM2-p53 interaction. The peptides should be 8 to 12 residues in length, cyclized via a head-to-tail backbone amide bond or a stable hydrocarbon staple. Ensure the designs retain the critical hot-spot triad mimicry (Phe-Trp-Leu motif), maintain a molecular weight between 900 and 1500 Da, have a topological polar surface area (tPSA) under 320 Å², and exhibit predicted sub-micromolar binding affinity without relying on unstable disulfide bridges.

**ASSISTANT:** {"stage": "generate", "target": "MDM2 (p53-binding site)", "scaffold_policy": "Macrocyclic peptide (8-12 residues; head-to-tail lactam or hydrocarbon staple; non-disulfide cyclization; must incorporate Phe-Trp-Leu hot-spot mimicry)", "property_envelope": {"molecular_weight": "900-1500 Da", "tPSA": "<= 320 \u00c5\u00b2", "predicted_affinity": "< 1 \u00b5M", "metabolic_stability": "no labile disulfide bonds"}, "count": 20}

---

## [409] source=multitask_sft_big

**USER:** Generate 25 novel drug-like small molecules with balanced lipophilicity and minimal cardiac liability. The compounds should have a cLogP between 1.5 and 3.0, low hERG inhibition (predicted hERG pIC50 < 5.0, or IC50 > 10 µM), molecular weight under 450 Da, and TPSA between 60 and 120 Å² to minimize off-target toxicity while maintaining oral bioavailability.

**ASSISTANT:** {"stage": "generate", "target": null, "scaffold_policy": null, "property_envelope": {"clogp": {"min": 1.5, "max": 3.0}, "herg_pIC50": {"max": 5.0}, "herg_ic50_um": {"min": 10.0}, "mw": {"max": 450.0}, "tpsa": {"min": 60.0, "max": 120.0}}, "count": 25}

---

## [410] source=multitask_sft_big

**USER:** Design 50 de novo small-molecule drug candidates optimized for cardiovascular safety and oral bioavailability, specifically requiring low hERG liability (hERG pIC50 < 5.0 or IC50 > 10 µM), balanced lipophilicity (clogP between 1.5 and 3.0), MW <= 450 Da, and TPSA between 60 and 110 Å².

**ASSISTANT:** {"stage": "generate", "target": "hERG", "scaffold_policy": null, "property_envelope": {"clogP": [1.5, 3.0], "hERG_pIC50": "< 5.0", "MW": "<= 450", "TPSA": [60, 110]}, "count": 50}

---

## [411] source=multitask_sft_big

**USER:** We are designing PROTAC degraders targeting BRD4 using a JQ1-derived warhead (terminal carboxylate exit vector) and a VHL ligand (VH032 terminal amine exit vector). Please generate 20 novel, synthetically feasible bifunctional linkers to bridge these two exit vectors. The linkers should avoid standard linear PEG or alkyl-only chains and instead incorporate rigidifying or semi-rigid motifs (e.g., piperazines, piperidines, spirocycles, or alkynes) to reduce conformational flexibility. Desired linker contour length is between 6 and 14 atoms, linker molecular weight < 250 Da, linker LogP between 0.5 and 2.5, and no more than 7 rotatable bonds within the linker fragment.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL ternary complex (PROTAC linker)", "scaffold_policy": "Bifunctional linker connecting JQ1 warhead carboxylate and VH032 amine; restrict linear PEG/alkyl chains; enforce rigidifying cyclic/spiro/alkynyl motifs", "property_envelope": {"linker_atom_length": "6-14", "linker_mw": "<250", "linker_clogP": "0.5-2.5", "linker_rotatable_bonds": "<=7"}, "count": 20}

---

## [412] source=multitask_sft_big

**USER:** Generate 50 novel, drug-like small-molecule scaffolds as prospective Type I kinase inhibitors targeting CDK2. The molecules must possess a novel hinge-binding core that is structurally distinct from standard aminopyrimidine, staurosporine, and purine chemotypes. Retain favorable oral drug-like properties: molecular weight between 350 and 480 Da, cLogP between 2.0 and 4.0, TPSA between 60 and 100 Å², at most 3 hydrogen bond donors, 4 to 8 hydrogen bond acceptors, no more than 6 rotatable bonds, and exclusion of PAINS or reactive functionalities.

**ASSISTANT:** {"stage": "generate", "target": {"gene_name": "CDK2", "class": "kinase", "inhibition_mode": "Type I (ATP-competitive)"}, "scaffold_policy": {"novelty": "high", "core_requirement": "novel hinge-binding motif", "forbidden_scaffolds": ["purine", "aminopyrimidine", "staurosporine", "pyrazolopyrimidine"]}, "property_envelope": {"molecular_weight": {"min": 350, "max": 480}, "clogp": {"min": 2.0, "max": 4.0}, "tpsa": {"min": 60.0, "max": 100.0}, "hbd": {"max": 3}, "hba": {"min": 4, "max": 8}, "rotatable_bonds": {"max": 6}, "filter_pains": true, "filter_reactive_groups": true}, "count": 50}

---

## [413] source=multitask_sft_big

**USER:** Design 10 de novo CDR-H3 loop sequences grafted onto a human IGHV3-23 / Trastuzumab heavy-chain framework to target the extracellular domain IV of HER2 (PDB: 1N8Z). Constrain CDR-H3 loop lengths to 12-16 amino acids. Generated designs must have predicted high binding affinity (pKd > 8.5), low hydrophobicity patch area, CamSol solubility score > 1.0, and be free of sequence liabilities including unpaired cysteines, N-glycosylation sites (N-X-[S/T]), and deamidation/isomerization motifs (NG, NS, DG).

**ASSISTANT:** {"stage": "generate", "target": {"name": "HER2", "domain": "Extracellular domain IV", "pdb_id": "1N8Z"}, "scaffold_policy": {"framework": "IGHV3-23/IGHJ4 (Trastuzumab VH scaffold)", "fixed_regions": ["FR1", "CDR-H1", "FR2", "CDR-H2", "FR3", "FR4"], "design_region": "CDR-H3", "loop_length": [12, 16]}, "property_envelope": {"predicted_pKd": {"min": 8.5}, "camsol_score": {"min": 1.0}, "sequence_liabilities": {"unpaired_cysteines": false, "n_glycosylation": false, "motifs_excluded": ["NG", "NS", "DG"]}}, "count": 10}

---

## [414] source=multitask_sft_big

**USER:** Design 20 novel PROTAC linkers connecting a JQ1-derived BRD4 warhead (amine/carboxylate attachment point) to a VH032 VHL E3 ligase ligand (phenolic exit vector). The linkers should have an extended chain length of 8 to 14 heavy atoms, combine flexibility and rigidifying motifs (e.g., piperazine, alkynes, or small cycloalkyl rings) to reduce conformational entropy, avoid unstable motifs like hydrolyzable esters, maintain cLogP between 2.0 and 4.5, and keep total TPSA under 160 Å² to preserve cell permeability.

**ASSISTANT:** {"stage": "generate", "target": "BRD4-VHL PROTAC ternary complex", "scaffold_policy": {"linker_type": "bifunctional_connector", "attachment_point_warhead": "JQ1 carboxylic acid/amine exit vector", "attachment_point_e3": "VH032 phenolic oxygen vector", "linker_length_heavy_atoms": [8, 14], "preferred_motifs": ["piperazine", "PEG-like spacers", "alkynes", "saturated heterocycles"], "forbidden_motifs": ["ester", "azo", "hydrazone", "unstable acetal"]}, "property_envelope": {"cLogP": [2.0, 4.5], "TPSA": [0.0, 160.0], "rotatable_bonds": [4, 12]}, "count": 20}

---

## [415] source=multitask_sft_big

**USER:** Design 20 novel, conformationally constrained PROTAC linkers connecting a VHL ligand (VH032-derived exit vector at the terminal amine) and an AR antagonist warhead (enzalutamide-derived carboxylic acid exit vector). Linkers must have an effective linear chain length of 8 to 14 heavy atoms and incorporate semi-rigid motifs such as piperazine, piperidine, or azetidine to restrict rotational freedom. Linker molecular weight must be between 100 and 300 Da, with linker cLogP between 0.5 and 3.0, linker TPSA below 80 Å², and total PROTAC MW not exceeding 1050 Da. Avoid ester, peroxide, and hydrazone bonds.

**ASSISTANT:** {"stage": "generate", "target": "AR-VHL ternary complex (Androgen Receptor / VHL ligase)", "scaffold_policy": "Bifunctional linker generation between fixed VHL and AR warhead attachment points; linker backbone must incorporate rigidifying nitrogen heterocycles (piperazine, piperidine, azetidine); exclude labile bonds (esters, peroxides, hydrazones)", "property_envelope": {"linker_heavy_atom_path_length": "8-14", "linker_mw": [100, 300], "linker_clogp": [0.5, 3.0], "linker_tpsa": "<= 80", "total_protac_mw": "<= 1050"}, "count": 20}

---

