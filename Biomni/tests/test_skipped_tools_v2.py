#!/usr/bin/env python3
"""
Test ONLY the previously skipped Biomni tools - v2 with correct signatures.
"""

import os
import sys
import json
import numpy as np
from pathlib import Path

TEST_DATA_DIR = Path("/tmp/biomni_test_v2")
TEST_DATA_DIR.mkdir(exist_ok=True)

SAMPLE_PROTEIN = "MKFLILLFNILCLFPVLAADNHGVGPQGASGVDPITFDINSNQTGVQLTLNSTGSEEECKFSLFLKWFEPG"
SAMPLE_DNA = "ATGAAATTCCTGATCCTGCTGTTCAACATCCTGTGCCTGTTCCCTGTGCTGGCTGCTGACAAC"
SAMPLE_SMILES = "CC(=O)OC1=CC=CC=C1C(=O)O"


class Results:
    def __init__(self):
        self.passed = []
        self.failed = []

    def add(self, name, status, msg=""):
        entry = {"name": name, "message": msg[:200]}
        if status == "PASS":
            self.passed.append(entry)
            print(f"  ✓ {name}")
        else:
            self.failed.append(entry)
            print(f"  ✗ {name}: {msg[:80]}")

    def summary(self):
        total = len(self.passed) + len(self.failed)
        print(f"\n{'='*60}")
        print(f"SKIPPED TOOLS TEST v2: {len(self.passed)}/{total} PASSED ({100*len(self.passed)/max(1,total):.0f}%)")
        print(f"{'='*60}")


def safe_test(results, name, func):
    try:
        result = func()
        results.add(name, "PASS", str(result)[:50] if result else "OK")
    except Exception as e:
        results.add(name, "FAIL", str(e))


# Create mock files
def setup_mock_data():
    """Create all mock data files"""
    paths = {}

    # Mock image
    try:
        from PIL import Image
        img = np.zeros((256, 256), dtype=np.uint8)
        for _ in range(15):
            cx, cy = np.random.randint(30, 226, 2)
            for i in range(256):
                for j in range(256):
                    if (i-cx)**2 + (j-cy)**2 < 200:
                        img[i,j] = np.random.randint(150, 255)
        img_path = str(TEST_DATA_DIR / "mock_image.png")
        Image.fromarray(img).save(img_path)
        paths['image'] = img_path
    except:
        paths['image'] = None

    # Mock AnnData
    try:
        import anndata as ad
        import pandas as pd
        import scipy.sparse as sp

        n_cells, n_genes = 100, 50
        X = sp.random(n_cells, n_genes, density=0.3, format='csr').astype(np.float32)
        obs = pd.DataFrame({
            'cell_type': np.random.choice(['T', 'B', 'NK'], n_cells),
            'batch': np.random.choice(['b1', 'b2'], n_cells),
            'leiden': np.random.choice(['0', '1', '2'], n_cells)
        }, index=[f'cell_{i}' for i in range(n_cells)])
        var = pd.DataFrame(index=[f'gene_{i}' for i in range(n_genes)])

        adata = ad.AnnData(X=X, obs=obs, var=var)
        adata.obsm['X_pca'] = np.random.randn(n_cells, 20).astype(np.float32)
        h5ad_path = str(TEST_DATA_DIR / "mock.h5ad")
        adata.write_h5ad(h5ad_path)
        paths['anndata'] = h5ad_path
        paths['data_dir'] = str(TEST_DATA_DIR)
    except Exception as e:
        print(f"  Warning: Cannot create AnnData: {e}")
        paths['anndata'] = None

    # Mock PDB
    pdb_path = str(TEST_DATA_DIR / "mock.pdb")
    with open(pdb_path, 'w') as f:
        f.write("""ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 20.00           N
ATOM      2  CA  ALA A   1       1.458   0.000   0.000  1.00 20.00           C
END
""")
    paths['pdb'] = pdb_path

    # Mock FASTA
    fasta_path = str(TEST_DATA_DIR / "mock.fasta")
    with open(fasta_path, 'w') as f:
        for i in range(5):
            seq = ''.join(np.random.choice(list('ACGT'), 300))
            f.write(f">seq_{i}\n{seq}\n")
    paths['fasta'] = fasta_path

    # Mock BED
    bed_path = str(TEST_DATA_DIR / "mock.bed")
    with open(bed_path, 'w') as f:
        for i in range(50):
            f.write(f"chr1\t{i*1000}\t{i*1000+500}\tpeak_{i}\t100\t+\n")
    paths['bed'] = bed_path

    # Mock BAM
    try:
        import pysam
        bam_path = str(TEST_DATA_DIR / "mock.bam")
        header = {'HD': {'VN': '1.0'}, 'SQ': [{'LN': 10000, 'SN': 'chr1'}]}
        with pysam.AlignmentFile(bam_path, "wb", header=header) as f:
            for i in range(50):
                a = pysam.AlignedSegment()
                a.query_name = f"read_{i}"
                a.query_sequence = "A" * 100
                a.flag = 0
                a.reference_id = 0
                a.reference_start = i * 100
                a.mapping_quality = 60
                a.cigar = [(0, 100)]
                a.query_qualities = pysam.qualitystring_to_array("I" * 100)
                f.write(a)
        pysam.index(bam_path)
        paths['bam'] = bam_path
    except:
        paths['bam'] = None

    # Mock FCS
    try:
        import fcswrite
        fcs_path = str(TEST_DATA_DIR / "mock.fcs")
        data = np.random.lognormal(10, 1, (1000, 5)).astype(np.float32)
        fcswrite.write_fcs(fcs_path, ['FSC', 'SSC', 'FITC', 'PE', 'APC'], data)
        paths['fcs'] = fcs_path
    except:
        paths['fcs'] = None

    return paths


