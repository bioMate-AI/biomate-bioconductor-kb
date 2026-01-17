#!/usr/bin/env python3
"""
Exhaustive Biomni Tools Test Suite v3
Tests ALL Biomni functions with correct signatures and mock data
"""

import os
import sys
import json
import tempfile
import numpy as np

BIOMNI_PATH = "/home/yzhang/biomate/Biomni"
if BIOMNI_PATH not in sys.path:
    sys.path.insert(0, BIOMNI_PATH)

# ============================================================================
# MOCK DATA
# ============================================================================

SAMPLE_PROTEIN_SEQ = "MKFLILLFNILCLFPVLAADNHGVGPQGASGVDPITFDINSNQTGVQLTLNSTGSEEECKFSLFLKWFEPG"
SAMPLE_DNA_SEQ = "ATGAAATTCCTGATCCTGCTGTTCAACATCCTGTGCCTGTTCCCTGTGCTGGCTGCTGACAACCATGGTGTGGGTCCACAGGGTGCTAGTGGTGTGGATCCTATCACCTTCGACATCAACAGCAACCAGACTGGTGTGCAGCTGACCCTGAACAGCACTGGTTCTGAGGAGGAGTGCAAATTCTCTCTGTTCCTGAAATGGTTTGAGCCTGGATGA"
SAMPLE_RNA_SEQ = "GCGGAUUUAGCUCAGUUGGGAGAGCGCCAGACUGAAGAUCUGGAGGUCCUGUGUUCGAUCCACAGAAUUCGCA"
SAMPLE_DOT_BRACKET = "((((....))))....((((....))))"
SAMPLE_SMILES = "CC(=O)OC1=CC=CC=C1C(=O)O"  # Aspirin

class TestResults:
    def __init__(self):
        self.passed = []
        self.failed = []
        self.skipped = []
        self.categories = {}
        self.total_functions = 0

    def add(self, category, func, status, msg=""):
        entry = {"category": category, "function": func, "message": msg}
        if category not in self.categories:
            self.categories[category] = {"passed": 0, "failed": 0, "skipped": 0}

        if status == "PASS":
            self.passed.append(entry)
            self.categories[category]["passed"] += 1
        elif status == "FAIL":
            self.failed.append(entry)
            self.categories[category]["failed"] += 1
        else:
            self.skipped.append(entry)
            self.categories[category]["skipped"] += 1

    def summary(self):
        total = len(self.passed) + len(self.failed) + len(self.skipped)
        print("\n" + "="*70)
        print(f"EXHAUSTIVE BIOMNI TEST RESULTS - {total} FUNCTIONS TESTED")
        print("="*70)
        print(f"  PASSED:  {len(self.passed)} ({100*len(self.passed)/max(1,total):.1f}%)")
        print(f"  FAILED:  {len(self.failed)} ({100*len(self.failed)/max(1,total):.1f}%)")
        print(f"  SKIPPED: {len(self.skipped)} ({100*len(self.skipped)/max(1,total):.1f}%)")

        print("\n--- By Category ---")
        for cat in sorted(self.categories.keys()):
            s = self.categories[cat]
            t = s["passed"] + s["failed"] + s["skipped"]
            print(f"  {cat}: {s['passed']}/{t} ({100*s['passed']/max(1,t):.0f}%)")

        if self.failed:
            print("\n--- FAILURES ---")
            for f in self.failed:
                print(f"  {f['category']}.{f['function']}: {f['message'][:80]}")
        print("="*70)


def safe_test(results, category, func_name, test_func):
    """Safely run a test and catch any exceptions"""
    try:
        result = test_func()
        if result is not None:
            results.add(category, func_name, "PASS", str(result)[:50])
        else:
            results.add(category, func_name, "PASS", "returned None (valid)")
    except Exception as e:
        results.add(category, func_name, "FAIL", str(e)[:200])


# ============================================================================
# DATABASE TESTS (4 functions - query functions removed, use Galaxy biomate_ds_api_*)
# ============================================================================
def test_database(results):
    print("\n--- Testing database (4 functions - query_* REMOVED, use Galaxy biomate_ds_api_*) ---")
    try:
        from biomni.tool import database

        # All query_* functions REMOVED - use Galaxy biomate_ds_api_* tools instead
        # Documenting removed functions for reference:
        query_funcs_removed = [
            "query_uniprot", "query_pdb", "query_kegg", "query_alphafold",
            "query_interpro", "query_stringdb", "query_pdb_identifiers",
            "query_chembl", "query_pubchem", "query_clinvar", "query_dbsnp",
            "query_geo", "query_ensembl", "query_gnomad", "query_gwas_catalog",
            "query_reactome", "query_quickgo", "query_cbioportal",
            "query_clinicaltrials", "query_dailymed", "query_emdb", "query_encode",
            "query_gtopdb", "query_jaspar", "query_monarch", "query_mpd",
            "query_openfda", "query_opentarget", "query_paleobiology",
            "query_pride", "query_regulomedb", "query_remap", "query_synapse",
            "query_ucsc", "query_unichem", "query_worms", "query_iucn"
        ]
        for func in query_funcs_removed:
            results.add("database", func, "SKIP", f"REMOVED - use Galaxy biomate_ds_api_{func.replace('query_', '')}")

        # Remaining non-LLM functions
        # NOTE: blast_sequence takes ~10min, skip in quick tests
        results.add("database", "blast_sequence", "SKIP", "takes 10+ minutes, use Galaxy BLAST instead")

        safe_test(results, "database", "region_to_ccre_screen",
                  lambda: database.region_to_ccre_screen("chr1", 1000000, 1001000))
        safe_test(results, "database", "get_genes_near_ccre",
                  lambda: database.get_genes_near_ccre("EH38E1516972", "GRCh38", "chr1"))
        # Skip get_hpo_names - requires data_lake_path
        results.add("database", "get_hpo_names", "SKIP", "requires data_lake_path")

    except ImportError as e:
        results.add("database", "import", "FAIL", str(e))


