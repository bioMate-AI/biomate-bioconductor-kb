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

# ---- Amendment A1 (coordinator request, before any run): three knowledge topics --------------------------------------
TOPICS = ["sar_rule", "structure_property", "prior_work", "target_structure"]
LESSON_TYPES = ["hit_rate", "failure_mode", "design_principle", "method_comparison", "optimisation_outcome"]
STRUCT_FEATURES = ["binding_mode", "key_contact", "bound_conformation", "turn_type", "hotspot_residue"]
TARGET_TERMS = {
    "a4b1": '"VLA-4" OR "alpha4beta1" OR "α4β1"', "a4b7": '"alpha4beta7" OR "α4β7" OR "integrin a4b7"',
    "avb6": '"alphavbeta6" OR "αvβ6" OR "avb6"', "baff": 'BAFF OR BLyS OR TNFSF13B', "c5": '"complement C5" OR "C5 inhibitor"',
    "cd20": 'CD20 OR MS4A1', "cd40": 'CD40', "fcrn": 'FcRn OR FCGRT', "il17a": '"IL-17A"', "il17f": '"IL-17F"',
    "il23": '"IL-23" OR IL23', "il2ra": '"IL-2Rα" OR CD25 OR "IL-2 receptor alpha"', "il6r": '"IL-6 receptor" OR "IL-6R"',
    "lfa1": 'LFA-1 OR "alphaLbeta2" OR "αLβ2"', "pdl1": '"PD-L1" OR CD274', "tnfa": '"TNF-alpha" OR "TNF-α" OR TNFα'}
TARGETS = list(TARGET_TERMS)
QUERIES += [
    ("fund_desolv", '("desolvation" OR "membrane permeation" OR "solubility-diffusion" OR "passive diffusion") AND (peptide OR macrocycle OR macrocyclic)' + OA),
    ("fund_3dpsa", '("3D polar surface area" OR "solvent accessible polar surface" OR "conformational ensemble" OR "molecular dynamics") AND ("cyclic peptide" OR macrocycle) AND permeab*' + OA),
    ("fund_amide", '("cis amide" OR "cis-trans isomerization" OR "peptide bond isomerization" OR "cis peptide bond") AND ("cyclic peptide" OR "N-methyl*")' + OA),
    ("fund_strain", '("ring strain" OR "conformational strain" OR "conformational preference" OR NOE) AND ("cyclic peptide" OR macrocycle)' + OA),
    ("fund_aggreg", '(aggregation OR "self-assembly" OR "solubility") AND ("cyclic peptide" OR macrocycle OR "macrocyclic peptide")' + OA),
    ("camp_design", '("de novo design" OR "computational design" OR "design") AND ("macrocyclic peptide" OR "cyclic peptide") AND ("hit rate" OR "success rate" OR "experimentally validated" OR binders)' + OA),
    ("camp_display", '("mRNA display" OR "phage display" OR RaPID OR "DNA-encoded") AND ("macrocyclic peptide" OR "cyclic peptide") AND (selection OR hits OR optimization)' + OA),
    ("camp_opt", '("lead optimization" OR "optimization campaign" OR "structure-based optimization") AND ("cyclic peptide" OR "macrocyclic peptide")' + OA),
    ("camp_fail", '(failed OR failure OR limitations OR "lessons learned" OR challenges) AND ("cyclic peptide design" OR "macrocycle design" OR "peptide macrocycle")' + OA),
    ("camp_ml", '("machine learning" OR "deep learning" OR generative) AND ("cyclic peptide" OR "macrocyclic peptide") AND (design OR permeability)' + OA),
]
for _t, _terms in TARGET_TERMS.items():
    QUERIES.append((f"tgt_{_t}", f'({_terms}) AND (peptide OR macrocycl* OR "cyclic") AND ("crystal structure" OR "binding mode" OR NMR OR docking OR "co-crystal")' + OA))
_SP = {"chameleon", "bro5", "ring_size", "stability", "perm_cp", "oral_bio", "nmethyl", "dresidue", "macrocyc_chem"}
QUERY_TOPICS = {}
for _qid, _ in QUERIES:
    if _qid.startswith("fund_"):
        QUERY_TOPICS[_qid] = ["structure_property"]
    elif _qid.startswith("camp_") or _qid == "drugs_cp":
        QUERY_TOPICS[_qid] = ["prior_work"]
    elif _qid.startswith("tgt_") or _qid in ("integrin", "pdl1_ppi", "grpr_gpcr"):
        QUERY_TOPICS[_qid] = ["target_structure", "sar_rule"]
    elif _qid in ("chameleon", "ring_size", "stability"):
        QUERY_TOPICS[_qid] = ["structure_property", "sar_rule"]
    else:
        QUERY_TOPICS[_qid] = ["sar_rule"]
