#!/usr/bin/env python3
"""
Test ONLY the previously skipped Biomni tools - v3 with CORRECT signatures.
Based on systematic audit of actual function signatures.
"""

import os
import sys
import json
import numpy as np
from pathlib import Path

TEST_DATA_DIR = Path("/tmp/biomni_test_v3")
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
            print(f"  [PASS] {name}")
        else:
            self.failed.append(entry)
            print(f"  [FAIL] {name}: {msg[:100]}")

    def summary(self):
        total = len(self.passed) + len(self.failed)
        rate = 100*len(self.passed)/max(1,total)
        print(f"\n{'='*60}")
        print(f"SKIPPED TOOLS TEST v3: {len(self.passed)}/{total} PASSED ({rate:.0f}%)")
        print(f"{'='*60}")
        return {"passed": len(self.passed), "total": total, "rate": rate}


def safe_test(results, name, func):
    try:
        result = func()
        results.add(name, "PASS", str(result)[:50] if result else "OK")
    except Exception as e:
        results.add(name, "FAIL", str(e))


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

        # Second image for multi-channel tests
        img2 = np.random.randint(50, 200, (256, 256), dtype=np.uint8)
        img2_path = str(TEST_DATA_DIR / "mock_image2.png")
        Image.fromarray(img2).save(img2_path)
        paths['image2'] = img2_path

        # Third image
        img3 = np.random.randint(30, 180, (256, 256), dtype=np.uint8)
        img3_path = str(TEST_DATA_DIR / "mock_image3.png")
        Image.fromarray(img3).save(img3_path)
        paths['image3'] = img3_path
    except:
        paths['image'] = None
        paths['image2'] = None
        paths['image3'] = None

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
        f.write(f">seq1\n{SAMPLE_DNA}\n>seq2\nGCTAGCTAGCTAGCTAGCTA\n")
    paths['fasta'] = fasta_path

    # Mock BED
    bed_path = str(TEST_DATA_DIR / "mock.bed")
    with open(bed_path, 'w') as f:
        f.write("chr1\t100\t200\tpeak1\t100\t+\nchr1\t300\t400\tpeak2\t150\t+\n")
    paths['bed'] = bed_path

    # Mock BAM (requires pysam)
    try:
        import pysam
        bam_path = str(TEST_DATA_DIR / "mock.bam")
        header = {'HD': {'VN': '1.0'}, 'SQ': [{'LN': 1000, 'SN': 'chr1'}]}
        with pysam.AlignmentFile(bam_path, "wb", header=header) as outf:
            a = pysam.AlignedSegment()
            a.query_name = "read1"
            a.query_sequence = "ATGC" * 25
            a.flag = 0
            a.reference_id = 0
            a.reference_start = 100
            a.mapping_quality = 60
            a.cigar = [(0, 100)]
            a.query_qualities = pysam.qualitystring_to_array("I" * 100)
            outf.write(a)
        pysam.index(bam_path)
        paths['bam'] = bam_path
    except:
        paths['bam'] = None

    # Mock CSV for tumor growth data (correct format)
    csv_path = str(TEST_DATA_DIR / "tumor_growth.csv")
    import csv
    with open(csv_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['time', 'volume', 'group', 'subject'])
        for subj in range(1, 6):
            for t in range(0, 21, 7):
                vol = 100 + t * 10 + np.random.randn() * 5
                writer.writerow([t, vol, 'control', f'subj_{subj}'])
        for subj in range(6, 11):
            for t in range(0, 21, 7):
                vol = 100 + t * 5 + np.random.randn() * 5
                writer.writerow([t, vol, 'treatment', f'subj_{subj}'])
    paths['tumor_csv'] = csv_path

    # Mock SBML reaction network (correct format)
    paths['reaction_network'] = [
        {"id": "v1", "name": "A to B", "reactants": ["A"], "products": ["B"],
         "kinetic_law": "k1 * A", "reversible": False},
        {"id": "v2", "name": "B to C", "reactants": ["B"], "products": ["C"],
         "kinetic_law": "k2 * B", "reversible": False}
    ]
    paths['kinetic_params'] = {"k1": 0.1, "k2": 0.05}

    # Mock SBML model file
    sbml_path = str(TEST_DATA_DIR / "mock_model.xml")
    with open(sbml_path, 'w') as f:
        f.write("""<?xml version="1.0" encoding="UTF-8"?>
<sbml xmlns="http://www.sbml.org/sbml/level3/version2/core" level="3" version="2">
  <model id="test_model">
    <listOfCompartments>
      <compartment id="c" size="1"/>
    </listOfCompartments>
    <listOfSpecies>
      <species id="A" compartment="c" initialConcentration="1"/>
      <species id="B" compartment="c" initialConcentration="0"/>
    </listOfSpecies>
    <listOfReactions>
      <reaction id="v1" reversible="false">
        <listOfReactants><speciesReference species="A"/></listOfReactants>
        <listOfProducts><speciesReference species="B"/></listOfProducts>
      </reaction>
    </listOfReactions>
  </model>
</sbml>
""")
    paths['sbml_model'] = sbml_path

    # Mock expression and mutation data for cancer biology
    expr_path = str(TEST_DATA_DIR / "expression_data.csv")
    mut_path = str(TEST_DATA_DIR / "mutation_data.csv")
    with open(expr_path, 'w') as f:
        f.write("gene,sample1,sample2,sample3\n")
        f.write("BRCA1,5.2,4.8,6.1\nATM,3.1,2.9,3.5\nTP53,7.2,6.8,7.5\n")
    with open(mut_path, 'w') as f:
        f.write("gene,sample1,sample2,sample3\n")
        f.write("BRCA1,1,0,1\nATM,0,1,0\nTP53,1,1,0\n")
    paths['expression_csv'] = expr_path
    paths['mutation_csv'] = mut_path

    # Mock GC data file
    gc_path = str(TEST_DATA_DIR / "gc_data.csv")
    with open(gc_path, 'w') as f:
        f.write("retention_time,area,compound\n")
        f.write("5.2,12500,C16:0\n8.4,8900,C18:0\n10.1,15600,C18:1\n12.3,6700,C18:2\n")
    paths['gc_data'] = gc_path

    # Mock ATP luminescence data
    atp_data_path = str(TEST_DATA_DIR / "atp_data.csv")
    atp_std_path = str(TEST_DATA_DIR / "atp_standard.csv")
    with open(atp_data_path, 'w') as f:
        f.write("sample,luminescence\n")
        for i in range(12):
            f.write(f"sample_{i},{np.random.randint(1000, 10000)}\n")
    with open(atp_std_path, 'w') as f:
        f.write("concentration,luminescence\n")
        for conc in [0, 0.1, 1, 10, 100]:
            f.write(f"{conc},{conc * 100 + np.random.randn() * 10}\n")
    paths['atp_data'] = atp_data_path
    paths['atp_standard'] = atp_std_path

    # Mock GWAS summary stats
    gwas_path = str(TEST_DATA_DIR / "gwas_summary.txt")
    with open(gwas_path, 'w') as f:
        f.write("SNP\tCHR\tPOS\tBETA\tSE\tP\n")
        for i in range(100):
            f.write(f"rs{i}\t1\t{i*1000}\t{np.random.randn()*0.1}\t0.05\t{np.random.uniform(0.001, 0.5)}\n")
    paths['gwas_summary'] = gwas_path

    # Mock LD matrix
    ld_matrix = np.eye(100) + np.random.randn(100, 100) * 0.1
    ld_matrix = (ld_matrix + ld_matrix.T) / 2
    np.fill_diagonal(ld_matrix, 1)
    paths['ld_matrix'] = ld_matrix

    # Mock waste characteristics for anaerobic digestion
    paths['waste_chars'] = {
        "vs_content": 0.75,  # Volatile solids
        "ts_content": 0.15,  # Total solids
        "c_to_n_ratio": 25,
        "ph": 7.2,
        "temperature": 35
    }
    paths['operational_params'] = {
        "hrt": 20,  # Hydraulic retention time (days)
        "organic_loading_rate": 2.5,  # kg VS/m3/day
        "temperature": 37
    }

    # Mock arsenic speciation data
    paths['arsenic_data'] = [
        {"retention_time": 2.5, "intensity": 15000, "species": "As(III)"},
        {"retention_time": 4.2, "intensity": 8500, "species": "As(V)"},
        {"retention_time": 6.1, "intensity": 3200, "species": "MMA"},
    ]
    paths['arsenic_calibration'] = {
        "As(III)": {"slope": 1000, "intercept": 100},
        "As(V)": {"slope": 950, "intercept": 80},
        "MMA": {"slope": 850, "intercept": 50}
    }

    # Mock EBV antibody data
    paths['ebv_od_data'] = str(TEST_DATA_DIR / "ebv_od.csv")
    paths['ebv_std_data'] = str(TEST_DATA_DIR / "ebv_std.csv")
    with open(paths['ebv_od_data'], 'w') as f:
        f.write("sample,OD450\n")
        for i in range(10):
            f.write(f"patient_{i},{np.random.uniform(0.1, 2.0)}\n")
    with open(paths['ebv_std_data'], 'w') as f:
        f.write("concentration,OD450\n")
        for conc in [0, 10, 50, 100, 500]:
            f.write(f"{conc},{np.log10(conc + 1) * 0.5 + np.random.randn() * 0.05}\n")

    # Mock flow cytometry data for cell cycle
    paths['flow_data'] = str(TEST_DATA_DIR / "flow_cytometry.csv")
    with open(paths['flow_data'], 'w') as f:
        f.write("PI_intensity\n")
        # G1 phase cells (2N DNA)
        for _ in range(500):
            f.write(f"{np.random.normal(100, 10)}\n")
        # S phase cells (2N-4N DNA)
        for _ in range(200):
            f.write(f"{np.random.normal(150, 20)}\n")
        # G2/M phase cells (4N DNA)
        for _ in range(300):
            f.write(f"{np.random.normal(200, 10)}\n")

    # Mock neural data for decoding
    n_trials, n_timepoints, n_neurons = 50, 100, 20
    paths['neural_data'] = np.random.randn(n_trials, n_timepoints, n_neurons)
    paths['behavioral_data'] = np.random.randn(n_trials, n_timepoints, 2)  # x, y position

    return paths