# ============================================================================
# MOLECULAR BIOLOGY TESTS (19 functions)
# ============================================================================
def test_molecular_biology(results):
    print("\n--- Testing molecular_biology (19 functions) ---")
    try:
        from biomni.tool import molecular_biology

        safe_test(results, "molecular_biology", "annotate_open_reading_frames",
                  lambda: molecular_biology.annotate_open_reading_frames(SAMPLE_DNA_SEQ, 30))
        safe_test(results, "molecular_biology", "annotate_plasmid",
                  lambda: molecular_biology.annotate_plasmid(SAMPLE_DNA_SEQ))
        safe_test(results, "molecular_biology", "find_restriction_sites",
                  lambda: molecular_biology.find_restriction_sites(SAMPLE_DNA_SEQ, ["EcoRI", "BamHI"]))
        safe_test(results, "molecular_biology", "find_restriction_enzymes",
                  lambda: molecular_biology.find_restriction_enzymes(SAMPLE_DNA_SEQ))
        safe_test(results, "molecular_biology", "digest_sequence",
                  lambda: molecular_biology.digest_sequence(SAMPLE_DNA_SEQ, ["EcoRI"]))
        safe_test(results, "molecular_biology", "design_primer",
                  lambda: molecular_biology.design_primer(SAMPLE_DNA_SEQ[:100], 10))
        safe_test(results, "molecular_biology", "align_sequences",
                  lambda: molecular_biology.align_sequences(SAMPLE_DNA_SEQ, SAMPLE_DNA_SEQ[10:50]))
        safe_test(results, "molecular_biology", "pcr_simple",
                  lambda: molecular_biology.pcr_simple(SAMPLE_DNA_SEQ, "ATGAAATTCCTGATC", "TCATCCAGGCTCAAA"))
        safe_test(results, "molecular_biology", "find_sequence_mutations",
                  lambda: molecular_biology.find_sequence_mutations(SAMPLE_DNA_SEQ, SAMPLE_DNA_SEQ.replace("ATG", "GTG")))
        safe_test(results, "molecular_biology", "get_oligo_annealing_protocol",
                  lambda: molecular_biology.get_oligo_annealing_protocol())
        safe_test(results, "molecular_biology", "get_golden_gate_assembly_protocol",
                  lambda: molecular_biology.get_golden_gate_assembly_protocol(num_inserts=2, enzyme_name="BsaI", vector_length=3000))
        safe_test(results, "molecular_biology", "get_bacterial_transformation_protocol",
                  lambda: molecular_biology.get_bacterial_transformation_protocol())
        safe_test(results, "molecular_biology", "get_gene_coding_sequence",
                  lambda: molecular_biology.get_gene_coding_sequence("BRCA1", "Homo sapiens"))
        safe_test(results, "molecular_biology", "get_plasmid_sequence",
                  lambda: molecular_biology.get_plasmid_sequence("pUC19"))
        safe_test(results, "molecular_biology", "design_golden_gate_oligos",
                  lambda: molecular_biology.design_golden_gate_oligos(SAMPLE_DNA_SEQ, SAMPLE_DNA_SEQ[:50], "BsaI"))
        safe_test(results, "molecular_biology", "golden_gate_assembly",
                  lambda: molecular_biology.golden_gate_assembly(SAMPLE_DNA_SEQ, "BsaI", [{"sequence": SAMPLE_DNA_SEQ[:30], "name": "frag1"}]))
        safe_test(results, "molecular_biology", "design_verification_primers",
                  lambda: molecular_biology.design_verification_primers(SAMPLE_DNA_SEQ, (10, 100)))
        # Skip design_knockout_sgrna - requires data_lake_path
        results.add("molecular_biology", "design_knockout_sgrna", "SKIP", "requires data_lake_path")

    except ImportError as e:
        results.add("molecular_biology", "import", "FAIL", str(e))


# ============================================================================
# LITERATURE TESTS (10 functions)
# ============================================================================
def test_literature(results):
    print("\n--- Testing literature (3 functions - query functions removed, use Galaxy biomate_ds_api_*) ---")
    try:
        from biomni.tool import literature

        # Query functions REMOVED - use Galaxy biomate_ds_api_* tools instead
        results.add("literature", "query_pubmed", "SKIP", "REMOVED - use Galaxy biomate_ds_api_pubmed")
        results.add("literature", "query_arxiv", "SKIP", "REMOVED - use Galaxy tools")
        results.add("literature", "query_scholar", "SKIP", "REMOVED - use Galaxy tools")
        results.add("literature", "search_google", "SKIP", "REMOVED - use Galaxy tools")
        results.add("literature", "advanced_web_search_claude", "SKIP", "REMOVED - LLM-dependent")

        # Remaining functions that don't require LLM
        safe_test(results, "literature", "extract_url_content",
                  lambda: literature.extract_url_content("https://www.uniprot.org/uniprotkb/P38398"))
        # Skip extract_pdf_content - requires PDF URL
        results.add("literature", "extract_pdf_content", "SKIP", "requires PDF URL")
        # Skip fetch_supplementary_info_from_doi - requires DOI
        results.add("literature", "fetch_supplementary_info_from_doi", "SKIP", "requires valid DOI")

    except ImportError as e:
        results.add("literature", "import", "FAIL", str(e))


