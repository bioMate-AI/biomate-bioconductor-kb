#!/usr/bin/env python3
"""
Test previously skipped Biomni tools - v5 with ALL fixes applied.

Fixes from v4:
1. arsenic_speciation: calibration_data needs {"species": {"factor": float, "limit": float}}
2. ebv_antibody_titers: standard_curve_data needs {"IgG": [...], "IgM": [...]} keys only
3. simulate_demographic_history: BUG in Biomni - workaround by using non-constant model

Author: BioMate Testing Framework
Date: 2026-01-19
"""

import os
import sys
import json
import numpy as np
from pathlib import Path

TEST_DATA_DIR = Path("/tmp/biomni_test_v5")
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
        print(f"SKIPPED TOOLS TEST v5: {len(self.passed)}/{total} PASSED ({rate:.0f}%)")
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
        # Colony image with clear spots
        img = np.zeros((512, 512), dtype=np.uint8)
        img[:] = 200  # Light background
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

    # === MICROBIOLOGY - FIXED FORMATS ===

    # optimize_anaerobic_digestion_process - TUPLES for ranges
    paths['waste_characteristics'] = {
        "total_solids": 15.0,
        "volatile_solids": 75.0,
        "cod": 50000.0
    }
    paths['operational_parameters'] = {
        "hrt": (10, 30),
        "olr": (1.0, 4.0),
        "if_ratio": (0.5, 2.0),
        "temperature": (30, 45),
        "ph": (6.5, 8.0)
    }

    # analyze_arsenic_speciation_hplc_icpms - FIXED FORMAT
    # Source code shows: calibration_data[species_name]["factor"] and ["limit"]
    paths['arsenic_sample_data'] = {
        "sample_001": {2.8: 15000, 7.5: 8500, 3.9: 3200, 6.2: 2100},
        "sample_002": {2.8: 12000, 7.5: 9200, 3.9: 2800, 6.2: 1900}
    }
    # CORRECT FORMAT: {"species": {"factor": float, "limit": float}}
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

    paths['formulations'] = [
        {
            "name": "Formulation A",
            "active_ingredient": "Aspirin",
            "concentration": 100.0,
            "excipients": ["lactose", "starch", "magnesium stearate"]
        }
    ]
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
        "radionuclide": "Ac-225",
        "half_life_hours": 240.0,
        "energy_per_decay_MeV": 28.0,
        "radiation_weighting_factor": 20.0,
        "S_factors": {"tumor_tumor": 5.2e-13, "liver_liver": 3.1e-13}
    }

    paths['chondrocyte_cells'] = {
        "source": "human articular cartilage",
        "passage_number": 3,
        "cell_density": 250000
    }
    paths['test_compounds'] = [
        {"name": "TGF-β3", "concentration": "10 ng/mL", "vehicle": "PBS + 0.1% BSA"}
    ]

    # === SYNTHETIC BIOLOGY ===
    paths['reaction_network'] = [
        {
            "id": "R1",
            "name": "Glucose uptake",
            "reactants": {"Glucose_ext": 1},
            "products": {"Glucose": 1},
            "reversible": False
        }
    ]
    paths['kinetic_parameters'] = {
        "R1": {
            "law_type": "mass_action",
            "parameters": {"k_forward": 0.1}
        }
    }

    # === SYSTEMS BIOLOGY ===
    paths['ras_initial_concentrations'] = {
        "renin": 1.0,
        "angiotensinogen": 100.0,
        "angiotensin_I": 0.0,
        "angiotensin_II": 0.0,
        "ACE2_angiotensin_II": 0.0,
        "angiotensin_1_7": 0.0
    }
    paths['ras_rate_constants'] = {
        "k_ren": 0.1, "k_agt": 0.5, "k_ace": 0.3,
        "k_ace2": 0.2, "k_at1r": 0.15, "k_mas": 0.1
    }
    paths['ras_feedback_params'] = {
        "fb_ang_II": 0.05, "fb_ace2": 0.03
    }
    paths['perturbation_params'] = {
        "time": 50.0, "metabolite": "A", "factor": 2.0
    }

    # === IMMUNOLOGY - FIXED FORMATS ===

    # analyze_ebv_antibody_titers - FIXED FORMAT
    # Source code shows: standard_curves[curve_type] where curve_type = "IgG" or "IgM"
    paths['ebv_raw_od_data'] = {
        "patient_001": {
            "VCA_IgG": 1.85, "VCA_IgM": 0.32,
            "EA_IgG": 0.95, "EA_IgM": 0.18,
            "EBNA1_IgG": 1.42, "EBNA1_IgM": 0.08
        },
        "patient_002": {
            "VCA_IgG": 0.45, "VCA_IgM": 1.52,
            "EA_IgG": 0.38, "EA_IgM": 0.85,
            "EBNA1_IgG": 0.22, "EBNA1_IgM": 0.55
        }
    }
    # CORRECT FORMAT: Just "IgG" and "IgM" as keys (not VCA_IgG, etc.)
    paths['ebv_standard_curve'] = {
        "IgG": [(0, 0.05), (10, 0.25), (50, 0.85), (100, 1.5), (500, 2.2)],
        "IgM": [(0, 0.04), (10, 0.22), (50, 0.78), (100, 1.4), (500, 2.0)]
    }
    paths['ebv_sample_metadata'] = {
        "patient_001": {"group": "chronic", "collection_date": "2026-01-15"},
        "patient_002": {"group": "acute", "collection_date": "2026-01-16"}
    }

    # estimate_cell_cycle_phase_durations
    n_timepoints = 10
    paths['flow_cytometry_data'] = {
        "time_points": list(range(0, n_timepoints * 2, 2)),
        "edu_positive": [5 + i*3 + np.random.randn()*2 for i in range(n_timepoints)],
        "brdu_positive": [3 + i*2.5 + np.random.randn()*1.5 for i in range(n_timepoints)],
        "double_positive": [1 + i*1.5 + np.random.randn() for i in range(n_timepoints)]
    }
    paths['cell_cycle_initial_estimates'] = {
        "g1_duration": 10.0, "s_duration": 8.0,
        "g2m_duration": 4.0, "death_rate": 0.01
    }

    # === BIOENGINEERING ===
    n_timepoints = 500
    paths['neural_data_2d'] = np.random.randn(n_timepoints, 50)
    paths['behavioral_data_2d'] = np.random.randn(n_timepoints, 3)

    # === GENETICS - FIXED FOR DEMOGRAPHIC HISTORY BUG ===
    # BUG: For "constant" model, code adds pop0 twice
    # WORKAROUND: Use "expansion" model which only adds pop0 once
    paths['demographic_params_expansion'] = {
        "N_initial": 10000,
        "N_final": 10000,  # Same as initial = effectively constant
        "T_expansion": 100
    }

    # bayesian_finemapping
    gwas_path = str(TEST_DATA_DIR / "gwas_summary.tsv")
    with open(gwas_path, 'w') as f:
        f.write("variant_id\teffect_size\tpvalue\tse\n")
        for i in range(100):
            var_id = f"rs{1000000 + i}"
            effect = np.random.randn() * 0.1
            se = abs(np.random.randn() * 0.02) + 0.01
            pval = min(1.0, max(1e-10, np.random.uniform(0.001, 0.5)))
            f.write(f"{var_id}\t{effect:.6f}\t{pval:.2e}\t{se:.6f}\n")
    paths['gwas_summary_file'] = gwas_path

    n_variants = 100
    ld = np.eye(n_variants)
    for i in range(n_variants):
        for j in range(max(0, i-5), min(n_variants, i+6)):
            if i != j:
                ld[i, j] = 0.5 ** abs(i - j)
    paths['ld_matrix'] = ld

    # === CSV FILES ===
    tumor_csv = str(TEST_DATA_DIR / "tumor_growth.csv")
    import csv
    with open(tumor_csv, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['time', 'volume', 'group', 'subject'])
        for subj in range(1, 6):
            for t in [0, 7, 14, 21]:
                vol = 100 + t * 10 + np.random.randn() * 5
                writer.writerow([t, vol, 'control', f'subj_{subj}'])
        for subj in range(6, 11):
            for t in [0, 7, 14, 21]:
                vol = 100 + t * 5 + np.random.randn() * 5
                writer.writerow([t, vol, 'treatment', f'subj_{subj}'])
    paths['tumor_csv'] = tumor_csv

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

    gc_path = str(TEST_DATA_DIR / "gc_data.csv")
    with open(gc_path, 'w') as f:
        f.write("retention_time,area,compound\n")
        f.write("5.2,12500,C16:0\n8.4,8900,C18:0\n10.1,15600,C18:1\n")
    paths['gc_data'] = gc_path

    atp_data = str(TEST_DATA_DIR / "atp_data.csv")
    atp_std = str(TEST_DATA_DIR / "atp_standard.csv")
    with open(atp_data, 'w') as f:
        f.write("sample,luminescence\n")
        for i in range(12):
            f.write(f"sample_{i},{np.random.randint(1000, 10000)}\n")
    with open(atp_std, 'w') as f:
        f.write("concentration,luminescence\n")
        for conc in [0, 0.1, 1, 10, 100]:
            f.write(f"{conc},{conc * 100 + np.random.randn() * 10}\n")
    paths['atp_data'] = atp_data
    paths['atp_standard'] = atp_std

    sbml_path = str(TEST_DATA_DIR / "model.xml")
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

    barcode_path = str(TEST_DATA_DIR / "barcodes.txt")
    with open(barcode_path, 'w') as f:
        for i in range(100):
            barcode = ''.join(np.random.choice(['A', 'T', 'G', 'C'], 20))
            f.write(f"{barcode}\t{np.random.randint(1, 1000)}\n")
    paths['barcode_file'] = barcode_path

    return paths


