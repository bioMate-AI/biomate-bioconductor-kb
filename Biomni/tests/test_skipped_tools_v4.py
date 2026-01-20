#!/usr/bin/env python3
"""
Test previously skipped Biomni tools - v4 with EXACT data formats from docstrings.

This version uses the exact data structures documented in each function's docstring,
based on systematic analysis of all failing functions.

Author: BioMate Testing Framework
Date: 2026-01-19
"""

import os
import sys
import json
import numpy as np
from pathlib import Path

TEST_DATA_DIR = Path("/tmp/biomni_test_v4")
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
        print(f"SKIPPED TOOLS TEST v4: {len(self.passed)}/{total} PASSED ({rate:.0f}%)")
        print(f"{'='*60}")
        return {"passed": len(self.passed), "total": total, "rate": rate}


def safe_test(results, name, func):
    try:
        result = func()
        results.add(name, "PASS", str(result)[:100] if result else "OK")
    except Exception as e:
        results.add(name, "FAIL", str(e))


def setup_mock_data():
    """Create all mock data files with EXACT formats from docstrings"""
    paths = {}

    # === IMAGES ===
    try:
        from PIL import Image
        # Colony image with clear spots
        img = np.zeros((512, 512), dtype=np.uint8)
        img[:] = 200  # Light background (agar)
        for _ in range(25):
            cx, cy = np.random.randint(50, 462, 2)
            radius = np.random.randint(5, 15)
            for i in range(512):
                for j in range(512):
                    if (i-cx)**2 + (j-cy)**2 < radius**2:
                        img[i,j] = np.random.randint(50, 100)  # Dark colonies
        img_path = str(TEST_DATA_DIR / "colony_image.png")
        Image.fromarray(img).save(img_path)
        paths['colony_image'] = img_path

        # General purpose images
        for i, name in enumerate(['image1', 'image2', 'image3']):
            img = np.random.randint(50, 200, (256, 256), dtype=np.uint8)
            p = str(TEST_DATA_DIR / f"{name}.png")
            Image.fromarray(img).save(p)
            paths[name] = p
    except Exception as e:
        print(f"  Warning: Image creation failed: {e}")

    # === ANNDATA ===
    try:
        import anndata as ad
        import pandas as pd
        import scipy.sparse as sp

        n_cells, n_genes = 100, 50
        X = sp.random(n_cells, n_genes, density=0.3, format='csr').astype(np.float32)
        obs = pd.DataFrame({
            'cell_type': np.random.choice(['T', 'B', 'NK'], n_cells),
            'batch': np.random.choice(['b1', 'b2'], n_cells),
        }, index=[f'cell_{i}' for i in range(n_cells)])
        var = pd.DataFrame(index=[f'gene_{i}' for i in range(n_genes)])

        adata = ad.AnnData(X=X, obs=obs, var=var)
        h5ad_path = str(TEST_DATA_DIR / "mock.h5ad")
        adata.write_h5ad(h5ad_path)
        paths['anndata'] = h5ad_path
    except:
        pass

    # === SEQUENCE FILES ===
    # PDB
    pdb_path = str(TEST_DATA_DIR / "mock.pdb")
    with open(pdb_path, 'w') as f:
        f.write("ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 20.00           N\n")
        f.write("ATOM      2  CA  ALA A   1       1.458   0.000   0.000  1.00 20.00           C\n")
        f.write("END\n")
    paths['pdb'] = pdb_path

    # FASTA
    fasta_path = str(TEST_DATA_DIR / "mock.fasta")
    with open(fasta_path, 'w') as f:
        f.write(f">seq1\n{SAMPLE_DNA}\n")
    paths['fasta'] = fasta_path

    # BED
    bed_path = str(TEST_DATA_DIR / "mock.bed")
    with open(bed_path, 'w') as f:
        f.write("chr1\t100\t200\tpeak1\t100\t+\n")
    paths['bed'] = bed_path

    # BAM
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
        pass

    # === EXACT FORMAT: MICROBIOLOGY ===

    # optimize_anaerobic_digestion_process
    # DOCSTRING FORMAT: operational_parameters needs TUPLES (min, max)
    paths['waste_characteristics'] = {
        "total_solids": 15.0,      # %
        "volatile_solids": 75.0,   # %
        "cod": 50000.0             # mg/L
    }
    paths['operational_parameters'] = {
        "hrt": (10, 30),           # TUPLE: (min, max) days
        "olr": (1.0, 4.0),         # TUPLE: (min, max) kg VS/(m³·d)
        "if_ratio": (0.5, 2.0),    # TUPLE: (min, max)
        "temperature": (30, 45),   # TUPLE: (min, max) °C
        "ph": (6.5, 8.0)           # TUPLE: (min, max)
    }

    # analyze_arsenic_speciation_hplc_icpms
    # DOCSTRING FORMAT: sample_data is dict with sample IDs as keys, values are dicts with retention times as keys
    paths['arsenic_sample_data'] = {
        "sample_001": {2.5: 15000, 4.2: 8500, 6.1: 3200},  # retention_time: intensity
        "sample_002": {2.5: 12000, 4.2: 9200, 6.1: 2800}
    }
    paths['arsenic_calibration'] = {
        "As(III)": [(0.1, 1500), (0.5, 7500), (1.0, 15000)],  # (concentration, signal)
        "As(V)": [(0.1, 950), (0.5, 4750), (1.0, 9500)],
        "MMA": [(0.1, 320), (0.5, 1600), (1.0, 3200)]
    }

    # === EXACT FORMAT: PHARMACOLOGY ===

    # analyze_western_blot
    # DOCSTRING FORMAT: target_bands is list of dicts with 'name' and 'roi'
    paths['western_target_bands'] = [
        {"name": "p53", "roi": [100, 50, 50, 30]},      # [x, y, width, height]
        {"name": "Bcl-2", "roi": [100, 100, 50, 30]}
    ]
    paths['western_loading_control'] = {"name": "GAPDH", "roi": [100, 200, 50, 30]}
    paths['western_antibody_info'] = {
        "primary": {"name": "anti-p53", "dilution": "1:1000", "source": "mouse"},
        "secondary": {"name": "anti-mouse HRP", "dilution": "1:5000"}
    }

    # analyze_accelerated_stability_of_pharmaceutical_formulations
    # DOCSTRING FORMAT: formulations is LIST of dicts, storage_conditions is LIST of dicts
    paths['formulations'] = [
        {
            "name": "Formulation A",
            "active_ingredient": "Aspirin",
            "concentration": 100.0,  # mg/mL
            "excipients": ["lactose", "starch", "magnesium stearate"]
        },
        {
            "name": "Formulation B",
            "active_ingredient": "Aspirin",
            "concentration": 50.0,
            "excipients": ["microcrystalline cellulose", "croscarmellose sodium"]
        }
    ]
    paths['storage_conditions'] = [
        {"temperature": 25.0, "humidity": 60.0, "description": "Room Temperature"},
        {"temperature": 40.0, "humidity": 75.0, "description": "Accelerated"}
    ]
    paths['time_points'] = [0, 30, 90, 180, 360]  # days

    # estimate_alpha_particle_radiotherapy_dosimetry
    # DOCSTRING FORMAT: biodistribution_data values are list of (time_hours, percent_injected_activity) tuples
    paths['biodistribution_data'] = {
        "tumor": [(1, 2.5), (4, 8.2), (24, 15.3), (48, 12.1), (72, 8.5)],
        "blood": [(1, 10.5), (4, 5.2), (24, 1.8), (48, 0.5), (72, 0.2)],
        "liver": [(1, 5.2), (4, 8.1), (24, 6.3), (48, 4.2), (72, 2.8)],
        "kidney": [(1, 3.1), (4, 4.5), (24, 3.2), (48, 2.1), (72, 1.5)],
        "spleen": [(1, 1.5), (4, 2.8), (24, 2.1), (48, 1.4), (72, 0.9)]
    }
    paths['radiation_parameters'] = {
        "radionuclide": "Ac-225",
        "half_life_hours": 240.0,  # 10 days
        "energy_per_decay_MeV": 28.0,
        "radiation_weighting_factor": 20.0,
        "S_factors": {
            "tumor_tumor": 5.2e-13,
            "liver_liver": 3.1e-13,
            "kidney_kidney": 4.5e-13
        }
    }

    # run_3d_chondrogenic_aggregate_assay
    # DOCSTRING FORMAT: chondrocyte_cells has 'source', 'passage_number', 'cell_density'
    paths['chondrocyte_cells'] = {
        "source": "human articular cartilage",
        "passage_number": 3,
        "cell_density": 250000  # cells per aggregate
    }
    # test_compounds is list of dicts with 'name', 'concentration', 'vehicle'
    paths['test_compounds'] = [
        {"name": "TGF-β3", "concentration": "10 ng/mL", "vehicle": "PBS + 0.1% BSA"},
        {"name": "BMP-2", "concentration": "100 ng/mL", "vehicle": "PBS + 0.1% BSA"}
    ]

    # === EXACT FORMAT: SYNTHETIC BIOLOGY ===

    # create_biochemical_network_sbml_model
    # DOCSTRING FORMAT: reaction_network list has 'reactants' and 'products' as DICTS with stoichiometry
    paths['reaction_network'] = [
        {
            "id": "R1",
            "name": "Glucose uptake",
            "reactants": {"Glucose_ext": 1},  # species: stoichiometry
            "products": {"Glucose": 1},
            "reversible": False
        },
        {
            "id": "R2",
            "name": "Glycolysis",
            "reactants": {"Glucose": 1, "ATP": 2},
            "products": {"Pyruvate": 2, "ATP": 4},
            "reversible": False
        }
    ]
    # kinetic_parameters maps reaction IDs to law_type and parameters
    paths['kinetic_parameters'] = {
        "R1": {
            "law_type": "mass_action",
            "parameters": {"k_forward": 0.1}
        },
        "R2": {
            "law_type": "michaelis_menten",
            "parameters": {"Vmax": 10.0, "Km": 0.5}
        }
    }

    # === EXACT FORMAT: SYSTEMS BIOLOGY ===

    # simulate_renin_angiotensin_system_dynamics
    # DOCSTRING FORMAT: initial_concentrations needs specific keys including 'angiotensin_I'
    paths['ras_initial_concentrations'] = {
        "renin": 1.0,
        "angiotensinogen": 100.0,
        "angiotensin_I": 0.0,
        "angiotensin_II": 0.0,
        "ACE2_angiotensin_II": 0.0,
        "angiotensin_1_7": 0.0
    }
    paths['ras_rate_constants'] = {
        "k_ren": 0.1,    # renin production
        "k_agt": 0.5,    # angiotensinogen production
        "k_ace": 0.3,    # ACE conversion rate
        "k_ace2": 0.2,   # ACE2 conversion rate
        "k_at1r": 0.15,  # AT1R binding rate
        "k_mas": 0.1     # Mas receptor binding rate
    }
    paths['ras_feedback_params'] = {
        "fb_ang_II": 0.05,   # angiotensin II feedback
        "fb_ace2": 0.03      # ACE2 feedback
    }

    # simulate_metabolic_network_perturbation
    # DOCSTRING FORMAT: perturbation_params needs 'time', 'metabolite', 'factor'
    paths['perturbation_params'] = {
        "time": 50.0,          # time at which perturbation is applied
        "metabolite": "A",     # ID of metabolite to perturb
        "factor": 2.0          # multiplication factor
    }

    # === EXACT FORMAT: IMMUNOLOGY ===

    # analyze_ebv_antibody_titers
    # DOCSTRING FORMAT: raw_od_data is dict with sample_id: {antibody_type: OD_value}
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
    # standard_curve_data is dict with antibody_type: [(concentration, OD), ...]
    paths['ebv_standard_curve'] = {
        "VCA_IgG": [(0, 0.05), (10, 0.25), (50, 0.85), (100, 1.5), (500, 2.2)],
        "VCA_IgM": [(0, 0.04), (10, 0.22), (50, 0.78), (100, 1.4), (500, 2.0)],
        "EA_IgG": [(0, 0.03), (10, 0.18), (50, 0.65), (100, 1.2), (500, 1.8)],
        "EA_IgM": [(0, 0.03), (10, 0.15), (50, 0.55), (100, 1.0), (500, 1.5)],
        "EBNA1_IgG": [(0, 0.04), (10, 0.20), (50, 0.72), (100, 1.35), (500, 1.95)],
        "EBNA1_IgM": [(0, 0.03), (10, 0.12), (50, 0.45), (100, 0.85), (500, 1.3)]
    }
    paths['ebv_sample_metadata'] = {
        "patient_001": {"group": "chronic", "collection_date": "2026-01-15"},
        "patient_002": {"group": "acute", "collection_date": "2026-01-16"}
    }

    # estimate_cell_cycle_phase_durations
    # DOCSTRING FORMAT: flow_cytometry_data is dict with specific keys
    n_timepoints = 10
    paths['flow_cytometry_data'] = {
        "time_points": list(range(0, n_timepoints * 2, 2)),  # hours
        "edu_positive": [5 + i*3 + np.random.randn()*2 for i in range(n_timepoints)],
        "brdu_positive": [3 + i*2.5 + np.random.randn()*1.5 for i in range(n_timepoints)],
        "double_positive": [1 + i*1.5 + np.random.randn() for i in range(n_timepoints)]
    }
    paths['cell_cycle_initial_estimates'] = {
        "g1_duration": 10.0,    # hours
        "s_duration": 8.0,      # hours
        "g2m_duration": 4.0,    # hours
        "death_rate": 0.01      # fraction per hour
    }

    # === EXACT FORMAT: BIOENGINEERING ===

    # decode_behavior_from_neural_trajectories
    # DOCSTRING FORMAT: neural_data is (n_timepoints, n_neurons), behavioral_data is (n_timepoints, n_variables)
    n_timepoints = 500
    n_neurons = 50
    n_behavioral_vars = 3
    paths['neural_data_2d'] = np.random.randn(n_timepoints, n_neurons)
    paths['behavioral_data_2d'] = np.random.randn(n_timepoints, n_behavioral_vars)

    # === EXACT FORMAT: GENETICS ===

    # simulate_demographic_history
    # DOCSTRING FORMAT for "constant" model: {"N": population size}
    paths['demographic_params_constant'] = {"N": 10000}

    # bayesian_finemapping_with_deep_vi
    # DOCSTRING FORMAT: GWAS file needs 'variant_id', 'effect_size', 'pvalue', 'se'
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

    # LD matrix
    n_variants = 100
    ld = np.eye(n_variants)
    for i in range(n_variants):
        for j in range(max(0, i-5), min(n_variants, i+6)):
            if i != j:
                ld[i, j] = 0.5 ** abs(i - j)
    paths['ld_matrix'] = ld

    # === CSV FILES ===

    # Tumor growth data
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

    # Expression data
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

    # GC data
    gc_path = str(TEST_DATA_DIR / "gc_data.csv")
    with open(gc_path, 'w') as f:
        f.write("retention_time,area,compound\n")
        f.write("5.2,12500,C16:0\n8.4,8900,C18:0\n10.1,15600,C18:1\n")
    paths['gc_data'] = gc_path

    # ATP luminescence
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

    # SBML model
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

    # Barcode file
    barcode_path = str(TEST_DATA_DIR / "barcodes.txt")
    with open(barcode_path, 'w') as f:
        for i in range(100):
            barcode = ''.join(np.random.choice(['A', 'T', 'G', 'C'], 20))
            f.write(f"{barcode}\t{np.random.randint(1, 1000)}\n")
    paths['barcode_file'] = barcode_path

    return paths