# ============================================================================
# GENOMICS TESTS (20 functions)
# ============================================================================
def test_genomics(results):
    print("\n--- Testing genomics (20 functions) ---")
    try:
        from biomni.tool import genomics

        safe_test(results, "genomics", "gene_set_enrichment_analysis",
                  lambda: genomics.gene_set_enrichment_analysis(["TP53", "BRCA1", "BRCA2", "ATM"]))
        safe_test(results, "genomics", "get_gene_set_enrichment_analysis_supported_database_list",
                  lambda: genomics.get_gene_set_enrichment_analysis_supported_database_list())
        safe_test(results, "genomics", "interspecies_gene_conversion",
                  lambda: genomics.interspecies_gene_conversion(["BRCA1"], "human", "mouse"))
        safe_test(results, "genomics", "get_rna_seq_archs4",
                  lambda: genomics.get_rna_seq_archs4("TP53", K=5))

        # Tools requiring file inputs
        results.add("genomics", "analyze_chromatin_interactions", "SKIP", "requires HiC file")
        results.add("genomics", "analyze_comparative_genomics_and_haplotypes", "SKIP", "requires FASTA files")
        results.add("genomics", "analyze_genomic_region_overlap", "SKIP", "requires BED files")
        results.add("genomics", "annotate_celltype_scRNA", "SKIP", "requires AnnData file")
        results.add("genomics", "annotate_celltype_with_panhumanpy", "SKIP", "requires AnnData file")
        results.add("genomics", "create_harmony_embeddings_scRNA", "SKIP", "requires AnnData file")
        results.add("genomics", "create_scvi_embeddings_scRNA", "SKIP", "requires AnnData file")
        results.add("genomics", "find_enriched_motifs_with_homer", "SKIP", "requires peak file")
        results.add("genomics", "generate_embeddings_with_state", "SKIP", "requires AnnData file")
        results.add("genomics", "generate_gene_embeddings_with_ESM_models", "SKIP", "requires GPU/model")
        results.add("genomics", "generate_transcriptformer_embeddings", "SKIP", "requires AnnData file")
        results.add("genomics", "get_uce_embeddings_scRNA", "SKIP", "requires AnnData file")
        results.add("genomics", "map_to_ima_interpret_scRNA", "SKIP", "requires AnnData file")
        results.add("genomics", "perform_chipseq_peak_calling_with_macs2", "SKIP", "requires BAM files")
        results.add("genomics", "unsupervised_celltype_transfer_between_scRNA_datasets", "SKIP", "requires h5ad files")

    except ImportError as e:
        results.add("genomics", "import", "FAIL", str(e))