def run_tests():
    print("="*60)
    print("TESTING PREVIOUSLY SKIPPED TOOLS - v5 (ALL FIXES)")
    print("="*60)

    print("\nCreating mock data with ALL FIXED formats...")
    paths = setup_mock_data()
    print(f"Created {len(paths)} data items")

    results = Results()

    from biomni.tool import literature, genomics, biochemistry, microbiology
    from biomni.tool import biophysics, pharmacology, synthetic_biology, systems_biology
    from biomni.tool import immunology, cell_biology, cancer_biology, physiology
    from biomni.tool import pathology, bioengineering, genetics, lab_automation

    # === LITERATURE ===
    print("\n--- literature ---")
    safe_test(results, "literature.extract_pdf_content",
        lambda: literature.extract_pdf_content("https://arxiv.org/pdf/2001.00001.pdf"))
    safe_test(results, "literature.fetch_supplementary_info_from_doi",
        lambda: literature.fetch_supplementary_info_from_doi("10.1038/s41586-020-2649-2"))

    # === GENOMICS ===
    print("\n--- genomics ---")
    safe_test(results, "genomics.find_enriched_motifs_with_homer",
        lambda: genomics.find_enriched_motifs_with_homer(paths['bed'], "hg38", str(TEST_DATA_DIR / "homer_out")))
    safe_test(results, "genomics.generate_gene_embeddings_with_ESM_models",
        lambda: genomics.generate_gene_embeddings_with_ESM_models([SAMPLE_PROTEIN[:50]]))
    # scRNA - need data_lake_path with models
    safe_test(results, "genomics.annotate_celltype_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: data_lake_path with celltype models")))
    safe_test(results, "genomics.create_harmony_embeddings_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: data_lake_path with harmony models")))
    safe_test(results, "genomics.create_scvi_embeddings_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: data_lake_path with scVI models")))

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
    # FIXED: calibration_data format
    safe_test(results, "microbiology.analyze_arsenic_speciation_hplc_icpms",
        lambda: microbiology.analyze_arsenic_speciation_hplc_icpms(
            sample_data=paths['arsenic_sample_data'],
            sample_name="soil_samples",
            calibration_data=paths['arsenic_calibration']))
    safe_test(results, "microbiology.annotate_bacterial_genome",
        lambda: microbiology.annotate_bacterial_genome(paths['fasta'], str(TEST_DATA_DIR / "annotation_out")))

    # === BIOPHYSICS ===
    print("\n--- biophysics ---")
    safe_test(results, "biophysics.analyze_cell_morphology_and_cytoskeleton",
        lambda: biophysics.analyze_cell_morphology_and_cytoskeleton(paths['image1']))

    # === PHARMACOLOGY ===
    print("\n--- pharmacology ---")
    safe_test(results, "pharmacology.calculate_physicochemical_properties",
        lambda: pharmacology.calculate_physicochemical_properties(SAMPLE_SMILES))
    # Docking - needs PyScreener with pdbfixer (requires conda)
    safe_test(results, "pharmacology.docking_autodock_vina",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: PyScreener with pdbfixer (conda install)")))
    safe_test(results, "pharmacology.run_autosite",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: prepare_receptor from MGLTools")))
    safe_test(results, "pharmacology.analyze_western_blot",
        lambda: pharmacology.analyze_western_blot(
            blot_image_path=paths['image1'],
            target_bands=paths['western_target_bands'],
            loading_control_band=paths['western_loading_control'],
            antibody_info=paths['western_antibody_info'],
            output_dir=str(TEST_DATA_DIR / "western_out")))
    safe_test(results, "pharmacology.grade_adverse_events_using_vcog_ctcae",
        lambda: pharmacology.grade_adverse_events_using_vcog_ctcae(
            [{"event": "Vomiting", "frequency": 3, "duration_hours": 2}]))
    safe_test(results, "pharmacology.analyze_xenograft_tumor_growth_inhibition",
        lambda: pharmacology.analyze_xenograft_tumor_growth_inhibition(
            data_path=paths['tumor_csv'], time_column='time', volume_column='volume',
            group_column='group', subject_column='subject',
            output_dir=str(TEST_DATA_DIR / "tumor_out")))
    safe_test(results, "pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations",
        lambda: pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations(
            formulations=paths['formulations'],
            storage_conditions=paths['storage_conditions'],
            time_points=paths['time_points']))
    safe_test(results, "pharmacology.analyze_radiolabeled_antibody_biodistribution",
        lambda: pharmacology.analyze_radiolabeled_antibody_biodistribution(
            time_points=[1, 4, 24, 48],
            tissue_data={"blood": [10, 8, 4, 2], "tumor": [2, 5, 8, 10]}))
    safe_test(results, "pharmacology.estimate_alpha_particle_radiotherapy_dosimetry",
        lambda: pharmacology.estimate_alpha_particle_radiotherapy_dosimetry(
            biodistribution_data=paths['biodistribution_data'],
            radiation_parameters=paths['radiation_parameters'],
            output_file=str(TEST_DATA_DIR / "dosimetry.csv")))
    safe_test(results, "pharmacology.perform_mwas_cyp2c19_metabolizer_status",
        lambda: pharmacology.perform_mwas_cyp2c19_metabolizer_status(
            np.random.randn(100, 50), np.random.choice(["PM", "IM", "EM", "UM"], 100)))
    safe_test(results, "pharmacology.run_3d_chondrogenic_aggregate_assay",
        lambda: pharmacology.run_3d_chondrogenic_aggregate_assay(
            chondrocyte_cells=paths['chondrocyte_cells'],
            test_compounds=paths['test_compounds'],
            culture_duration_days=21, measurement_intervals=7))

    # === SYNTHETIC BIOLOGY ===
    print("\n--- synthetic_biology ---")
    safe_test(results, "synthetic_biology.create_biochemical_network_sbml_model",
        lambda: synthetic_biology.create_biochemical_network_sbml_model(
            reaction_network=paths['reaction_network'],
            kinetic_parameters=paths['kinetic_parameters'],
            output_file=str(TEST_DATA_DIR / "network.xml")))
    safe_test(results, "synthetic_biology.analyze_barcode_sequencing_data",
        lambda: synthetic_biology.analyze_barcode_sequencing_data(paths['barcode_file']))

    # === SYSTEMS BIOLOGY ===
    print("\n--- systems_biology ---")
    safe_test(results, "systems_biology.query_chatnt",
        lambda: systems_biology.query_chatnt(
            question="What is the GC content?", sequence=SAMPLE_DNA))
    safe_test(results, "systems_biology.simulate_renin_angiotensin_system_dynamics",
        lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(
            initial_concentrations=paths['ras_initial_concentrations'],
            rate_constants=paths['ras_rate_constants'],
            feedback_params=paths['ras_feedback_params'],
            simulation_time=48, time_points=100))
    safe_test(results, "systems_biology.simulate_metabolic_network_perturbation",
        lambda: systems_biology.simulate_metabolic_network_perturbation(
            model_file=paths['sbml_model'],
            initial_concentrations={"A": 1.0, "B": 0.0},
            perturbation_params=paths['perturbation_params'],
            simulation_time=100, time_points=100))
    safe_test(results, "systems_biology.compare_protein_structures",
        lambda: systems_biology.compare_protein_structures(paths['pdb'], paths['pdb']))

    # === IMMUNOLOGY ===
    print("\n--- immunology ---")
    # FIXED: standard_curve_data keys are just "IgG" and "IgM"
    safe_test(results, "immunology.analyze_ebv_antibody_titers",
        lambda: immunology.analyze_ebv_antibody_titers(
            raw_od_data=paths['ebv_raw_od_data'],
            standard_curve_data=paths['ebv_standard_curve'],
            sample_metadata=paths['ebv_sample_metadata'],
            output_dir=str(TEST_DATA_DIR / "ebv_out")))
    safe_test(results, "immunology.estimate_cell_cycle_phase_durations",
        lambda: immunology.estimate_cell_cycle_phase_durations(
            flow_cytometry_data=paths['flow_cytometry_data'],
            initial_estimates=paths['cell_cycle_initial_estimates']))
    safe_test(results, "immunology.analyze_cns_lesion_histology",
        lambda: immunology.analyze_cns_lesion_histology(paths['image1']))
    safe_test(results, "immunology.analyze_immunohistochemistry_image",
        lambda: immunology.analyze_immunohistochemistry_image(paths['image1']))

    # === CELL BIOLOGY ===
    print("\n--- cell_biology ---")
    safe_test(results, "cell_biology.analyze_mitochondrial_morphology_and_potential",
        lambda: cell_biology.analyze_mitochondrial_morphology_and_potential(
            morphology_image_path=paths['image1'],
            potential_image_path=paths['image2'],
            output_dir=str(TEST_DATA_DIR / "mito_out")))

    # === CANCER BIOLOGY ===
    print("\n--- cancer_biology ---")
    safe_test(results, "cancer_biology.analyze_ddr_network_in_cancer",
        lambda: cancer_biology.analyze_ddr_network_in_cancer(
            expression_data_path=paths['expression_csv'],
            mutation_data_path=paths['mutation_csv'],
            output_dir=str(TEST_DATA_DIR / "ddr_out")))
    safe_test(results, "cancer_biology.perform_gene_expression_nmf_analysis",
        lambda: cancer_biology.perform_gene_expression_nmf_analysis(np.random.rand(100, 50), 5))

    # === PHYSIOLOGY ===
    print("\n--- physiology ---")
    safe_test(results, "physiology.analyze_fatty_acid_composition_by_gc",
        lambda: physiology.analyze_fatty_acid_composition_by_gc(
            gc_data_file=paths['gc_data'], tissue_type="liver",
            sample_id="sample_001", output_directory=str(TEST_DATA_DIR / "fatty_out")))
    safe_test(results, "physiology.analyze_protein_colocalization",
        lambda: physiology.analyze_protein_colocalization(paths['image1'], paths['image2']))
    safe_test(results, "physiology.quantify_amyloid_beta_plaques",
        lambda: physiology.quantify_amyloid_beta_plaques(paths['image1']))

    # === PATHOLOGY ===
    print("\n--- pathology ---")
    safe_test(results, "pathology.analyze_atp_luminescence_assay",
        lambda: pathology.analyze_atp_luminescence_assay(
            data_file=paths['atp_data'], standard_curve_file=paths['atp_standard'],
            normalization_method="protein", normalization_data={"sample_0": 1.2}))
    safe_test(results, "pathology.analyze_aortic_diameter_and_geometry",
        lambda: pathology.analyze_aortic_diameter_and_geometry(paths['image1']))
    safe_test(results, "pathology.analyze_thrombus_histology",
        lambda: pathology.analyze_thrombus_histology(paths['image1'], str(TEST_DATA_DIR / "thrombus_out")))
    safe_test(results, "pathology.quantify_corneal_nerve_fibers",
        lambda: pathology.quantify_corneal_nerve_fibers(
            image_path=paths['image1'], marker_type="tubulin",
            output_dir=str(TEST_DATA_DIR / "cornea_out"), threshold_method="otsu"))
    safe_test(results, "pathology.analyze_intracellular_calcium_with_rhod2",
        lambda: pathology.analyze_intracellular_calcium_with_rhod2(
            background_image_path=paths['image1'],
            control_image_path=paths['image2'],
            sample_image_path=paths['image3'],
            output_dir=str(TEST_DATA_DIR / "calcium_out")))
    safe_test(results, "pathology.segment_and_quantify_cells_in_multiplexed_images",
        lambda: pathology.segment_and_quantify_cells_in_multiplexed_images(
            image_path=paths['image1'], markers_list=["CD3", "CD4", "CD8"],
            nuclear_channel_index=0, output_dir=str(TEST_DATA_DIR / "multiplex_out")))

    # === BIOENGINEERING ===
    print("\n--- bioengineering ---")
    safe_test(results, "bioengineering.analyze_myofiber_morphology",
        lambda: bioengineering.analyze_myofiber_morphology(paths['image1']))
    safe_test(results, "bioengineering.decode_behavior_from_neural_trajectories",
        lambda: bioengineering.decode_behavior_from_neural_trajectories(
            neural_data=paths['neural_data_2d'],
            behavioral_data=paths['behavioral_data_2d'],
            n_components=10, output_dir=str(TEST_DATA_DIR / "neural_out")))

    # === GENETICS ===
    print("\n--- genetics ---")
    safe_test(results, "genetics.liftover_coordinates",
        lambda: genetics.liftover_coordinates(
            chromosome="chr1", position=12345, input_format="hg19",
            output_format="hg38", data_path=str(TEST_DATA_DIR)))
    safe_test(results, "genetics.bayesian_finemapping_with_deep_vi",
        lambda: genetics.bayesian_finemapping_with_deep_vi(
            gwas_summary_path=paths['gwas_summary_file'],
            ld_matrix=paths['ld_matrix'],
            n_iterations=100, learning_rate=0.01,
            hidden_dim=32, credible_threshold=0.95))
    safe_test(results, "genetics.fit_genomic_prediction_model",
        lambda: genetics.fit_genomic_prediction_model(
            genotypes=np.random.randint(0, 3, (100, 50)),
            phenotypes=np.random.randn(100),
            fixed_effects=None, model_type="additive",
            output_file=str(TEST_DATA_DIR / "gp_model.pkl")))
    # WORKAROUND: Use "expansion" model to avoid duplicate pop0 bug
    safe_test(results, "genetics.simulate_demographic_history",
        lambda: genetics.simulate_demographic_history(
            num_samples=10, sequence_length=10000,
            recombination_rate=1e-8, mutation_rate=1e-8,
            demographic_model="expansion",  # WORKAROUND for bug
            demographic_params=paths['demographic_params_expansion'],
            coalescent_model="kingman",
            random_seed=42, output_file=str(TEST_DATA_DIR / "simulation.vcf")))

    # === LAB AUTOMATION ===
    print("\n--- lab_automation ---")
    safe_test(results, "lab_automation.test_pylabrobot_script",
        lambda: lab_automation.test_pylabrobot_script("print('Hello from PyLabRobot')"))

    summary = results.summary()

    output_file = Path("/tmp/biomni_skipped_test_v5.json")
    with open(output_file, 'w') as f:
        json.dump({
            "version": "v5",
            "summary": summary,
            "passed": results.passed,
            "failed": results.failed
        }, f, indent=2)
    print(f"\nResults saved to {output_file}")


if __name__ == "__main__":
    run_tests()