def run_tests():
    print("="*60)
    print("TESTING PREVIOUSLY SKIPPED TOOLS - v4 (EXACT FORMATS)")
    print("="*60)

    print("\nCreating mock data with EXACT docstring formats...")
    paths = setup_mock_data()
    print(f"Created {len(paths)} data items")

    results = Results()

    # Import modules
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
    # scRNA functions - explicitly mark as needing data_lake_path
    safe_test(results, "genomics.annotate_celltype_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: data_lake_path with celltype annotation models")))
    safe_test(results, "genomics.create_harmony_embeddings_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: proper data_dir with batch information")))
    safe_test(results, "genomics.create_scvi_embeddings_scRNA",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: scVI trained model in data_lake_path")))

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
            paths['colony_image'],
            dilution_factor=1,
            plate_area_cm2=65.0,
            output_dir=str(TEST_DATA_DIR / "colonies_out")))
    safe_test(results, "microbiology.segment_and_analyze_microbial_cells",
        lambda: microbiology.segment_and_analyze_microbial_cells(paths['image1']))
    safe_test(results, "microbiology.segment_cells_with_deep_learning",
        lambda: microbiology.segment_cells_with_deep_learning(paths['image1']))
    # EXACT FORMAT: operational_parameters with TUPLES
    safe_test(results, "microbiology.optimize_anaerobic_digestion_process",
        lambda: microbiology.optimize_anaerobic_digestion_process(
            waste_characteristics=paths['waste_characteristics'],
            operational_parameters=paths['operational_parameters'],
            target_output='methane_yield',
            optimization_method='rsm'))
    # EXACT FORMAT: sample_data as dict with sample_id: {retention_time: intensity}
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
    safe_test(results, "pharmacology.docking_autodock_vina",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: PyScreener properly configured")))
    safe_test(results, "pharmacology.run_autosite",
        lambda: (_ for _ in ()).throw(Exception("REQUIRES: prepare_receptor binary from MGLTools")))
    # EXACT FORMAT: target_bands as list of dicts with 'name' and 'roi'
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
            data_path=paths['tumor_csv'],
            time_column='time',
            volume_column='volume',
            group_column='group',
            subject_column='subject',
            output_dir=str(TEST_DATA_DIR / "tumor_out")))
    # EXACT FORMAT: formulations as LIST of dicts, storage_conditions as LIST of dicts
    safe_test(results, "pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations",
        lambda: pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations(
            formulations=paths['formulations'],
            storage_conditions=paths['storage_conditions'],
            time_points=paths['time_points']))
    safe_test(results, "pharmacology.analyze_radiolabeled_antibody_biodistribution",
        lambda: pharmacology.analyze_radiolabeled_antibody_biodistribution(
            time_points=[1, 4, 24, 48, 72],
            tissue_data={"blood": [10, 8, 4, 2, 1], "tumor": [2, 5, 8, 10, 9]}))
    # EXACT FORMAT: biodistribution_data values are list of (time, activity) tuples
    safe_test(results, "pharmacology.estimate_alpha_particle_radiotherapy_dosimetry",
        lambda: pharmacology.estimate_alpha_particle_radiotherapy_dosimetry(
            biodistribution_data=paths['biodistribution_data'],
            radiation_parameters=paths['radiation_parameters'],
            output_file=str(TEST_DATA_DIR / "dosimetry.csv")))
    safe_test(results, "pharmacology.perform_mwas_cyp2c19_metabolizer_status",
        lambda: pharmacology.perform_mwas_cyp2c19_metabolizer_status(
            np.random.randn(100, 50), np.random.choice(["PM", "IM", "EM", "UM"], 100)))
    # EXACT FORMAT: test_compounds is list of dicts with 'name', 'concentration', 'vehicle'
    safe_test(results, "pharmacology.run_3d_chondrogenic_aggregate_assay",
        lambda: pharmacology.run_3d_chondrogenic_aggregate_assay(
            chondrocyte_cells=paths['chondrocyte_cells'],
            test_compounds=paths['test_compounds'],
            culture_duration_days=21,
            measurement_intervals=7))

    # === SYNTHETIC BIOLOGY ===
    print("\n--- synthetic_biology ---")
    # EXACT FORMAT: reaction_network reactants/products are DICTS with stoichiometry
    safe_test(results, "synthetic_biology.create_biochemical_network_sbml_model",
        lambda: synthetic_biology.create_biochemical_network_sbml_model(
            reaction_network=paths['reaction_network'],
            kinetic_parameters=paths['kinetic_parameters'],
            output_file=str(TEST_DATA_DIR / "network.xml")))
    safe_test(results, "synthetic_biology.analyze_barcode_sequencing_data",
        lambda: synthetic_biology.analyze_barcode_sequencing_data(paths['barcode_file']))

    # === SYSTEMS BIOLOGY ===
    print("\n--- systems_biology ---")
    # EXACT FORMAT: query_chatnt needs both question AND sequence
    safe_test(results, "systems_biology.query_chatnt",
        lambda: systems_biology.query_chatnt(
            question="What is the GC content of this sequence?",
            sequence=SAMPLE_DNA))
    # EXACT FORMAT: initial_concentrations needs all specific keys including 'angiotensin_I'
    safe_test(results, "systems_biology.simulate_renin_angiotensin_system_dynamics",
        lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(
            initial_concentrations=paths['ras_initial_concentrations'],
            rate_constants=paths['ras_rate_constants'],
            feedback_params=paths['ras_feedback_params'],
            simulation_time=48,
            time_points=100))
    # EXACT FORMAT: perturbation_params needs 'time', 'metabolite', 'factor'
    safe_test(results, "systems_biology.simulate_metabolic_network_perturbation",
        lambda: systems_biology.simulate_metabolic_network_perturbation(
            model_file=paths['sbml_model'],
            initial_concentrations={"A": 1.0, "B": 0.0},
            perturbation_params=paths['perturbation_params'],
            simulation_time=100,
            time_points=100))
    safe_test(results, "systems_biology.compare_protein_structures",
        lambda: systems_biology.compare_protein_structures(paths['pdb'], paths['pdb']))

    # === IMMUNOLOGY ===
    print("\n--- immunology ---")
    # EXACT FORMAT: raw_od_data is dict with sample_id: {antibody_type: OD_value}
    safe_test(results, "immunology.analyze_ebv_antibody_titers",
        lambda: immunology.analyze_ebv_antibody_titers(
            raw_od_data=paths['ebv_raw_od_data'],
            standard_curve_data=paths['ebv_standard_curve'],
            sample_metadata=paths['ebv_sample_metadata'],
            output_dir=str(TEST_DATA_DIR / "ebv_out")))
    # EXACT FORMAT: flow_cytometry_data is dict with specific keys
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
            gc_data_file=paths['gc_data'],
            tissue_type="liver",
            sample_id="sample_001",
            output_directory=str(TEST_DATA_DIR / "fatty_out")))
    safe_test(results, "physiology.analyze_protein_colocalization",
        lambda: physiology.analyze_protein_colocalization(paths['image1'], paths['image2']))
    safe_test(results, "physiology.quantify_amyloid_beta_plaques",
        lambda: physiology.quantify_amyloid_beta_plaques(paths['image1']))

    # === PATHOLOGY ===
    print("\n--- pathology ---")
    safe_test(results, "pathology.analyze_atp_luminescence_assay",
        lambda: pathology.analyze_atp_luminescence_assay(
            data_file=paths['atp_data'],
            standard_curve_file=paths['atp_standard'],
            normalization_method="protein",
            normalization_data={"sample_0": 1.2}))
    safe_test(results, "pathology.analyze_aortic_diameter_and_geometry",
        lambda: pathology.analyze_aortic_diameter_and_geometry(paths['image1']))
    safe_test(results, "pathology.analyze_thrombus_histology",
        lambda: pathology.analyze_thrombus_histology(paths['image1'], str(TEST_DATA_DIR / "thrombus_out")))
    safe_test(results, "pathology.quantify_corneal_nerve_fibers",
        lambda: pathology.quantify_corneal_nerve_fibers(
            image_path=paths['image1'],
            marker_type="tubulin",
            output_dir=str(TEST_DATA_DIR / "cornea_out"),
            threshold_method="otsu"))
    safe_test(results, "pathology.analyze_intracellular_calcium_with_rhod2",
        lambda: pathology.analyze_intracellular_calcium_with_rhod2(
            background_image_path=paths['image1'],
            control_image_path=paths['image2'],
            sample_image_path=paths['image3'],
            output_dir=str(TEST_DATA_DIR / "calcium_out")))
    safe_test(results, "pathology.segment_and_quantify_cells_in_multiplexed_images",
        lambda: pathology.segment_and_quantify_cells_in_multiplexed_images(
            image_path=paths['image1'],
            markers_list=["CD3", "CD4", "CD8"],
            nuclear_channel_index=0,
            output_dir=str(TEST_DATA_DIR / "multiplex_out")))

    # === BIOENGINEERING ===
    print("\n--- bioengineering ---")
    safe_test(results, "bioengineering.analyze_myofiber_morphology",
        lambda: bioengineering.analyze_myofiber_morphology(paths['image1']))
    # EXACT FORMAT: neural_data is 2D (n_timepoints, n_neurons), NOT 3D
    safe_test(results, "bioengineering.decode_behavior_from_neural_trajectories",
        lambda: bioengineering.decode_behavior_from_neural_trajectories(
            neural_data=paths['neural_data_2d'],
            behavioral_data=paths['behavioral_data_2d'],
            n_components=10,
            output_dir=str(TEST_DATA_DIR / "neural_out")))

    # === GENETICS ===
    print("\n--- genetics ---")
    safe_test(results, "genetics.liftover_coordinates",
        lambda: genetics.liftover_coordinates(
            chromosome="chr1",
            position=12345,
            input_format="hg19",
            output_format="hg38",
            data_path=str(TEST_DATA_DIR)))
    # EXACT FORMAT: GWAS file needs 'variant_id', 'effect_size', 'pvalue', 'se' columns
    safe_test(results, "genetics.bayesian_finemapping_with_deep_vi",
        lambda: genetics.bayesian_finemapping_with_deep_vi(
            gwas_summary_path=paths['gwas_summary_file'],
            ld_matrix=paths['ld_matrix'],
            n_iterations=100,
            learning_rate=0.01,
            hidden_dim=32,
            credible_threshold=0.95))
    safe_test(results, "genetics.fit_genomic_prediction_model",
        lambda: genetics.fit_genomic_prediction_model(
            genotypes=np.random.randint(0, 3, (100, 50)),
            phenotypes=np.random.randn(100),
            fixed_effects=None,
            model_type="additive",
            output_file=str(TEST_DATA_DIR / "gp_model.pkl")))
    # EXACT FORMAT for "constant" model: {"N": population_size}
    safe_test(results, "genetics.simulate_demographic_history",
        lambda: genetics.simulate_demographic_history(
            num_samples=10,
            sequence_length=10000,
            recombination_rate=1e-8,
            mutation_rate=1e-8,
            demographic_model="constant",
            demographic_params=paths['demographic_params_constant'],
            coalescent_model="kingman",
            beta_coalescent_param=None,
            random_seed=42,
            output_file=str(TEST_DATA_DIR / "simulation.vcf")))

    # === LAB AUTOMATION ===
    print("\n--- lab_automation ---")
    safe_test(results, "lab_automation.test_pylabrobot_script",
        lambda: lab_automation.test_pylabrobot_script("print('Hello from PyLabRobot')"))

    # Summary
    summary = results.summary()

    # Save detailed results
    output_file = Path("/tmp/biomni_skipped_test_v4.json")
    with open(output_file, 'w') as f:
        json.dump({
            "version": "v4",
            "summary": summary,
            "passed": results.passed,
            "failed": results.failed
        }, f, indent=2)
    print(f"\nResults saved to {output_file}")


if __name__ == "__main__":
    run_tests()
