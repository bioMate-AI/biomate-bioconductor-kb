"""K2 configuration: topic queries, closed vocabularies, tiers. Frozen by docs/20261031_ALLATOM_KNOWLEDGE_SCALE_PREREG.md."""
OA = " AND OPEN_ACCESS:y AND HAS_FT:y"
QUERIES = [
    ("perm_cp", '("cyclic peptide" OR "cyclic peptides" OR macrocycle OR macrocycles OR macrocyclic) AND (permeability OR permeab* OR PAMPA OR Caco-2)' + OA),
    ("oral_bio", '("cyclic peptide" OR macrocycle OR macrocyclic) AND ("oral bioavailability" OR "oral absorption" OR orally)' + OA),
    ("nmethyl", '("N-methylation" OR "N-methylated" OR "backbone methylation") AND (peptide OR cyclic) AND (permeab* OR conformation OR stability)' + OA),
    ("chameleon", '(chameleon* OR "intramolecular hydrogen bond*" OR "polar surface area") AND ("cyclic peptide" OR macrocycle OR macrocyclic)' + OA),
    ("bro5", '("beyond rule of 5" OR "beyond the rule of five" OR bRo5 OR "rule of five") AND (macrocycle OR "cyclic peptide" OR peptide)' + OA),
    ("dresidue", '("D-amino acid" OR "D-amino acids" OR "D-residue" OR stereochemistry OR "non-canonical amino acid" OR "unnatural amino acid") AND ("cyclic peptide" OR macrocycle)' + OA),
    ("macrocyc_chem", '(macrocyclization OR macrocyclisation OR "head-to-tail" OR "stapled peptide" OR "peptide stapling" OR "lactam bridge" OR "thioether") AND (peptide OR peptides)' + OA),
    ("stability", '("cyclic peptide" OR "macrocyclic peptide") AND (proteolysis OR "proteolytic stability" OR "metabolic stability" OR "plasma stability" OR protease)' + OA),
    ("integrin", '(integrin OR RGD OR "alphavbeta6" OR "avb6" OR "alpha v beta 6") AND ("cyclic peptide" OR macrocycle OR macrocyclic)' + OA),
    ("pdl1_ppi", '("PD-L1" OR "PD-1" OR "protein-protein interaction") AND ("macrocyclic peptide" OR "cyclic peptide" OR "macrocycle")' + OA),
    ("grpr_gpcr", '(GRPR OR bombesin OR somatostatin OR "melanocortin" OR GPCR) AND ("cyclic peptide" OR "cyclic peptides")' + OA),
    ("sar_cp", '("structure-activity relationship" OR SAR) AND ("cyclic peptide" OR "macrocyclic peptide") AND (permeab* OR affinity OR potency)' + OA),
    ("drugs_cp", '("approved" OR "clinical") AND ("cyclic peptide" OR "macrocyclic peptide") AND (drug OR therapeutics)' + OA),
    ("ring_size", '("ring size" OR "macrocycle size" OR "ring-size") AND ("cyclic peptide" OR macrocycle)' + OA),
]
PROPERTIES = ["permeability", "oral_bioavailability", "binding_affinity", "selectivity", "solubility",
              "metabolic_stability", "proteolytic_stability", "conformation_chameleonicity", "renal_pk",
              "toxicity_liability", "synthesis_macrocyclization", "other"]
SUBSTRUCTURES = ["n_methylation", "d_residue_stereo", "ring_size_topology", "noncanonical_residue",
                 "physchem_tpsa_hbd_logp_mw", "ihb_conformation", "side_chain_motif_pharmacophore",
                 "linker_terminus_macrocyclization_chem", "charge_polarity", "other"]
DIRECTIONS = ["increases", "decreases", "no_effect", "conditional", "qualitative"]
TIER_BY_PUBTYPE = {"research-article": "T1", "review-article": "T2", "review": "T2"}
MODEL = "Qwen/Qwen3-8B"
QUOTE_MIN_WORDS, QUOTE_MAX_WORDS = 6, 30
PASSAGE_WORDS, PASSAGE_OVERLAP = 800, 80
TOPIC_RE = (r"(cyclic peptide|macrocycl|cyclic|permeab|N-methyl|methylat|bioavailab|chameleon|hydrogen bond|"
            r"TPSA|polar surface|D-amino|stereo|RGD|integrin|ring size|stapl|lactam|proteoly|stability)")