def run_tests():
    print("="*60)
    print("TESTING PREVIOUSLY SKIPPED TOOLS - v2 (CORRECT SIGNATURES)")
    print("="*60)

    print("\nCreating mock data...")
    paths = setup_mock_data()
    print(f"Created: {[k for k,v in paths.items() if v]}")

    results = Results()

    # ========== LITERATURE (should work) ==========
    print("\n--- literature ---")
    try:
        from biomni.tool import literature
        safe_test(results, "literature.extract_pdf_content",
                  lambda: literature.extract_pdf_content("https://arxiv.org/pdf/2301.00001.pdf"))
        safe_test(results, "literature.fetch_supplementary_info_from_doi",
                  lambda: literature.fetch_supplementary_info_from_doi("10.1038/s41586-020-2649-2"))
    except ImportError as e:
        results.add("literature.import", "FAIL", str(e))

    # ========== GENOMICS ==========
    print("\n--- genomics ---")
    try:
        from biomni.tool import genomics

        if paths.get('bed'):
            safe_test(results, "genomics.find_enriched_motifs_with_homer",
                      lambda: genomics.find_enriched_motifs_with_homer(paths['bed']))

        # ESM embeddings (GPU)
        safe_test(results, "genomics.generate_gene_embeddings_with_ESM_models",
                  lambda: genomics.generate_gene_embeddings_with_ESM_models([SAMPLE_PROTEIN[:30]]))

        # scRNA functions need: adata_filename, data_dir, data_info, data_lake_path
        if paths.get('anndata'):
            data_info = {'species': 'human', 'tissue': 'blood'}
            # These need data_lake_path with models - mark as needing setup
            results.add("genomics.annotate_celltype_scRNA", "FAIL",
                       "Needs data_lake_path with celltype models")
            results.add("genomics.create_harmony_embeddings_scRNA", "FAIL",
                       "Needs proper data_dir structure")
            results.add("genomics.create_scvi_embeddings_scRNA", "FAIL",
                       "Needs batch_key, label_key, data_dir")

    except ImportError as e:
        results.add("genomics.import", "FAIL", str(e))

    # ========== BIOCHEMISTRY ==========
    print("\n--- biochemistry ---")
    try:
        from biomni.tool import biochemistry
        # ITC needs specific format
        itc_data = {
            'injection_volume': [2.0]*10,
            'heat': list(np.random.randn(10)*10),
            'ligand_conc': list(np.linspace(0, 100, 10)),
            'protein_conc': 10.0,
            'cell_volume': 1.4,  # mL
            'temperature': 25.0  # Celsius
        }
        safe_test(results, "biochemistry.analyze_itc_binding_thermodynamics",
                  lambda: biochemistry.analyze_itc_binding_thermodynamics(itc_data))
    except ImportError as e:
        results.add("biochemistry.import", "FAIL", str(e))

    # ========== MICROBIOLOGY ==========
    print("\n--- microbiology ---")
    try:
        from biomni.tool import microbiology

        if paths.get('image'):
            safe_test(results, "microbiology.count_bacterial_colonies",
                      lambda: microbiology.count_bacterial_colonies(paths['image']))
            safe_test(results, "microbiology.segment_and_analyze_microbial_cells",
                      lambda: microbiology.segment_and_analyze_microbial_cells(paths['image']))
            safe_test(results, "microbiology.segment_cells_with_deep_learning",
                      lambda: microbiology.segment_cells_with_deep_learning(paths['image']))

        # optimize_anaerobic_digestion_process: (waste_characteristics, operational_parameters, ...)
        waste = {
            'volatile_solids': 50.0,
            'total_solids': 80.0,
            'carbon_nitrogen_ratio': 25.0,
            'organic_loading_rate': 3.0
        }
        op_params = {
            'temperature': 35.0,
            'ph': 7.0,
            'hydraulic_retention_time': 20.0
        }
        safe_test(results, "microbiology.optimize_anaerobic_digestion_process",
                  lambda: microbiology.optimize_anaerobic_digestion_process(waste, op_params))

        # analyze_arsenic_speciation needs proper HPLC data format
        hplc_data = {
            'retention_times': [1.0, 2.0, 3.0, 4.0],
            'intensities': [100, 200, 150, 80],
            'species': ['As(III)', 'As(V)', 'MMA', 'DMA']
        }
        safe_test(results, "microbiology.analyze_arsenic_speciation_hplc_icpms",
                  lambda: microbiology.analyze_arsenic_speciation_hplc_icpms(hplc_data))

        if paths.get('fasta'):
            safe_test(results, "microbiology.annotate_bacterial_genome",
                      lambda: microbiology.annotate_bacterial_genome(paths['fasta']))

    except ImportError as e:
        results.add("microbiology.import", "FAIL", str(e))

    # ========== BIOPHYSICS ==========
    print("\n--- biophysics ---")
    try:
        from biomni.tool import biophysics
        if paths.get('image'):
            safe_test(results, "biophysics.analyze_cell_morphology_and_cytoskeleton",
                      lambda: biophysics.analyze_cell_morphology_and_cytoskeleton(paths['image']))
    except ImportError as e:
        results.add("biophysics.import", "FAIL", str(e))

    # ========== PHARMACOLOGY ==========
    print("\n--- pharmacology ---")
    try:
        from biomni.tool import pharmacology

        safe_test(results, "pharmacology.calculate_physicochemical_properties",
                  lambda: pharmacology.calculate_physicochemical_properties(SAMPLE_SMILES))

        # docking_autodock_vina: (smiles_list, receptor_pdb_file, box_center, box_size, ncpu=1)
        if paths.get('pdb'):
            safe_test(results, "pharmacology.docking_autodock_vina",
                      lambda: pharmacology.docking_autodock_vina(
                          [SAMPLE_SMILES], paths['pdb'],
                          box_center=[0.0, 0.0, 0.0], box_size=[20.0, 20.0, 20.0]))

            safe_test(results, "pharmacology.run_autosite",
                      lambda: pharmacology.run_autosite(paths['pdb'], output_dir=str(TEST_DATA_DIR)))

        # analyze_western_blot: (blot_image_path, target_bands, loading_control_band, antibody_info, output_dir)
        if paths.get('image'):
            safe_test(results, "pharmacology.analyze_western_blot",
                      lambda: pharmacology.analyze_western_blot(
                          paths['image'],
                          target_bands=['band1', 'band2'],
                          loading_control_band='actin',
                          antibody_info={'primary': 'anti-X', 'secondary': 'anti-rabbit'},
                          output_dir=str(TEST_DATA_DIR)))

        # grade_adverse_events: needs VCOG-CTCAE format
        ae_data = [
            {'patient_id': 1, 'event': 'nausea', 'severity': 'mild'},
            {'patient_id': 2, 'event': 'vomiting', 'severity': 'moderate'}
        ]
        safe_test(results, "pharmacology.grade_adverse_events_using_vcog_ctcae",
                  lambda: pharmacology.grade_adverse_events_using_vcog_ctcae(ae_data))

        # analyze_xenograft: (time_points, tumor_volumes, treatment_groups, control_group)
        safe_test(results, "pharmacology.analyze_xenograft_tumor_growth_inhibition",
                  lambda: pharmacology.analyze_xenograft_tumor_growth_inhibition(
                      time_points=[0, 7, 14, 21],
                      tumor_volumes=[[100, 150, 200, 250], [100, 120, 130, 140]],
                      treatment_groups=['control', 'drug'],
                      control_group='control'))

        # analyze_accelerated_stability: (time_points, potency_data, temperature, humidity)
        safe_test(results, "pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations",
                  lambda: pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations(
                      time_points=[0, 30, 60, 90],
                      potency_data=[100, 98, 95, 90],
                      temperature=40,
                      humidity=75))

        # analyze_radiolabeled_antibody_biodistribution: (organ_data, time_points)
        organ_data = {
            'liver': [15.0, 12.0, 8.0],
            'kidney': [8.0, 6.0, 4.0],
            'tumor': [5.0, 15.0, 25.0]
        }
        safe_test(results, "pharmacology.analyze_radiolabeled_antibody_biodistribution",
                  lambda: pharmacology.analyze_radiolabeled_antibody_biodistribution(
                      organ_data, time_points=[1, 24, 72]))

        # estimate_alpha_particle_dosimetry: (activity_data, organ_masses)
        safe_test(results, "pharmacology.estimate_alpha_particle_radiotherapy_dosimetry",
                  lambda: pharmacology.estimate_alpha_particle_radiotherapy_dosimetry(
                      activity_data={'tumor': 1.0, 'kidney': 0.5},
                      organ_masses={'tumor': 10.0, 'kidney': 150.0}))

        # perform_mwas: (methylation_data, phenotype_data)
        meth_data = np.random.rand(100, 1000)  # 100 samples, 1000 CpG sites
        pheno_data = np.random.choice([0, 1, 2], 100)  # metabolizer status
        safe_test(results, "pharmacology.perform_mwas_cyp2c19_metabolizer_status",
                  lambda: pharmacology.perform_mwas_cyp2c19_metabolizer_status(
                      meth_data, pheno_data))

        # run_3d_chondrogenic: (cell_data, time_points)
        safe_test(results, "pharmacology.run_3d_chondrogenic_aggregate_assay",
                  lambda: pharmacology.run_3d_chondrogenic_aggregate_assay(
                      cell_data={'diameter': [100, 200, 350, 500], 'viability': [95, 92, 88, 85]},
                      time_points=[0, 7, 14, 21]))

    except ImportError as e:
        results.add("pharmacology.import", "FAIL", str(e))

    # ========== SYNTHETIC BIOLOGY ==========
    print("\n--- synthetic_biology ---")
    try:
        from biomni.tool import synthetic_biology

        # create_sbml: (species_list, reactions, parameters)
        safe_test(results, "synthetic_biology.create_biochemical_network_sbml_model",
                  lambda: synthetic_biology.create_biochemical_network_sbml_model(
                      species_list=['A', 'B', 'C'],
                      reactions=[
                          {'reactants': ['A'], 'products': ['B'], 'rate_law': 'k1*A'},
                          {'reactants': ['B'], 'products': ['C'], 'rate_law': 'k2*B'}
                      ],
                      parameters={'k1': 0.1, 'k2': 0.05}))

        # analyze_barcode_sequencing: expects file path, not dict
        barcode_path = str(TEST_DATA_DIR / "barcodes.txt")
        with open(barcode_path, 'w') as f:
            f.write("ACGT\t100\nTGCA\t50\nGCTA\t75\n")
        safe_test(results, "synthetic_biology.analyze_barcode_sequencing_data",
                  lambda: synthetic_biology.analyze_barcode_sequencing_data(barcode_path))

        # simulate_gene_circuit - already tested in v1, should work

    except ImportError as e:
        results.add("synthetic_biology.import", "FAIL", str(e))

    # ========== SYSTEMS BIOLOGY ==========
    print("\n--- systems_biology ---")
    try:
        from biomni.tool import systems_biology

        # query_chatnt: (sequence, query)  - needs DNA/RNA sequence
        safe_test(results, "systems_biology.query_chatnt",
                  lambda: systems_biology.query_chatnt(SAMPLE_DNA, "What is this sequence?"))

        # simulate_protein_signaling_network - tested, works
        # simulate_renin_angiotensin - needs all required keys
        conc = {
            "renin": 1.0,
            "angiotensinogen": 100.0,
            "angiotensin_I": 0.0,
            "angiotensin_II": 0.0,
            "ACE2_angiotensin_II": 0.0,
            "angiotensin_1_7": 0.0
        }
        rate = {
            "k_ren": 0.1, "k_agt": 0.05, "k_ace": 0.5,
            "k_ace2": 0.3, "k_at1r": 0.2, "k_mas": 0.1
        }
        fb = {"fb_ang_II": 0.1, "fb_ace2": 0.05}
        safe_test(results, "systems_biology.simulate_renin_angiotensin_system_dynamics",
                  lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(conc, rate, fb))

        # simulate_metabolic_network: (model_file, perturbations)
        sbml_path = str(TEST_DATA_DIR / "model.sbml")
        sbml = """<?xml version="1.0"?>
<sbml xmlns="http://www.sbml.org/sbml/level3/version2/core" level="3" version="2">
  <model id="test"><listOfCompartments><compartment id="c" size="1"/></listOfCompartments>
  <listOfSpecies><species id="A" compartment="c" initialConcentration="1"/></listOfSpecies>
  </model>
</sbml>"""
        with open(sbml_path, 'w') as f:
            f.write(sbml)
        safe_test(results, "systems_biology.simulate_metabolic_network_perturbation",
                  lambda: systems_biology.simulate_metabolic_network_perturbation(
                      sbml_path, perturbations={'A': 0.5}))

        if paths.get('pdb'):
            safe_test(results, "systems_biology.compare_protein_structures",
                      lambda: systems_biology.compare_protein_structures(paths['pdb'], paths['pdb']))

    except ImportError as e:
        results.add("systems_biology.import", "FAIL", str(e))

    # ========== IMMUNOLOGY ==========
    print("\n--- immunology ---")
    try:
        from biomni.tool import immunology

        # analyze_ebv_antibody_titers: (dilutions, od_values, standard_curve)
        safe_test(results, "immunology.analyze_ebv_antibody_titers",
                  lambda: immunology.analyze_ebv_antibody_titers(
                      dilutions=[1, 10, 100, 1000],
                      od_values=[2.0, 1.5, 0.5, 0.1],
                      standard_curve={'conc': [0, 10, 100, 1000], 'od': [0.1, 0.5, 1.5, 2.0]}))

        # estimate_cell_cycle: (intensity_data)
        safe_test(results, "immunology.estimate_cell_cycle_phase_durations",
                  lambda: immunology.estimate_cell_cycle_phase_durations(
                      intensity_data=np.random.lognormal(10, 1, 1000)))

        if paths.get('image'):
            safe_test(results, "immunology.analyze_cns_lesion_histology",
                      lambda: immunology.analyze_cns_lesion_histology(paths['image']))
            safe_test(results, "immunology.analyze_immunohistochemistry_image",
                      lambda: immunology.analyze_immunohistochemistry_image(paths['image']))

    except ImportError as e:
        results.add("immunology.import", "FAIL", str(e))

    # ========== CELL BIOLOGY ==========
    print("\n--- cell_biology ---")
    try:
        from biomni.tool import cell_biology

        # analyze_flow_cytometry: (fcs_path, markers)
        if paths.get('fcs'):
            safe_test(results, "cell_biology.analyze_flow_cytometry_immunophenotyping",
                      lambda: cell_biology.analyze_flow_cytometry_immunophenotyping(
                          paths['fcs'], markers=['FITC', 'PE']))

        # analyze_mito: (image_path, channel)
        if paths.get('image'):
            safe_test(results, "cell_biology.analyze_mitochondrial_morphology_and_potential",
                      lambda: cell_biology.analyze_mitochondrial_morphology_and_potential(
                          paths['image'], channel='red'))

    except ImportError as e:
        results.add("cell_biology.import", "FAIL", str(e))

    # ========== CANCER BIOLOGY ==========
    print("\n--- cancer_biology ---")
    try:
        from biomni.tool import cancer_biology

        # analyze_ddr: (expression_data, mutation_data, gene_list)
        expr = {'TP53': 10.5, 'BRCA1': 8.2, 'ATM': 12.1}
        mut = {'TP53': 'R273H', 'BRCA1': None}
        safe_test(results, "cancer_biology.analyze_ddr_network_in_cancer",
                  lambda: cancer_biology.analyze_ddr_network_in_cancer(
                      expr, mut, gene_list=['TP53', 'BRCA1', 'ATM']))

        # perform_nmf: (expression_matrix, n_components)
        expr_matrix = np.random.rand(100, 50)  # 100 samples, 50 genes
        safe_test(results, "cancer_biology.perform_gene_expression_nmf_analysis",
                  lambda: cancer_biology.perform_gene_expression_nmf_analysis(
                      expr_matrix, n_components=5))

    except ImportError as e:
        results.add("cancer_biology.import", "FAIL", str(e))

    # ========== PHYSIOLOGY ==========
    print("\n--- physiology ---")
    try:
        from biomni.tool import physiology

        # analyze_fatty_acid: (retention_times, peak_areas, standards)
        safe_test(results, "physiology.analyze_fatty_acid_composition_by_gc",
                  lambda: physiology.analyze_fatty_acid_composition_by_gc(
                      retention_times=[1.0, 2.0, 3.0, 4.0],
                      peak_areas=[1000, 2000, 1500, 800],
                      standards={'C16:0': 1.0, 'C18:0': 2.0, 'C18:1': 3.0, 'C18:2': 4.0}))

        if paths.get('image'):
            safe_test(results, "physiology.analyze_protein_colocalization",
                      lambda: physiology.analyze_protein_colocalization(
                          paths['image'], paths['image']))
            safe_test(results, "physiology.quantify_amyloid_beta_plaques",
                      lambda: physiology.quantify_amyloid_beta_plaques(paths['image']))

    except ImportError as e:
        results.add("physiology.import", "FAIL", str(e))

    # ========== PATHOLOGY ==========
    print("\n--- pathology ---")
    try:
        from biomni.tool import pathology

        # analyze_atp: (luminescence_values, standard_curve)
        safe_test(results, "pathology.analyze_atp_luminescence_assay",
                  lambda: pathology.analyze_atp_luminescence_assay(
                      luminescence_values=[1000, 1200, 800, 900],
                      standard_curve={'atp_conc': [0, 1, 10, 100], 'lum': [100, 500, 2000, 10000]}))

        if paths.get('image'):
            safe_test(results, "pathology.analyze_aortic_diameter_and_geometry",
                      lambda: pathology.analyze_aortic_diameter_and_geometry(paths['image']))
            safe_test(results, "pathology.analyze_thrombus_histology",
                      lambda: pathology.analyze_thrombus_histology(paths['image']))

            # quantify_corneal: (image, marker_channel)
            safe_test(results, "pathology.quantify_corneal_nerve_fibers",
                      lambda: pathology.quantify_corneal_nerve_fibers(
                          paths['image'], marker_channel='green'))

            # analyze_calcium: (image_stack, baseline_frames)
            safe_test(results, "pathology.analyze_intracellular_calcium_with_rhod2",
                      lambda: pathology.analyze_intracellular_calcium_with_rhod2(
                          paths['image'], baseline_frames=10))

            # segment_multiplexed: (image, markers)
            safe_test(results, "pathology.segment_and_quantify_cells_in_multiplexed_images",
                      lambda: pathology.segment_and_quantify_cells_in_multiplexed_images(
                          paths['image'], markers=['DAPI', 'CD3', 'CD8']))

    except ImportError as e:
        results.add("pathology.import", "FAIL", str(e))

    # ========== BIOENGINEERING ==========
    print("\n--- bioengineering ---")
    try:
        from biomni.tool import bioengineering

        if paths.get('image'):
            safe_test(results, "bioengineering.analyze_myofiber_morphology",
                      lambda: bioengineering.analyze_myofiber_morphology(paths['image']))

        # decode_behavior: (neural_data, labels)
        neural = np.random.randn(100, 50)  # 100 time points, 50 neurons
        labels = np.random.choice(['left', 'right'], 100)
        safe_test(results, "bioengineering.decode_behavior_from_neural_trajectories",
                  lambda: bioengineering.decode_behavior_from_neural_trajectories(
                      neural, labels))

    except ImportError as e:
        results.add("bioengineering.import", "FAIL", str(e))

    # ========== GENETICS ==========
    print("\n--- genetics ---")
    try:
        from biomni.tool import genetics

        # liftover: (coordinates, from_assembly, to_assembly)
        safe_test(results, "genetics.liftover_coordinates",
                  lambda: genetics.liftover_coordinates(
                      [("chr1", 1000000), ("chr2", 2000000)], "hg19", "hg38"))

        # bayesian_finemapping: (summary_stats, ld_matrix, n_causal)
        summary = {
            'beta': np.random.randn(100),
            'se': np.abs(np.random.randn(100)) * 0.1,
            'snp': [f'rs{i}' for i in range(100)]
        }
        ld = np.eye(100) + np.random.randn(100, 100) * 0.1
        ld = (ld + ld.T) / 2  # make symmetric
        safe_test(results, "genetics.bayesian_finemapping_with_deep_vi",
                  lambda: genetics.bayesian_finemapping_with_deep_vi(
                      summary, ld, n_causal=3))

        # fit_genomic_prediction: (genotypes, phenotypes, method)
        geno = np.random.randint(0, 3, (100, 1000))  # 100 samples, 1000 SNPs
        pheno = np.random.randn(100)
        safe_test(results, "genetics.fit_genomic_prediction_model",
                  lambda: genetics.fit_genomic_prediction_model(
                      geno, pheno, method='gblup'))

        # pcr_and_gel: already tested, works

        # simulate_demography: (sample_sizes, population_configs)
        safe_test(results, "genetics.simulate_demographic_history",
                  lambda: genetics.simulate_demographic_history(
                      sample_sizes=[10, 10],
                      population_configs=[
                          {'initial_size': 10000, 'growth_rate': 0},
                          {'initial_size': 10000, 'growth_rate': 0}
                      ]))

    except ImportError as e:
        results.add("genetics.import", "FAIL", str(e))

    # ========== LAB AUTOMATION ==========
    print("\n--- lab_automation ---")
    try:
        from biomni.tool import lab_automation

        script_path = str(TEST_DATA_DIR / "test_script.py")
        with open(script_path, 'w') as f:
            f.write("from pylabrobot.liquid_handling import LiquidHandler\nlh = LiquidHandler()")
        safe_test(results, "lab_automation.test_pylabrobot_script",
                  lambda: lab_automation.test_pylabrobot_script(script_path))

    except ImportError as e:
        results.add("lab_automation.import", "FAIL", str(e))

    # Summary
    results.summary()

    # Save
    with open("/tmp/biomni_skipped_test_v2.json", 'w') as f:
        json.dump({"passed": results.passed, "failed": results.failed}, f, indent=2)
    print(f"\nResults saved to /tmp/biomni_skipped_test_v2.json")


if __name__ == "__main__":
    run_tests()
