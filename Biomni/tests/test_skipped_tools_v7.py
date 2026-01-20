#!/usr/bin/env python3
"""
Test previously skipped Biomni tools - v7 with working scRNA tests.

Changes from v5:
1. Harmony and scVI tests now actually run with proper AnnData
2. annotate_celltype_scRNA still needs API key
3. Docking tools documented with ARM64 limitations

Author: BioMate Testing Framework
Date: 2026-01-19
"""

import os
import sys
import json
import numpy as np
from pathlib import Path

TEST_DATA_DIR = Path("/tmp/biomni_test_v7")
TEST_DATA_DIR.mkdir(exist_ok=True)

SAMPLE_PROTEIN = "MKFLILLFNILCLFPVLAADNHGVGPQGASGVDPITFDINSNQTGVQLTLNSTGSEEECKFSLFLKWFEPG"
SAMPLE_DNA = "ATGAAATTCCTGATCCTGCTGTTCAACATCCTGTGCCTGTTCCCTGTGCTGGCTGCTGACAAC"
SAMPLE_SMILES = "CC(=O)OC1=CC=CC=C1C(=O)O"


class Results:
    def __init__(self):
        self.passed = []
        self.failed = []

    def add(self, name, status, msg=""):
        entry = {"name": name, "message": msg[:300]}
        if status == "PASS":
            self.passed.append(entry)
            print(f"  [PASS] {name}")
        else:
            self.failed.append(entry)
            print(f"  [FAIL] {name}: {msg[:120]}")

    def summary(self):
        total = len(self.passed) + len(self.failed)
        rate = 100*len(self.passed)/max(1,total)
        print(f"\n{'='*60}")
        print(f"SKIPPED TOOLS TEST v7: {len(self.passed)}/{total} PASSED ({rate:.0f}%)")
        print(f"{'='*60}")
        return {"passed": len(self.passed), "total": total, "rate": rate}


def safe_test(results, name, func):
    try:
        result = func()
        results.add(name, "PASS", str(result)[:100] if result else "OK")
    except Exception as e:
        results.add(name, "FAIL", str(e))