def run_tests():
    print("="*60)
    print("TESTING PREVIOUSLY SKIPPED TOOLS - v3 (CORRECT SIGNATURES)")
    print("="*60)

    print("\nCreating mock data...")
    paths = setup_mock_data()
    print(f"Created: {list(paths.keys())}")

    results = Results()

    # Import modules
    from biomni.tool import literature, genomics, biochemistry, microbiology
    from biomni.tool import biophysics, pharmacology, synthetic_biology, systems_biology
    from biomni.tool import immunology, cell_biology, cancer_biology, physiology
    from biomni.tool import pathology, bioengineering, genetics, lab_automation

    # --- LITERATURE ---
    print("\n--- literature ---")
    safe_test(results, "literature.extract_pdf_content",
        lambda: literature.extract_pdf_content("https://arxiv.org/pdf/2001.00001.pdf"))
    safe_test(results, "literature.fetch_supplementary_info_from_doi",
        lambda: literature.fetch_supplementary_info_from_doi("10.1038/s41586-020-2649-2"))

    # --- GENOMICS ---
    print("\n--- genomics ---")
    safe_test(results, "genomics.find_enriched_motifs_with_homer",
        lambda: genomics.find_enriched_motifs_with_homer(paths['bed'], "hg38", str(TEST_DATA_DIR / "homer_out")))
    safe_test(results, "genomics.generate_gene_embeddings_with_ESM_models",
        lambda: genomics.generate_gene_embeddings_with_ESM_models([SAMPLE_PROTEIN[:50]]))
    # scRNA functions need data_lake_path with models - mark as expected to fail
    safe_test(results, "genomics.annotate_celltype_scRNA",
        lambda: (_ for _ in ()).throw(Exception("Needs data_lake_path with celltype models")))
    safe_test(results, "genomics.create_harmony_embeddings_scRNA",
        lambda: (_ for _ in ()).throw(Exception("Needs proper data_dir structure")))
    safe_test(results, "genomics.create_scvi_embeddings_scRNA",
        lambda: (_ for _ in ()).throw(Exception("Needs batch_key, label_key, data_dir")))

    # --- BIOCHEMISTRY ---
    print("\n--- biochemistry ---")
    safe_test(results, "biochemistry.analyze_itc_binding_thermodynamics",
        lambda: biochemistry.analyze_itc_binding_thermodynamics(
            {"time": [0, 60, 120, 180, 240, 300], "heat": [0, -5.2, -4.8, -4.1, -3.2, -2.1]},
            {"cell_volume": 1.4e-3, "syringe_concentration": 1e-3, "cell_concentration": 1e-4}))

    # --- MICROBIOLOGY ---
    print("\n--- microbiology ---")
    safe_test(results, "microbiology.count_bacterial_colonies",
        lambda: microbiology.count_bacterial_colonies(paths['image'], str(TEST_DATA_DIR / "colonies_out")))
    safe_test(results, "microbiology.segment_and_analyze_microbial_cells",
        lambda: microbiology.segment_and_analyze_microbial_cells(paths['image']))
    safe_test(results, "microbiology.segment_cells_with_deep_learning",
        lambda: microbiology.segment_cells_with_deep_learning(paths['image']))
    # CORRECT SIGNATURE: (waste_characteristics, operational_parameters, target_output, optimization_method)
    safe_test(results, "microbiology.optimize_anaerobic_digestion_process",
        lambda: microbiology.optimize_anaerobic_digestion_process(
            waste_characteristics=paths['waste_chars'],
            operational_parameters=paths['operational_params'],
            target_output="methane",
            optimization_method="response_surface"))
    # CORRECT SIGNATURE: (sample_data, sample_name, calibration_data)
    safe_test(results, "microbiology.analyze_arsenic_speciation_hplc_icpms",
        lambda: microbiology.analyze_arsenic_speciation_hplc_icpms(
            sample_data=paths['arsenic_data'],
            sample_name="soil_sample_1",
            calibration_data=paths['arsenic_calibration']))
    safe_test(results, "microbiology.annotate_bacterial_genome",
        lambda: microbiology.annotate_bacterial_genome(paths['fasta'], str(TEST_DATA_DIR / "annotation_out")))

    # --- BIOPHYSICS ---
    print("\n--- biophysics ---")
    safe_test(results, "biophysics.analyze_cell_morphology_and_cytoskeleton",
        lambda: biophysics.analyze_cell_morphology_and_cytoskeleton(paths['image']))

    # --- PHARMACOLOGY ---
    print("\n--- pharmacology ---")
    safe_test(results, "pharmacology.calculate_physicochemical_properties",
        lambda: pharmacology.calculate_physicochemical_properties(SAMPLE_SMILES))
    # docking_autodock_vina needs PyScreener installed correctly
    safe_test(results, "pharmacology.docking_autodock_vina",
        lambda: (_ for _ in ()).throw(Exception("Needs PyScreener with correct setup")))
    # run_autosite needs prepare_receptor binary
    safe_test(results, "pharmacology.run_autosite",
        lambda: (_ for _ in ()).throw(Exception("Needs prepare_receptor binary from MGLTools")))
    # CORRECT SIGNATURE: (blot_image_path, target_bands, loading_control_band, antibody_info, output_dir)
    safe_test(results, "pharmacology.analyze_western_blot",
        lambda: pharmacology.analyze_western_blot(
            blot_image_path=paths['image'],
            target_bands=["band1", "band2"],
            loading_control_band="GAPDH",
            antibody_info={"primary": "anti-target", "secondary": "anti-rabbit"},
            output_dir=str(TEST_DATA_DIR / "western_out")))
    safe_test(results, "pharmacology.grade_adverse_events_using_vcog_ctcae",
        lambda: pharmacology.grade_adverse_events_using_vcog_ctcae(
            [{"event": "Vomiting", "frequency": 3, "duration_hours": 2},
             {"event": "Diarrhea", "frequency": 2, "duration_hours": 4}]))
    # CORRECT SIGNATURE: (data_path, time_column, volume_column, group_column, subject_column, output_dir)
    safe_test(results, "pharmacology.analyze_xenograft_tumor_growth_inhibition",
        lambda: pharmacology.analyze_xenograft_tumor_growth_inhibition(
            data_path=paths['tumor_csv'],
            time_column='time',
            volume_column='volume',
            group_column='group',
            subject_column='subject',
            output_dir=str(TEST_DATA_DIR / "tumor_out")))
    # CORRECT SIGNATURE: (formulations, storage_conditions, time_points)
    safe_test(results, "pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations",
        lambda: pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations(
            formulations={"form1": {"active_content": 100, "ph": 6.5}},
            storage_conditions={"25C_60RH": {"temp": 25, "rh": 60}},
            time_points=[0, 1, 3, 6, 12]))
    # CORRECT SIGNATURE: (time_points, tissue_data)
    safe_test(results, "pharmacology.analyze_radiolabeled_antibody_biodistribution",
        lambda: pharmacology.analyze_radiolabeled_antibody_biodistribution(
            time_points=[1, 4, 24, 48, 72],
            tissue_data={"blood": [10, 8, 4, 2, 1], "tumor": [2, 5, 8, 10, 9], "liver": [5, 8, 6, 4, 3]}))
    # CORRECT SIGNATURE: (biodistribution_data, radiation_parameters, output_file)
    safe_test(results, "pharmacology.estimate_alpha_particle_radiotherapy_dosimetry",
        lambda: pharmacology.estimate_alpha_particle_radiotherapy_dosimetry(
            biodistribution_data={"tumor": {"activity": [100, 80, 50], "time": [0, 24, 48]}},
            radiation_parameters={"isotope": "Ac-225", "energy_MeV": 5.8},
            output_file=str(TEST_DATA_DIR / "dosimetry.json")))
    safe_test(results, "pharmacology.perform_mwas_cyp2c19_metabolizer_status",
        lambda: pharmacology.perform_mwas_cyp2c19_metabolizer_status(
            np.random.randn(100, 50), np.random.choice(["PM", "IM", "EM", "UM"], 100)))
    # CORRECT SIGNATURE: (chondrocyte_cells, test_compounds, culture_duration_days, measurement_intervals)
    safe_test(results, "pharmacology.run_3d_chondrogenic_aggregate_assay",
        lambda: pharmacology.run_3d_chondrogenic_aggregate_assay(
            chondrocyte_cells={"cell_count": 50000, "passage": 3, "source": "human"},
            test_compounds=[{"name": "TGF-b", "concentration": "10ng/mL"}],
            culture_duration_days=21,
            measurement_intervals=[0, 7, 14, 21]))

    # --- SYNTHETIC_BIOLOGY ---
    print("\n--- synthetic_biology ---")
    # CORRECT SIGNATURE: (reaction_network, kinetic_parameters, output_file)
    safe_test(results, "synthetic_biology.create_biochemical_network_sbml_model",
        lambda: synthetic_biology.create_biochemical_network_sbml_model(
            reaction_network=paths['reaction_network'],
            kinetic_parameters=paths['kinetic_params'],
            output_file=str(TEST_DATA_DIR / "network.xml")))
    safe_test(results, "synthetic_biology.analyze_barcode_sequencing_data",
        lambda: synthetic_biology.analyze_barcode_sequencing_data(
            str(TEST_DATA_DIR / "barcodes.txt") if os.path.exists(str(TEST_DATA_DIR / "barcodes.txt"))
            else _create_barcode_file(str(TEST_DATA_DIR / "barcodes.txt"))))

    # --- SYSTEMS_BIOLOGY ---
    print("\n--- systems_biology ---")
    safe_test(results, "systems_biology.query_chatnt",
        lambda: systems_biology.query_chatnt(SAMPLE_DNA))
    safe_test(results, "systems_biology.simulate_renin_angiotensin_system_dynamics",
        lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(
            {"renin": 1.0, "angiotensinogen": 100.0, "ACE": 10.0},
            {"k_renin": 0.1, "k_ACE": 0.05, "k_decay": 0.01},
            100, 1000))
    # CORRECT SIGNATURE: (model_file, initial_concentrations, perturbation_params, simulation_time, time_points)
    safe_test(results, "systems_biology.simulate_metabolic_network_perturbation",
        lambda: systems_biology.simulate_metabolic_network_perturbation(
            model_file=paths['sbml_model'],
            initial_concentrations={"A": 1.0, "B": 0.0},
            perturbation_params={"A": 0.5},
            simulation_time=100,
            time_points=100))
    safe_test(results, "systems_biology.compare_protein_structures",
        lambda: systems_biology.compare_protein_structures(paths['pdb'], paths['pdb']))

    # --- IMMUNOLOGY ---
    print("\n--- immunology ---")
    # CORRECT SIGNATURE: (raw_od_data, standard_curve_data, sample_metadata, output_dir)
    safe_test(results, "immunology.analyze_ebv_antibody_titers",
        lambda: immunology.analyze_ebv_antibody_titers(
            raw_od_data=paths['ebv_od_data'],
            standard_curve_data=paths['ebv_std_data'],
            sample_metadata={"patient_0": {"age": 35, "sex": "M"}},
            output_dir=str(TEST_DATA_DIR / "ebv_out")))
    # CORRECT SIGNATURE: (flow_cytometry_data, initial_estimates)
    safe_test(results, "immunology.estimate_cell_cycle_phase_durations",
        lambda: immunology.estimate_cell_cycle_phase_durations(
            flow_cytometry_data=paths['flow_data'],
            initial_estimates={"G1": 10, "S": 8, "G2M": 4}))
    safe_test(results, "immunology.analyze_cns_lesion_histology",
        lambda: immunology.analyze_cns_lesion_histology(paths['image']))
    safe_test(results, "immunology.analyze_immunohistochemistry_image",
        lambda: immunology.analyze_immunohistochemistry_image(paths['image']))

    # --- CELL_BIOLOGY ---
    print("\n--- cell_biology ---")
    # CORRECT SIGNATURE: (morphology_image_path, potential_image_path, output_dir)
    safe_test(results, "cell_biology.analyze_mitochondrial_morphology_and_potential",
        lambda: cell_biology.analyze_mitochondrial_morphology_and_potential(
            morphology_image_path=paths['image'],
            potential_image_path=paths['image2'],
            output_dir=str(TEST_DATA_DIR / "mito_out")))

    # --- CANCER_BIOLOGY ---
    print("\n--- cancer_biology ---")
    # CORRECT SIGNATURE: (expression_data_path, mutation_data_path, output_dir)
    safe_test(results, "cancer_biology.analyze_ddr_network_in_cancer",
        lambda: cancer_biology.analyze_ddr_network_in_cancer(
            expression_data_path=paths['expression_csv'],
            mutation_data_path=paths['mutation_csv'],
            output_dir=str(TEST_DATA_DIR / "ddr_out")))
    safe_test(results, "cancer_biology.perform_gene_expression_nmf_analysis",
        lambda: cancer_biology.perform_gene_expression_nmf_analysis(
            np.random.rand(100, 50), 5))

    # --- PHYSIOLOGY ---
    print("\n--- physiology ---")
    # CORRECT SIGNATURE: (gc_data_file, tissue_type, sample_id, output_directory)
    safe_test(results, "physiology.analyze_fatty_acid_composition_by_gc",
        lambda: physiology.analyze_fatty_acid_composition_by_gc(
            gc_data_file=paths['gc_data'],
            tissue_type="liver",
            sample_id="sample_001",
            output_directory=str(TEST_DATA_DIR / "fatty_acid_out")))
    safe_test(results, "physiology.analyze_protein_colocalization",
        lambda: physiology.analyze_protein_colocalization(paths['image'], paths['image2']))
    safe_test(results, "physiology.quantify_amyloid_beta_plaques",
        lambda: physiology.quantify_amyloid_beta_plaques(paths['image']))

    # --- PATHOLOGY ---
    print("\n--- pathology ---")
    # CORRECT SIGNATURE: (data_file, standard_curve_file, normalization_method, normalization_data)
    safe_test(results, "pathology.analyze_atp_luminescence_assay",
        lambda: pathology.analyze_atp_luminescence_assay(
            data_file=paths['atp_data'],
            standard_curve_file=paths['atp_standard'],
            normalization_method="protein",
            normalization_data={"sample_0": 1.2, "sample_1": 1.1}))
    safe_test(results, "pathology.analyze_aortic_diameter_and_geometry",
        lambda: pathology.analyze_aortic_diameter_and_geometry(paths['image']))
    safe_test(results, "pathology.analyze_thrombus_histology",
        lambda: pathology.analyze_thrombus_histology(paths['image'], str(TEST_DATA_DIR / "thrombus_out")))
    # CORRECT SIGNATURE: (image_path, marker_type, output_dir, threshold_method)
    safe_test(results, "pathology.quantify_corneal_nerve_fibers",
        lambda: pathology.quantify_corneal_nerve_fibers(
            image_path=paths['image'],
            marker_type="tubulin",
            output_dir=str(TEST_DATA_DIR / "cornea_out"),
            threshold_method="otsu"))
    # CORRECT SIGNATURE: (background_image_path, control_image_path, sample_image_path, output_dir)
    safe_test(results, "pathology.analyze_intracellular_calcium_with_rhod2",
        lambda: pathology.analyze_intracellular_calcium_with_rhod2(
            background_image_path=paths['image'],
            control_image_path=paths['image2'],
            sample_image_path=paths['image3'],
            output_dir=str(TEST_DATA_DIR / "calcium_out")))
    # CORRECT SIGNATURE: (image_path, markers_list, nuclear_channel_index, output_dir)
    safe_test(results, "pathology.segment_and_quantify_cells_in_multiplexed_images",
        lambda: pathology.segment_and_quantify_cells_in_multiplexed_images(
            image_path=paths['image'],
            markers_list=["CD3", "CD4", "CD8"],
            nuclear_channel_index=0,
            output_dir=str(TEST_DATA_DIR / "multiplex_out")))

    # --- BIOENGINEERING ---
    print("\n--- bioengineering ---")
    safe_test(results, "bioengineering.analyze_myofiber_morphology",
        lambda: bioengineering.analyze_myofiber_morphology(paths['image']))
    # CORRECT SIGNATURE: (neural_data, behavioral_data, n_components, output_dir)
    safe_test(results, "bioengineering.decode_behavior_from_neural_trajectories",
        lambda: bioengineering.decode_behavior_from_neural_trajectories(
            neural_data=paths['neural_data'],
            behavioral_data=paths['behavioral_data'],
            n_components=5,
            output_dir=str(TEST_DATA_DIR / "neural_out")))

    # --- GENETICS ---
    print("\n--- genetics ---")
    # CORRECT SIGNATURE: (chromosome, position, input_format, output_format, data_path)
    safe_test(results, "genetics.liftover_coordinates",
        lambda: genetics.liftover_coordinates(
            chromosome="chr1",
            position=12345,
            input_format="hg19",
            output_format="hg38",
            data_path=str(TEST_DATA_DIR)))  # Needs chain files
    # CORRECT SIGNATURE: (gwas_summary_path, ld_matrix, n_iterations, learning_rate, hidden_dim, credible_threshold)
    safe_test(results, "genetics.bayesian_finemapping_with_deep_vi",
        lambda: genetics.bayesian_finemapping_with_deep_vi(
            gwas_summary_path=paths['gwas_summary'],
            ld_matrix=paths['ld_matrix'],
            n_iterations=100,
            learning_rate=0.01,
            hidden_dim=32,
            credible_threshold=0.95))
    # CORRECT SIGNATURE: (genotypes, phenotypes, fixed_effects, model_type, output_file)
    safe_test(results, "genetics.fit_genomic_prediction_model",
        lambda: genetics.fit_genomic_prediction_model(
            genotypes=np.random.randint(0, 3, (100, 50)),
            phenotypes=np.random.randn(100),
            fixed_effects=None,
            model_type="additive",
            output_file=str(TEST_DATA_DIR / "gp_model.pkl")))
    # CORRECT SIGNATURE: (num_samples, sequence_length, recombination_rate, mutation_rate,
    #                     demographic_model, demographic_params, coalescent_model, beta_coalescent_param,
    #                     random_seed, output_file)
    safe_test(results, "genetics.simulate_demographic_history",
        lambda: genetics.simulate_demographic_history(
            num_samples=20,
            sequence_length=10000,
            recombination_rate=1e-8,
            mutation_rate=1e-8,
            demographic_model="constant",
            demographic_params={"Ne": 10000},
            coalescent_model="hudson",
            beta_coalescent_param=None,
            random_seed=42,
            output_file=str(TEST_DATA_DIR / "simulation.trees")))

    # --- LAB_AUTOMATION ---
    print("\n--- lab_automation ---")
    safe_test(results, "lab_automation.test_pylabrobot_script",
        lambda: lab_automation.test_pylabrobot_script("print('Hello from PyLabRobot')"))

    # Summary
    summary = results.summary()

    # Save results
    output_file = Path("/tmp/biomni_skipped_test_v3.json")
    with open(output_file, 'w') as f:
        json.dump({
            "summary": summary,
            "passed": results.passed,
            "failed": results.failed
        }, f, indent=2)
    print(f"\nResults saved to {output_file}")


def _create_barcode_file(path):
    """Helper to create barcode file"""
    with open(path, 'w') as f:
        for i in range(100):
            barcode = ''.join(np.random.choice(['A', 'T', 'G', 'C'], 20))
            f.write(f"{barcode}\t{np.random.randint(1, 1000)}\n")
    return path


if __name__ == "__main__":
    run_tests()