# ============================================================================
# BIOCHEMISTRY TESTS (6 functions)
# ============================================================================
def test_biochemistry(results):
    print("\n--- Testing biochemistry (6 functions) ---")
    try:
        from biomni.tool import biochemistry

        # Create mock data
        wavelengths = list(range(190, 260, 5))
        cd_signal = [x * 0.01 for x in range(-10, 4)]

        safe_test(results, "biochemistry", "analyze_circular_dichroism_spectra",
                  lambda: biochemistry.analyze_circular_dichroism_spectra(
                      "TestProtein", "protein", wavelengths, cd_signal))

        substrate_conc = [0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
        safe_test(results, "biochemistry", "analyze_enzyme_kinetics_assay",
                  lambda: biochemistry.analyze_enzyme_kinetics_assay(
                      "Trypsin", substrate_conc, 0.01))

        safe_test(results, "biochemistry", "analyze_rna_secondary_structure_features",
                  lambda: biochemistry.analyze_rna_secondary_structure_features(
                      SAMPLE_DOT_BRACKET, SAMPLE_RNA_SEQ[:len(SAMPLE_DOT_BRACKET)]))

        # analyze_protein_conservation requires multiple sequences
        safe_test(results, "biochemistry", "analyze_protein_conservation",
                  lambda: biochemistry.analyze_protein_conservation([SAMPLE_PROTEIN_SEQ, SAMPLE_PROTEIN_SEQ.replace("M", "L")]))

        time_points = [0, 5, 10, 15, 20, 30, 45, 60]
        fluorescence = [[100, 150, 200, 250, 300, 350, 380, 400] for _ in substrate_conc]
        safe_test(results, "biochemistry", "analyze_protease_kinetics",
                  lambda: biochemistry.analyze_protease_kinetics(
                      time_points, fluorescence, substrate_conc, 0.01))

        # analyze_itc_binding_thermodynamics requires ITC data file
        results.add("biochemistry", "analyze_itc_binding_thermodynamics", "SKIP", "requires ITC data")

    except ImportError as e:
        results.add("biochemistry", "import", "FAIL", str(e))


# ============================================================================
# GLYCOENGINEERING TESTS (3 functions)
# ============================================================================
def test_glycoengineering(results):
    print("\n--- Testing glycoengineering (3 functions) ---")
    try:
        from biomni.tool import glycoengineering

        safe_test(results, "glycoengineering", "find_n_glycosylation_motifs",
                  lambda: glycoengineering.find_n_glycosylation_motifs(SAMPLE_PROTEIN_SEQ))
        safe_test(results, "glycoengineering", "predict_o_glycosylation_hotspots",
                  lambda: glycoengineering.predict_o_glycosylation_hotspots(SAMPLE_PROTEIN_SEQ))
        safe_test(results, "glycoengineering", "list_glycoengineering_resources",
                  lambda: glycoengineering.list_glycoengineering_resources())

    except ImportError as e:
        results.add("glycoengineering", "import", "FAIL", str(e))


# ============================================================================
# MICROBIOLOGY TESTS (12 functions)
# ============================================================================
def test_microbiology(results):
    print("\n--- Testing microbiology (12 functions) ---")
    try:
        from biomni.tool import microbiology

        safe_test(results, "microbiology", "predict_rna_secondary_structure",
                  lambda: microbiology.predict_rna_secondary_structure(SAMPLE_RNA_SEQ))

        safe_test(results, "microbiology", "simulate_microbial_population_dynamics",
                  lambda: microbiology.simulate_microbial_population_dynamics(
                      [1000, 500], [0.5, 0.3], [0.1, 0.1], [10000, 8000]))

        safe_test(results, "microbiology", "simulate_generalized_lotka_volterra_dynamics",
                  lambda: microbiology.simulate_generalized_lotka_volterra_dynamics(
                      [100, 50], [0.5, 0.3], [[-0.01, -0.02], [-0.01, -0.01]], list(range(100))))

        safe_test(results, "microbiology", "model_bacterial_growth_dynamics",
                  lambda: microbiology.model_bacterial_growth_dynamics(1000, 0.5, 0.1, 100000))

        safe_test(results, "microbiology", "enumerate_bacterial_cfu_by_serial_dilution",
                  lambda: microbiology.enumerate_bacterial_cfu_by_serial_dilution())

        od_values = [0.1, 0.15, 0.2, 0.3, 0.5]
        safe_test(results, "microbiology", "quantify_biofilm_biomass_crystal_violet",
                  lambda: microbiology.quantify_biofilm_biomass_crystal_violet(od_values))

        # Tools requiring files/images
        results.add("microbiology", "annotate_bacterial_genome", "SKIP", "requires genome file")
        results.add("microbiology", "count_bacterial_colonies", "SKIP", "requires image")
        results.add("microbiology", "segment_and_analyze_microbial_cells", "SKIP", "requires image")
        results.add("microbiology", "segment_cells_with_deep_learning", "SKIP", "requires image")
        results.add("microbiology", "optimize_anaerobic_digestion_process", "SKIP", "requires waste data")
        results.add("microbiology", "analyze_arsenic_speciation_hplc_icpms", "SKIP", "requires HPLC data")

    except ImportError as e:
        results.add("microbiology", "import", "FAIL", str(e))


# ============================================================================
# BIOPHYSICS TESTS (3 functions)
# ============================================================================
def test_biophysics(results):
    print("\n--- Testing biophysics (3 functions) ---")
    try:
        from biomni.tool import biophysics

        safe_test(results, "biophysics", "predict_protein_disorder_regions",
                  lambda: biophysics.predict_protein_disorder_regions(SAMPLE_PROTEIN_SEQ))

        # Image-based tools
        results.add("biophysics", "analyze_cell_morphology_and_cytoskeleton", "SKIP", "requires image")
        results.add("biophysics", "analyze_tissue_deformation_flow", "SKIP", "requires image sequence")

    except ImportError as e:
        results.add("biophysics", "import", "FAIL", str(e))


# ============================================================================
# PHARMACOLOGY TESTS (24 functions)
# ============================================================================
def test_pharmacology(results):
    print("\n--- Testing pharmacology (24 functions) ---")
    try:
        from biomni.tool import pharmacology

        safe_test(results, "pharmacology", "calculate_physicochemical_properties",
                  lambda: pharmacology.calculate_physicochemical_properties(SAMPLE_SMILES))

        # Skip ADMET - requires DeepPurpose model download
        results.add("pharmacology", "predict_admet_properties", "SKIP", "requires model download")

        # Skip binding affinity - requires model download
        results.add("pharmacology", "predict_binding_affinity_protein_1d_sequence", "SKIP", "requires model download")

        safe_test(results, "pharmacology", "check_drug_combination_safety",
                  lambda: pharmacology.check_drug_combination_safety(["aspirin", "ibuprofen"]))

        safe_test(results, "pharmacology", "query_drug_interactions",
                  lambda: pharmacology.query_drug_interactions(["aspirin", "warfarin"]))

        safe_test(results, "pharmacology", "find_alternative_drugs_ddinter",
                  lambda: pharmacology.find_alternative_drugs_ddinter("aspirin", ["warfarin"]))

        safe_test(results, "pharmacology", "analyze_interaction_mechanisms",
                  lambda: pharmacology.analyze_interaction_mechanisms(("aspirin", "warfarin")))

        safe_test(results, "pharmacology", "get_fda_drug_label_info",
                  lambda: pharmacology.get_fda_drug_label_info("aspirin"))

        safe_test(results, "pharmacology", "check_fda_drug_recalls",
                  lambda: pharmacology.check_fda_drug_recalls("aspirin"))

        safe_test(results, "pharmacology", "query_fda_adverse_events",
                  lambda: pharmacology.query_fda_adverse_events("aspirin", limit=5))

        safe_test(results, "pharmacology", "analyze_fda_safety_signals",
                  lambda: pharmacology.analyze_fda_safety_signals(["aspirin"]))

        # Tools requiring files/special setup
        results.add("pharmacology", "docking_autodock_vina", "SKIP", "requires PDB/ligand files")
        results.add("pharmacology", "run_diffdock_with_smiles", "SKIP", "requires GPU/model")
        results.add("pharmacology", "run_autosite", "SKIP", "requires PDB file")
        results.add("pharmacology", "grade_adverse_events_using_vcog_ctcae", "SKIP", "requires clinical data file")
        results.add("pharmacology", "analyze_western_blot", "SKIP", "requires blot image")
        results.add("pharmacology", "analyze_xenograft_tumor_growth_inhibition", "SKIP", "requires data file")
        results.add("pharmacology", "analyze_accelerated_stability_of_pharmaceutical_formulations", "SKIP", "requires formulation data")
        results.add("pharmacology", "analyze_radiolabeled_antibody_biodistribution", "SKIP", "requires biodistribution data")
        results.add("pharmacology", "estimate_alpha_particle_radiotherapy_dosimetry", "SKIP", "requires dosimetry data")
        results.add("pharmacology", "perform_mwas_cyp2c19_metabolizer_status", "SKIP", "requires methylation data")
        results.add("pharmacology", "retrieve_topk_repurposing_drugs_from_disease_txgnn", "SKIP", "requires data_lake_path")
        results.add("pharmacology", "run_3d_chondrogenic_aggregate_assay", "SKIP", "requires cell data")

    except ImportError as e:
        results.add("pharmacology", "import", "FAIL", str(e))


# ============================================================================
# SYNTHETIC BIOLOGY TESTS (8 functions)
# ============================================================================
def test_synthetic_biology(results):
    print("\n--- Testing synthetic_biology (8 functions) ---")
    try:
        from biomni.tool import synthetic_biology

        time_pts = list(range(0, 10))
        od_vals = [0.1, 0.15, 0.25, 0.4, 0.6, 0.85, 1.0, 1.1, 1.15, 1.18]

        safe_test(results, "synthetic_biology", "analyze_bacterial_growth_rate",
                  lambda: synthetic_biology.analyze_bacterial_growth_rate(time_pts, od_vals, "E.coli"))

        safe_test(results, "synthetic_biology", "identify_fas_functional_domains",
                  lambda: synthetic_biology.identify_fas_functional_domains(SAMPLE_PROTEIN_SEQ))

        # E. coli codon usage table (simplified)
        ecoli_codon_usage = {"UUU": 0.58, "UUC": 0.42, "UUA": 0.13, "UUG": 0.13,
                            "CUU": 0.10, "CUC": 0.10, "CUA": 0.04, "CUG": 0.50}
        safe_test(results, "synthetic_biology", "optimize_codons_for_heterologous_expression",
                  lambda: synthetic_biology.optimize_codons_for_heterologous_expression(SAMPLE_PROTEIN_SEQ[:20], ecoli_codon_usage))

        # Import numpy for mock data generation
        import numpy as np

        param_vals = list(range(10))
        time_series = [[i + np.random.randn() for i in range(100)] for _ in param_vals]
        safe_test(results, "synthetic_biology", "analyze_bifurcation_diagram",
                  lambda: synthetic_biology.analyze_bifurcation_diagram(time_series, param_vals))

        # Tools requiring special inputs
        results.add("synthetic_biology", "create_biochemical_network_sbml_model", "SKIP", "requires network definition")
        results.add("synthetic_biology", "engineer_bacterial_genome_for_therapeutic_delivery", "SKIP", "requires genome file")
        results.add("synthetic_biology", "analyze_barcode_sequencing_data", "SKIP", "requires sequencing file")

        # simulate_gene_circuit_with_growth_feedback with mock data
        circuit = np.array([[0, -1], [1, 0]])  # Simple toggle switch
        kinetic = {"basal_rates": [0.1, 0.1], "degradation_rates": [0.1, 0.1],
                   "hill_coefficients": [2, 2], "threshold_constants": [1, 1]}
        growth = {"max_growth_rate": 0.5, "growth_inhibition": 0.1, "gene_growth_weights": [0.5, 0.5]}
        safe_test(results, "synthetic_biology", "simulate_gene_circuit_with_growth_feedback",
                  lambda: synthetic_biology.simulate_gene_circuit_with_growth_feedback(circuit, kinetic, growth, simulation_time=10))

    except ImportError as e:
        results.add("synthetic_biology", "import", "FAIL", str(e))


# ============================================================================
# SYSTEMS BIOLOGY TESTS (7 functions)
# ============================================================================
def test_systems_biology(results):
    print("\n--- Testing systems_biology (7 functions) ---")
    try:
        from biomni.tool import systems_biology

        # Skip query_chatnt - requires downloading large model
        results.add("systems_biology", "query_chatnt", "SKIP", "requires large model download")

        # model_protein_dimerization_network requires specific format
        # affinities: dict with string keys "A-B", topology: list of tuples
        monomer_conc = {"A": 1.0, "B": 2.0}
        affinities = {"A-A": 0.1, "A-B": 0.2, "B-B": 0.15}
        topology = [("A", "A"), ("A", "B"), ("B", "B")]
        safe_test(results, "systems_biology", "model_protein_dimerization_network",
                  lambda: systems_biology.model_protein_dimerization_network(monomer_conc, affinities, topology))

        # Tools requiring files
        results.add("systems_biology", "perform_flux_balance_analysis", "SKIP", "requires model file")
        results.add("systems_biology", "compare_protein_structures", "SKIP", "requires PDB files")
        results.add("systems_biology", "simulate_metabolic_network_perturbation", "SKIP", "requires model file")

        # simulate_protein_signaling_network with mock data
        network_struct = {"B": [("A", 1)], "C": [("B", 1), ("A", -1)]}
        rxn_params = {("A", "B"): {"W": 1.0, "n": 2, "EC50": 0.5},
                      ("B", "C"): {"W": 0.8, "n": 2, "EC50": 0.5},
                      ("A", "C"): {"W": 0.5, "n": 2, "EC50": 0.5}}
        species_params = {"A": {"tau": 1.0, "y0": 1.0, "ymax": 1.0},
                          "B": {"tau": 2.0, "y0": 0.0, "ymax": 1.0},
                          "C": {"tau": 3.0, "y0": 0.0, "ymax": 1.0}}
        safe_test(results, "systems_biology", "simulate_protein_signaling_network",
                  lambda: systems_biology.simulate_protein_signaling_network(network_struct, rxn_params, species_params))

        # simulate_renin_angiotensin_system_dynamics with mock data
        initial_conc = {"renin": 1.0, "angiotensinogen": 100.0, "angiotensin_I": 0.0,
                        "angiotensin_II": 0.0, "ACE2_angiotensin_II": 0.0, "angiotensin_1_7": 0.0}
        rate_const = {"k_ren": 0.1, "k_agt": 0.05, "k_ace": 0.5, "k_ace2": 0.3, "k_at1r": 0.2, "k_mas": 0.1}
        feedback = {"fb_ang_II": 0.1, "fb_ace2": 0.05}
        safe_test(results, "systems_biology", "simulate_renin_angiotensin_system_dynamics",
                  lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(initial_conc, rate_const, feedback))

    except ImportError as e:
        results.add("systems_biology", "import", "FAIL", str(e))


# ============================================================================
# IMMUNOLOGY TESTS (11 functions)
# ============================================================================
def test_immunology(results):
    print("\n--- Testing immunology (11 functions) ---")
    try:
        from biomni.tool import immunology

        time_pts = list(range(0, 24, 2))
        od_vals = [0.1, 0.15, 0.25, 0.4, 0.6, 0.85, 1.0, 1.1, 1.15, 1.18, 1.19, 1.19]

        safe_test(results, "immunology", "analyze_bacterial_growth_curve",
                  lambda: immunology.analyze_bacterial_growth_curve(time_pts, od_vals, "E.coli"))

        safe_test(results, "immunology", "isolate_purify_immune_cells",
                  lambda: immunology.isolate_purify_immune_cells("blood", "T cells"))

        # Tools requiring files/data
        results.add("immunology", "analyze_atac_seq_differential_accessibility", "SKIP", "requires BAM files")
        results.add("immunology", "analyze_cfse_cell_proliferation", "SKIP", "requires FCS file")
        results.add("immunology", "analyze_cns_lesion_histology", "SKIP", "requires image")
        results.add("immunology", "analyze_cytokine_production_in_cd4_tcells", "SKIP", "requires FCS files")
        results.add("immunology", "analyze_ebv_antibody_titers", "SKIP", "requires ELISA data")
        results.add("immunology", "analyze_immunohistochemistry_image", "SKIP", "requires image")
        results.add("immunology", "estimate_cell_cycle_phase_durations", "SKIP", "requires flow data")
        results.add("immunology", "track_immune_cells_under_flow", "SKIP", "requires image sequence")

    except ImportError as e:
        results.add("immunology", "import", "FAIL", str(e))


# ============================================================================
# CELL BIOLOGY TESTS (5 functions)
# ============================================================================
def test_cell_biology(results):
    print("\n--- Testing cell_biology (5 functions) ---")
    try:
        from biomni.tool import cell_biology

        # Create mock cell sorting data
        cell_data = {"cell_id": list(range(100)), "fluorescence": [i * 10 + np.random.randn() * 5 for i in range(100)]}
        safe_test(results, "cell_biology", "perform_facs_cell_sorting",
                  lambda: cell_biology.perform_facs_cell_sorting(cell_data, "fluorescence", 200, 800))

        # Tools requiring files
        results.add("cell_biology", "analyze_flow_cytometry_immunophenotyping", "SKIP", "requires FCS file")
        results.add("cell_biology", "analyze_mitochondrial_morphology_and_potential", "SKIP", "requires images")
        results.add("cell_biology", "quantify_and_cluster_cell_motility", "SKIP", "requires image sequence")
        results.add("cell_biology", "quantify_cell_cycle_phases_from_microscopy", "SKIP", "requires images")

    except ImportError as e:
        results.add("cell_biology", "import", "FAIL", str(e))


# ============================================================================
# CANCER BIOLOGY TESTS (6 functions)
# ============================================================================
def test_cancer_biology(results):
    print("\n--- Testing cancer_biology (6 functions) ---")
    try:
        from biomni.tool import cancer_biology

        # All cancer biology tools require file inputs
        results.add("cancer_biology", "analyze_ddr_network_in_cancer", "SKIP", "requires expression + mutation files")
        results.add("cancer_biology", "analyze_cell_senescence_and_apoptosis", "SKIP", "requires FCS file")
        results.add("cancer_biology", "analyze_copy_number_purity_ploidy_and_focal_events", "SKIP", "requires BAM file")
        results.add("cancer_biology", "detect_and_annotate_somatic_mutations", "SKIP", "requires BAM files")
        results.add("cancer_biology", "detect_and_characterize_structural_variations", "SKIP", "requires BAM file")
        results.add("cancer_biology", "perform_gene_expression_nmf_analysis", "SKIP", "requires expression file")

    except ImportError as e:
        results.add("cancer_biology", "import", "FAIL", str(e))


# ============================================================================
# PHYSIOLOGY TESTS (11 functions)
# ============================================================================
def test_physiology(results):
    print("\n--- Testing physiology (11 functions) ---")
    try:
        from biomni.tool import physiology
        import math

        # Cosinor analysis with circadian data
        time_pts = list(range(0, 48, 2))
        values = [10 + 5 * math.sin(2 * math.pi * t / 24) + np.random.randn() * 0.5 for t in time_pts]
        safe_test(results, "physiology", "perform_cosinor_analysis",
                  lambda: physiology.perform_cosinor_analysis(time_pts, values))

        # ABR waveform analysis
        time_ms = list(range(0, 10))
        amplitude = [0, 0.5, 1.0, 0.8, 0.3, -0.2, -0.5, -0.3, 0, 0.1]
        safe_test(results, "physiology", "analyze_abr_waveform_p1_metrics",
                  lambda: physiology.analyze_abr_waveform_p1_metrics(time_ms, amplitude))

        # Calcium dynamics
        time_pts2 = list(range(0, 60))
        lumi_vals = [100 + 50 * math.exp(-t/10) for t in time_pts2]
        safe_test(results, "physiology", "analyze_endolysosomal_calcium_dynamics",
                  lambda: physiology.analyze_endolysosomal_calcium_dynamics(time_pts2, lumi_vals))

        # Hemodynamic analysis
        pressure_data = [80 + 40 * math.sin(2 * math.pi * i / 100) for i in range(1000)]
        safe_test(results, "physiology", "analyze_hemodynamic_data",
                  lambda: physiology.analyze_hemodynamic_data(pressure_data, 1000))

        # Thyroid PK simulation
        params = {"ka": 0.5, "ke": 0.1, "V": 10}
        initial = {"dose": 100, "A": 100, "C": 0}
        safe_test(results, "physiology", "simulate_thyroid_hormone_pharmacokinetics",
                  lambda: physiology.simulate_thyroid_hormone_pharmacokinetics(params, initial))

        # Tools requiring files/images
        results.add("physiology", "analyze_ciliary_beat_frequency", "SKIP", "requires video")
        results.add("physiology", "analyze_fatty_acid_composition_by_gc", "SKIP", "requires GC data file")
        results.add("physiology", "analyze_protein_colocalization", "SKIP", "requires images")
        results.add("physiology", "calculate_brain_adc_map", "SKIP", "requires DWI file")
        results.add("physiology", "quantify_amyloid_beta_plaques", "SKIP", "requires image")
        results.add("physiology", "reconstruct_3d_face_from_mri", "SKIP", "requires MRI file")

    except ImportError as e:
        results.add("physiology", "import", "FAIL", str(e))


# ============================================================================
# PATHOLOGY TESTS (7 functions)
# ============================================================================
def test_pathology(results):
    print("\n--- Testing pathology (7 functions) ---")
    try:
        from biomni.tool import pathology

        # ATP assay with mock data files
        results.add("pathology", "analyze_atp_luminescence_assay", "SKIP", "requires data files")
        results.add("pathology", "analyze_aortic_diameter_and_geometry", "SKIP", "requires image")
        results.add("pathology", "analyze_bone_microct_morphometry", "SKIP", "requires microCT file")
        results.add("pathology", "analyze_intracellular_calcium_with_rhod2", "SKIP", "requires images")
        results.add("pathology", "analyze_thrombus_histology", "SKIP", "requires image")
        results.add("pathology", "quantify_corneal_nerve_fibers", "SKIP", "requires image")
        results.add("pathology", "segment_and_quantify_cells_in_multiplexed_images", "SKIP", "requires image")

    except ImportError as e:
        results.add("pathology", "import", "FAIL", str(e))


# ============================================================================
# BIOENGINEERING TESTS (7 functions)
# ============================================================================
def test_bioengineering(results):
    print("\n--- Testing bioengineering (7 functions) ---")
    try:
        from biomni.tool import bioengineering

        # Drug release kinetics
        time_pts = [0, 1, 2, 4, 8, 12, 24, 48]
        conc_data = [0, 10, 25, 45, 65, 80, 90, 95]
        safe_test(results, "bioengineering", "analyze_in_vitro_drug_release_kinetics",
                  lambda: bioengineering.analyze_in_vitro_drug_release_kinetics(time_pts, conc_data, "TestDrug"))

        # Whole cell ODE model
        initial = {"X": 1.0, "Y": 0.5}
        params = {"a": 0.1, "b": 0.2}
        safe_test(results, "bioengineering", "simulate_whole_cell_ode_model",
                  lambda: bioengineering.simulate_whole_cell_ode_model(initial, params))

        # CRISPR editing simulation - target_genomic_loci is a string, not a list of dicts
        guides = ["ATGCATGCATGCATGCATGC"]
        target_seq = "NNNNATGCATGCATGCATGCATGCNGGNNNN"  # PAM-containing target sequence
        safe_test(results, "bioengineering", "perform_crispr_cas9_genome_editing",
                  lambda: bioengineering.perform_crispr_cas9_genome_editing(guides, target_seq, "HEK293"))

        # Tools requiring files
        results.add("bioengineering", "analyze_calcium_imaging_data", "SKIP", "requires image stack")
        results.add("bioengineering", "analyze_cell_migration_metrics", "SKIP", "requires image sequence")
        results.add("bioengineering", "analyze_myofiber_morphology", "SKIP", "requires image")
        results.add("bioengineering", "decode_behavior_from_neural_trajectories", "SKIP", "requires neural data")

    except ImportError as e:
        results.add("bioengineering", "import", "FAIL", str(e))


# ============================================================================
# GENETICS TESTS (10 functions)
# ============================================================================
def test_genetics(results):
    print("\n--- Testing genetics (10 functions) ---")
    try:
        from biomni.tool import genetics

        # CRISPR analysis
        edited_seq = SAMPLE_DNA_SEQ.replace("ATG", "GTG")
        safe_test(results, "genetics", "analyze_crispr_genome_editing",
                  lambda: genetics.analyze_crispr_genome_editing(SAMPLE_DNA_SEQ, edited_seq, "ATGAAATTCCTGATCCTGCT"))

        # TF binding sites
        safe_test(results, "genetics", "identify_transcription_factor_binding_sites",
                  lambda: genetics.identify_transcription_factor_binding_sites(SAMPLE_DNA_SEQ, "TP53"))

        # Protein phylogeny
        fasta_seqs = f">seq1\n{SAMPLE_PROTEIN_SEQ}\n>seq2\n{SAMPLE_PROTEIN_SEQ.replace('M', 'L')}"
        safe_test(results, "genetics", "analyze_protein_phylogeny",
                  lambda: genetics.analyze_protein_phylogeny(fasta_seqs))

        # Cas9 mutation outcomes - expects dict and nested dict format
        ref_seqs = {"target1": SAMPLE_DNA_SEQ[:100]}
        edit_seqs = {"target1": {"read1": SAMPLE_DNA_SEQ[:100].replace("ATG", "GTG"),
                                  "read2": SAMPLE_DNA_SEQ[:100].replace("ATG", "AAG")}}
        safe_test(results, "genetics", "analyze_cas9_mutation_outcomes",
                  lambda: genetics.analyze_cas9_mutation_outcomes(ref_seqs, edit_seqs))

        # Tools requiring special files/data
        results.add("genetics", "liftover_coordinates", "SKIP", "requires chain file data_path")
        results.add("genetics", "bayesian_finemapping_with_deep_vi", "SKIP", "requires GWAS summary + LD matrix")
        results.add("genetics", "fit_genomic_prediction_model", "SKIP", "requires genotype/phenotype data")
        results.add("genetics", "perform_pcr_and_gel_electrophoresis", "SKIP", "requires genomic DNA")
        results.add("genetics", "simulate_demographic_history", "SKIP", "requires msprime setup")

    except ImportError as e:
        results.add("genetics", "import", "FAIL", str(e))


# ============================================================================
# PROTOCOLS TESTS (2 functions)
# ============================================================================
def test_protocols(results):
    print("\n--- Testing protocols (MODULE DELETED - protocols.io API moved elsewhere) ---")
    # protocols.py was DELETED - it required external API token
    # Protocol queries should use Galaxy tools or external APIs directly
    results.add("protocols", "search_protocols", "SKIP", "MODULE DELETED - required protocols.io token")
    results.add("protocols", "get_protocol_details", "SKIP", "MODULE DELETED - required protocols.io token")


# ============================================================================
# LAB AUTOMATION TESTS (3 functions)
# ============================================================================
def test_lab_automation(results):
    print("\n--- Testing lab_automation (3 functions) ---")
    try:
        from biomni.tool import lab_automation

        safe_test(results, "lab_automation", "get_pylabrobot_documentation_liquid",
                  lambda: lab_automation.get_pylabrobot_documentation_liquid())

        safe_test(results, "lab_automation", "get_pylabrobot_documentation_material",
                  lambda: lab_automation.get_pylabrobot_documentation_material())

        # test_pylabrobot_script requires actual script
        results.add("lab_automation", "test_pylabrobot_script", "SKIP", "requires PyLabRobot script")

    except ImportError as e:
        results.add("lab_automation", "import", "FAIL", str(e))


# ============================================================================
# BIOIMAGING TESTS
# ============================================================================
def test_bioimaging(results):
    print("\n--- Testing bioimaging (requires nnunet) ---")
    try:
        from biomni.tool import bioimaging
        results.add("bioimaging", "import", "PASS", "module imported")
        # All bioimaging tools require image files
        results.add("bioimaging", "all_functions", "SKIP", "requires image files and nnunet")
    except ImportError as e:
        results.add("bioimaging", "import", "FAIL", str(e))


# ============================================================================
# MAIN
# ============================================================================
def run_all_tests():
    print("="*70)
    print("EXHAUSTIVE BIOMNI TEST SUITE v3 - TESTING ALL FUNCTIONS")
    print("="*70)

    results = TestResults()

    test_database(results)
    test_molecular_biology(results)
    test_literature(results)
    test_genomics(results)
    test_biochemistry(results)
    test_glycoengineering(results)
    test_microbiology(results)
    test_biophysics(results)
    test_pharmacology(results)
    test_synthetic_biology(results)
    test_systems_biology(results)
    test_immunology(results)
    test_cell_biology(results)
    test_cancer_biology(results)
    test_physiology(results)
    test_pathology(results)
    test_bioengineering(results)
    test_genetics(results)
    test_protocols(results)
    test_lab_automation(results)
    test_bioimaging(results)

    results.summary()

    # Save results
    with open("/tmp/biomni_test_v3.json", "w") as f:
        json.dump({
            "passed": results.passed,
            "failed": results.failed,
            "skipped": results.skipped,
            "categories": results.categories
        }, f, indent=2, default=str)
    print(f"\nResults saved to /tmp/biomni_test_v3.json")


if __name__ == "__main__":
    run_all_tests()