def setup_mock_data():
    """Create all mock data files with EXACT formats from source code analysis"""
    paths = {}

    # === IMAGES ===
    try:
        from PIL import Image
        img = np.zeros((512, 512), dtype=np.uint8)
        img[:] = 200
        for _ in range(25):
            cx, cy = np.random.randint(50, 462, 2)
            radius = np.random.randint(5, 15)
            for i in range(512):
                for j in range(512):
                    if (i-cx)**2 + (j-cy)**2 < radius**2:
                        img[i,j] = np.random.randint(50, 100)
        img_path = str(TEST_DATA_DIR / "colony_image.png")
        Image.fromarray(img).save(img_path)
        paths['colony_image'] = img_path

        for i, name in enumerate(['image1', 'image2', 'image3']):
            img = np.random.randint(50, 200, (256, 256), dtype=np.uint8)
            p = str(TEST_DATA_DIR / f"{name}.png")
            Image.fromarray(img).save(p)
            paths[name] = p
    except Exception as e:
        print(f"  Warning: Image creation failed: {e}")

    # === SEQUENCE FILES ===
    pdb_path = str(TEST_DATA_DIR / "mock.pdb")
    with open(pdb_path, 'w') as f:
        f.write("ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 20.00           N\n")
        f.write("ATOM      2  CA  ALA A   1       1.458   0.000   0.000  1.00 20.00           C\n")
        f.write("END\n")
    paths['pdb'] = pdb_path

    fasta_path = str(TEST_DATA_DIR / "mock.fasta")
    with open(fasta_path, 'w') as f:
        f.write(f">seq1\n{SAMPLE_DNA}\n")
    paths['fasta'] = fasta_path

    bed_path = str(TEST_DATA_DIR / "mock.bed")
    with open(bed_path, 'w') as f:
        f.write("chr1\t100\t200\tpeak1\t100\t+\n")
    paths['bed'] = bed_path

    # === scRNA AnnData for Harmony and scVI ===
    try:
        import scanpy as sc
        import pandas as pd
        
        scrna_dir = TEST_DATA_DIR / "scrna"
        scrna_dir.mkdir(exist_ok=True)
        
        np.random.seed(42)
        n_cells = 100
        n_genes = 200
        X = np.random.poisson(lam=3, size=(n_cells, n_genes)).astype(np.float32)
        
        adata = sc.AnnData(X)
        adata.obs_names = [f'cell_{i}' for i in range(n_cells)]
        adata.var_names = [f'gene_{i}' for i in range(n_genes)]
        adata.obs['batch'] = np.random.choice(['batch1', 'batch2'], n_cells)
        adata.obs['celltype'] = np.random.choice(['T_cell', 'B_cell', 'Monocyte'], n_cells)
        adata.obs['leiden'] = pd.Categorical(np.random.choice(['0', '1', '2'], n_cells))
        
        sc.pp.normalize_total(adata)
        sc.pp.log1p(adata)
        sc.pp.highly_variable_genes(adata, n_top_genes=50)
        sc.pp.pca(adata, n_comps=30)
        
        adata_path = str(scrna_dir / "test_adata.h5ad")
        adata.write(adata_path)
        paths['scrna_dir'] = str(scrna_dir)
        paths['scrna_adata'] = 'test_adata.h5ad'
    except Exception as e:
        print(f"  Warning: AnnData creation failed: {e}")

    # === MICROBIOLOGY - FIXED FORMATS ===
    paths['waste_characteristics'] = {
        "total_solids": 15.0, "volatile_solids": 75.0, "cod": 50000.0
    }
    paths['operational_parameters'] = {
        "hrt": (10, 30), "olr": (1.0, 4.0), "if_ratio": (0.5, 2.0),
        "temperature": (30, 45), "ph": (6.5, 8.0)
    }
    paths['arsenic_sample_data'] = {
        "sample_001": {2.8: 15000, 7.5: 8500, 3.9: 3200, 6.2: 2100},
        "sample_002": {2.8: 12000, 7.5: 9200, 3.9: 2800, 6.2: 1900}
    }
    paths['arsenic_calibration'] = {
        "As(III)": {"factor": 0.85, "limit": 0.1},
        "As(V)": {"factor": 0.92, "limit": 0.1},
        "MMAs(III)": {"factor": 0.78, "limit": 0.2},
        "MMAs(V)": {"factor": 0.88, "limit": 0.15},
        "DMAs(III)": {"factor": 0.81, "limit": 0.2},
        "DMAs(V)": {"factor": 0.90, "limit": 0.15},
    }

    # === PHARMACOLOGY ===
    paths['western_target_bands'] = [
        {"name": "p53", "roi": [100, 50, 50, 30]},
        {"name": "Bcl-2", "roi": [100, 100, 50, 30]}
    ]
    paths['western_loading_control'] = {"name": "GAPDH", "roi": [100, 200, 50, 30]}
    paths['western_antibody_info'] = {
        "primary": {"name": "anti-p53", "dilution": "1:1000", "source": "mouse"},
        "secondary": {"name": "anti-mouse HRP", "dilution": "1:5000"}
    }
    paths['formulations'] = [{
        "name": "Formulation A", "active_ingredient": "Aspirin",
        "concentration": 100.0, "excipients": ["lactose", "starch", "magnesium stearate"]
    }]
    paths['storage_conditions'] = [
        {"temperature": 25.0, "humidity": 60.0, "description": "Room Temperature"},
        {"temperature": 40.0, "humidity": 75.0, "description": "Accelerated"}
    ]
    paths['time_points'] = [0, 30, 90, 180, 360]
    paths['biodistribution_data'] = {
        "tumor": [(1, 2.5), (4, 8.2), (24, 15.3), (48, 12.1)],
        "blood": [(1, 10.5), (4, 5.2), (24, 1.8), (48, 0.5)],
        "liver": [(1, 5.2), (4, 8.1), (24, 6.3), (48, 4.2)],
        "kidney": [(1, 3.1), (4, 4.5), (24, 3.2), (48, 2.1)]
    }
    paths['radiation_parameters'] = {
        "radionuclide": "Ac-225", "half_life_hours": 240.0,
        "energy_per_decay_MeV": 28.0, "radiation_weighting_factor": 20.0,
        "S_factors": {"tumor_tumor": 5.2e-13, "liver_liver": 3.1e-13}
    }
    paths['chondrocyte_cells'] = {
        "source": "human articular cartilage", "passage_number": 3, "cell_density": 250000
    }
    paths['test_compounds'] = [
        {"name": "TGF-β3", "concentration": "10 ng/mL", "vehicle": "PBS + 0.1% BSA"}
    ]

    # === SYNTHETIC BIOLOGY ===
    paths['reaction_network'] = [{
        "id": "R1", "name": "Glucose uptake",
        "reactants": {"Glucose_ext": 1}, "products": {"Glucose": 1}, "reversible": False
    }]
    paths['kinetic_parameters'] = {
        "R1": {"law_type": "mass_action", "parameters": {"k_forward": 0.1}}
    }
    paths['species_initial'] = {"Glucose_ext": 10.0, "Glucose": 0.0}

    barcode_file = str(TEST_DATA_DIR / "barcodes.fasta")
    with open(barcode_file, 'w') as f:
        for i in range(10):
            bc = ''.join(np.random.choice(list('ATCG'), 20))
            f.write(f">barcode_{i}\n{bc}\n")
    paths['barcode_file'] = barcode_file

    # === SYSTEMS BIOLOGY ===
    sbml_path = str(TEST_DATA_DIR / "model.xml")
    with open(sbml_path, 'w') as f:
        f.write('''<?xml version="1.0" encoding="UTF-8"?>
<sbml xmlns="http://www.sbml.org/sbml/level3/version1/core" level="3" version="1">
<model id="test"><listOfCompartments><compartment id="c" size="1"/></listOfCompartments>
<listOfSpecies><species id="A" compartment="c" initialConcentration="1"/>
<species id="B" compartment="c" initialConcentration="0"/></listOfSpecies>
<listOfReactions><reaction id="v1" reversible="false">
<listOfReactants><speciesReference species="A" stoichiometry="1"/></listOfReactants>
<listOfProducts><speciesReference species="B" stoichiometry="1"/></listOfProducts>
<kineticLaw><math xmlns="http://www.w3.org/1998/Math/MathML"><cn>0.1</cn></math></kineticLaw>
</reaction></listOfReactions></model></sbml>''')
    paths['sbml_model'] = sbml_path

    # === IMMUNOLOGY ===
    paths['ebv_sample_data'] = {
        "patient_001": {"IgG": 1.85, "IgM": 0.42},
        "patient_002": {"IgG": 0.25, "IgM": 1.95}
    }
    paths['ebv_standard_curve'] = {
        "IgG": [(0, 0.05), (10, 0.25), (50, 0.85), (100, 1.5), (500, 2.2)],
        "IgM": [(0, 0.04), (10, 0.22), (50, 0.78), (100, 1.4), (500, 2.0)]
    }
    paths['cell_cycle_data'] = {
        "time_hours": [0, 2, 4, 6, 8, 10, 12],
        "BrdU_positive": [0.05, 0.15, 0.35, 0.55, 0.65, 0.60, 0.45],
        "IdU_positive": [0.0, 0.05, 0.20, 0.40, 0.55, 0.60, 0.55]
    }

    # === GENETICS ===
    paths['demographic_params_expansion'] = {
        "N_initial": 10000, "N_final": 10000, "T_expansion": 100
    }
    gwas_csv = str(TEST_DATA_DIR / "gwas_summary.csv")
    with open(gwas_csv, 'w') as f:
        f.write("snp,beta,se,p_value,effect_size\n")
        for i in range(100):
            f.write(f"rs{i},{np.random.randn():.4f},{np.random.uniform(0.1,0.5):.4f},{np.random.uniform(0,1):.6f},{np.random.randn():.4f}\n")
    paths['gwas_summary'] = gwas_csv
    paths['ld_matrix'] = np.eye(100) + np.random.randn(100, 100) * 0.1
    np.fill_diagonal(paths['ld_matrix'], 1.0)

    genotype_path = str(TEST_DATA_DIR / "genotypes.npy")
    phenotype_path = str(TEST_DATA_DIR / "phenotypes.npy")
    n_samples, n_snps = 200, 100
    G = np.random.randint(0, 3, (n_samples, n_snps)).astype(np.float32)
    y = G @ np.random.randn(n_snps) * 0.1 + np.random.randn(n_samples)
    np.save(genotype_path, G)
    np.save(phenotype_path, y)
    paths['genotype_matrix'] = genotype_path
    paths['phenotype_vector'] = phenotype_path

    # === LAB AUTOMATION ===
    script_path = str(TEST_DATA_DIR / "test_script.py")
    with open(script_path, 'w') as f:
        f.write('print("Hello from PyLabRobot")\n')
    paths['pylabrobot_script'] = script_path

    return paths


def main():
    print("="*60)
    print("TESTING PREVIOUSLY SKIPPED TOOLS - v7 (scRNA WORKING)")
    print("="*60)

    print("\nCreating mock data with ALL FIXED formats...")
    paths = setup_mock_data()
    print(f"Created {len(paths)} data items")

    results = Results()

    from biomni.tool import (
        literature, genomics, biochemistry, microbiology,
        biophysics, pharmacology, synthetic_biology, systems_biology,
        immunology, cell_biology, cancer_biology, physiology,
        pathology, bioengineering, genetics, lab_automation
    )

    # === LITERATURE ===
    print("\n--- literature ---")
    safe_test(results, "literature.extract_pdf_content",
        lambda: literature.extract_pdf_content("https://arxiv.org/pdf/2401.00001.pdf"))
    safe_test(results, "literature.fetch_supplementary_info_from_doi",
        lambda: literature.fetch_supplementary_info_from_doi("10.1038/s41586-020-2649-2"))

    # === GENOMICS ===
    print("\n--- genomics ---")
    safe_test(results, "genomics.find_enriched_motifs_with_homer",
        lambda: genomics.find_enriched_motifs_with_homer(paths['bed'], str(TEST_DATA_DIR / "homer_out"), "hg38"))
    safe_test(results, "genomics.generate_gene_embeddings_with_ESM_models",
        lambda: genomics.generate_gene_embeddings_with_ESM_models(["BRCA1"], "esm2_t6_8M_UR50D"))
    
    # scRNA functions - NOW ACTUALLY TESTED (Harmony and scVI work!)
    if 'scrna_dir' in paths:
        safe_test(results, "genomics.create_harmony_embeddings_scRNA",
            lambda: genomics.create_harmony_embeddings_scRNA(
                paths['scrna_adata'], 'batch', paths['scrna_dir']))
        safe_test(results, "genomics.create_scvi_embeddings_scRNA",
            lambda: genomics.create_scvi_embeddings_scRNA(
                paths['scrna_adata'], 'batch', 'celltype', paths['scrna_dir']))
    else:
        safe_test(results, "genomics.create_harmony_embeddings_scRNA",
            lambda: (_ for _ in ()).throw(Exception("AnnData creation failed")))
        safe_test(results, "genomics.create_scvi_embeddings_scRNA",
            lambda: (_ for _ in ()).throw(Exception("AnnData creation failed")))
    
    # annotate_celltype needs API key + parquet
    safe_test(results, "genomics.annotate_celltype_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: ANTHROPIC_API_KEY + czi_census parquet")))

    # === BIOCHEMISTRY ===
    print("\n--- biochemistry ---")
    safe_test(results, "biochemistry.analyze_itc_binding_thermodynamics",
        lambda: biochemistry.analyze_itc_binding_thermodynamics(
            {"time": [0, 60, 120, 180, 240], "heat": [0, -5.2, -4.8, -4.1, -3.2]},
            {"cell_volume": 1.4e-3, "syringe_concentration": 1e-3, "cell_concentration": 1e-4}))

    # === MICROBIOLOGY ===
    print("\n--- microbiology ---")
    safe_test(results, "microbiology.count_bacterial_colonies",
        lambda: microbiology.count_bacterial_colonies(
            paths['colony_image'], dilution_factor=1, plate_area_cm2=65.0,
            output_dir=str(TEST_DATA_DIR / "colonies_out")))
    safe_test(results, "microbiology.segment_and_analyze_microbial_cells",
        lambda: microbiology.segment_and_analyze_microbial_cells(paths['image1']))
    safe_test(results, "microbiology.segment_cells_with_deep_learning",
        lambda: microbiology.segment_cells_with_deep_learning(paths['image1']))
    safe_test(results, "microbiology.optimize_anaerobic_digestion_process",
        lambda: microbiology.optimize_anaerobic_digestion_process(
            waste_characteristics=paths['waste_characteristics'],
            operational_parameters=paths['operational_parameters'],
            target_output='methane_yield', optimization_method='rsm'))
    safe_test(results, "microbiology.analyze_arsenic_speciation_hplc_icpms",
        lambda: microbiology.analyze_arsenic_speciation_hplc_icpms(
            paths['arsenic_sample_data'], paths['arsenic_calibration']))
    safe_test(results, "microbiology.annotate_bacterial_genome",
        lambda: microbiology.annotate_bacterial_genome(paths['fasta']))

    # === BIOPHYSICS ===
    print("\n--- biophysics ---")
    safe_test(results, "biophysics.analyze_cell_morphology_and_cytoskeleton",
        lambda: biophysics.analyze_cell_morphology_and_cytoskeleton(paths['image1']))

    # === PHARMACOLOGY ===
    print("\n--- pharmacology ---")
    safe_test(results, "pharmacology.calculate_physicochemical_properties",
        lambda: pharmacology.calculate_physicochemical_properties(SAMPLE_SMILES))
    
    # Docking - ARM64 issues
    safe_test(results, "pharmacology.docking_autodock_vina",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: rdkit<2024.3.1, TDC tiledb (ARM64 issues)")))
    safe_test(results, "pharmacology.run_autosite",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: autosite binary (ADFR suite, not available ARM64)")))
    
    safe_test(results, "pharmacology.analyze_western_blot",
        lambda: pharmacology.analyze_western_blot(
            paths['image1'], paths['western_target_bands'],
            paths['western_loading_control'], paths['western_antibody_info']))
    safe_test(results, "pharmacology.grade_adverse_events_using_vcog_ctcae",
        lambda: pharmacology.grade_adverse_events_using_vcog_ctcae(
            [{"event": "Vomiting", "frequency": "3x daily", "severity": "moderate"}]))
    safe_test(results, "pharmacology.analyze_xenograft_tumor_growth_inhibition",
        lambda: pharmacology.analyze_xenograft_tumor_growth_inhibition(
            [[0,100],[7,250],[14,500],[21,900]], [[0,100],[7,150],[14,180],[21,200]]))
    safe_test(results, "pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations",
        lambda: pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations(
            paths['formulations'], paths['storage_conditions'], paths['time_points']))
    safe_test(results, "pharmacology.analyze_radiolabeled_antibody_biodistribution",
        lambda: pharmacology.analyze_radiolabeled_antibody_biodistribution(
            paths['biodistribution_data'], {"half_life": 159.6}))
    safe_test(results, "pharmacology.estimate_alpha_particle_radiotherapy_dosimetry",
        lambda: pharmacology.estimate_alpha_particle_radiotherapy_dosimetry(
            paths['biodistribution_data'], paths['radiation_parameters']))
    safe_test(results, "pharmacology.perform_mwas_cyp2c19_metabolizer_status",
        lambda: pharmacology.perform_mwas_cyp2c19_metabolizer_status(
            np.random.rand(50, 100), np.random.choice([0, 1], 50)))
    safe_test(results, "pharmacology.run_3d_chondrogenic_aggregate_assay",
        lambda: pharmacology.run_3d_chondrogenic_aggregate_assay(
            paths['chondrocyte_cells'], paths['test_compounds']))

    # === SYNTHETIC BIOLOGY ===
    print("\n--- synthetic_biology ---")
    safe_test(results, "synthetic_biology.create_biochemical_network_sbml_model",
        lambda: synthetic_biology.create_biochemical_network_sbml_model(
            paths['reaction_network'], paths['kinetic_parameters'], paths['species_initial'],
            str(TEST_DATA_DIR / "output_model.xml")))
    safe_test(results, "synthetic_biology.analyze_barcode_sequencing_data",
        lambda: synthetic_biology.analyze_barcode_sequencing_data(paths['barcode_file']))

    # === SYSTEMS BIOLOGY ===
    print("\n--- systems_biology ---")
    safe_test(results, "systems_biology.query_chatnt",
        lambda: systems_biology.query_chatnt(
            "What is the effect of this DNA sequence?", sequence="ATGCATGC" * 10))
    safe_test(results, "systems_biology.simulate_renin_angiotensin_system_dynamics",
        lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(100))
    safe_test(results, "systems_biology.simulate_metabolic_network_perturbation",
        lambda: systems_biology.simulate_metabolic_network_perturbation(
            paths['sbml_model'], {"v1": 0.5}, "FBA"))
    safe_test(results, "systems_biology.compare_protein_structures",
        lambda: systems_biology.compare_protein_structures(paths['pdb'], paths['pdb']))

    # === IMMUNOLOGY ===
    print("\n--- immunology ---")
    safe_test(results, "immunology.analyze_ebv_antibody_titers",
        lambda: immunology.analyze_ebv_antibody_titers(
            paths['ebv_sample_data'], paths['ebv_standard_curve']))
    safe_test(results, "immunology.estimate_cell_cycle_phase_durations",
        lambda: immunology.estimate_cell_cycle_phase_durations(paths['cell_cycle_data']))
    safe_test(results, "immunology.analyze_cns_lesion_histology",
        lambda: immunology.analyze_cns_lesion_histology(paths['image1']))
    safe_test(results, "immunology.analyze_immunohistochemistry_image",
        lambda: immunology.analyze_immunohistochemistry_image(paths['image1'], "CD3"))

    # === CELL BIOLOGY ===
    print("\n--- cell_biology ---")
    safe_test(results, "cell_biology.analyze_mitochondrial_morphology_and_potential",
        lambda: cell_biology.analyze_mitochondrial_morphology_and_potential(
            paths['image1'], paths['image2']))

    # === CANCER BIOLOGY ===
    print("\n--- cancer_biology ---")
    safe_test(results, "cancer_biology.analyze_ddr_network_in_cancer",
        lambda: cancer_biology.analyze_ddr_network_in_cancer(
            {"BRCA1": 0.5, "ATM": 1.2, "TP53": 0.8}, {"TP53": "R175H"}))
    safe_test(results, "cancer_biology.perform_gene_expression_nmf_analysis",
        lambda: cancer_biology.perform_gene_expression_nmf_analysis(
            np.random.rand(100, 50), n_components=3))

    # === PHYSIOLOGY ===
    print("\n--- physiology ---")
    safe_test(results, "physiology.analyze_fatty_acid_composition_by_gc",
        lambda: physiology.analyze_fatty_acid_composition_by_gc(
            {"C16:0": 1000000, "C18:0": 500000, "C18:1": 800000, "C18:2": 300000}))
    safe_test(results, "physiology.analyze_protein_colocalization",
        lambda: physiology.analyze_protein_colocalization(paths['image1'], paths['image2']))
    safe_test(results, "physiology.quantify_amyloid_beta_plaques",
        lambda: physiology.quantify_amyloid_beta_plaques(paths['image1']))

    # === PATHOLOGY ===
    print("\n--- pathology ---")
    safe_test(results, "pathology.analyze_atp_luminescence_assay",
        lambda: pathology.analyze_atp_luminescence_assay(
            str(TEST_DATA_DIR), "*.png"))
    safe_test(results, "pathology.analyze_aortic_diameter_and_geometry",
        lambda: pathology.analyze_aortic_diameter_and_geometry(paths['image1']))
    safe_test(results, "pathology.analyze_thrombus_histology",
        lambda: pathology.analyze_thrombus_histology(paths['image1']))
    safe_test(results, "pathology.quantify_corneal_nerve_fibers",
        lambda: pathology.quantify_corneal_nerve_fibers(paths['image1']))
    safe_test(results, "pathology.analyze_intracellular_calcium_with_rhod2",
        lambda: pathology.analyze_intracellular_calcium_with_rhod2(
            [paths['image1'], paths['image2']]))
    safe_test(results, "pathology.segment_and_quantify_cells_in_multiplexed_images",
        lambda: pathology.segment_and_quantify_cells_in_multiplexed_images(
            {"DAPI": paths['image1'], "CD3": paths['image2'], "CD8": paths['image3']}))

    # === BIOENGINEERING ===
    print("\n--- bioengineering ---")
    safe_test(results, "bioengineering.analyze_myofiber_morphology",
        lambda: bioengineering.analyze_myofiber_morphology(paths['image1']))
    safe_test(results, "bioengineering.decode_behavior_from_neural_trajectories",
        lambda: bioengineering.decode_behavior_from_neural_trajectories(
            np.random.randn(100, 3, 50), np.random.randint(0, 3, 100)))

    # === GENETICS ===
    print("\n--- genetics ---")
    safe_test(results, "genetics.liftover_coordinates",
        lambda: genetics.liftover_coordinates([("chr1", 100000, 100001)], "hg19", "hg38"))
    safe_test(results, "genetics.bayesian_finemapping_with_deep_vi",
        lambda: genetics.bayesian_finemapping_with_deep_vi(
            paths['gwas_summary'], paths['ld_matrix']))
    safe_test(results, "genetics.fit_genomic_prediction_model",
        lambda: genetics.fit_genomic_prediction_model(
            np.load(paths['genotype_matrix']), np.load(paths['phenotype_vector'])))
    safe_test(results, "genetics.simulate_demographic_history",
        lambda: genetics.simulate_demographic_history(
            "expansion", paths['demographic_params_expansion']))

    # === LAB AUTOMATION ===
    print("\n--- lab_automation ---")
    safe_test(results, "lab_automation.test_pylabrobot_script",
        lambda: lab_automation.test_pylabrobot_script(paths['pylabrobot_script']))

    # === SUMMARY ===
    summary = results.summary()

    # Save results
    with open("/tmp/biomni_skipped_test_v7.json", "w") as f:
        json.dump({
            "summary": summary,
            "passed": results.passed,
            "failed": results.failed
        }, f, indent=2)
    
    print(f"\nResults saved to /tmp/biomni_skipped_test_v7.json")


if __name__ == "__main__":
    main()
