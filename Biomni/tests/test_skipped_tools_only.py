#!/usr/bin/env python3
"""
Test ONLY the previously skipped Biomni tools.
Creates mock data and tests each one - NO SKIPS ALLOWED.
"""

import os
import sys
import json
import numpy as np
from pathlib import Path

BIOMNI_PATH = "/home/yzhang/biomate/Biomni"
if BIOMNI_PATH not in sys.path:
    sys.path.insert(0, BIOMNI_PATH)

TEST_DATA_DIR = Path("/tmp/biomni_skipped_test_data")
TEST_DATA_DIR.mkdir(exist_ok=True)

# Sample sequences
SAMPLE_PROTEIN = "MKFLILLFNILCLFPVLAADNHGVGPQGASGVDPITFDINSNQTGVQLTLNSTGSEEECKFSLFLKWFEPG"
SAMPLE_DNA = "ATGAAATTCCTGATCCTGCTGTTCAACATCCTGTGCCTGTTCCCTGTGCTGGCTGCTGACAACCATGGTGTGGGTCCACAGGGTGCTAGTGGTGTGGATCCTATCACCTTCGACATCAACAGCAACCAGACTGGTGTGCAGCTGACCCTGAACAGCACTGGTTCTGAGGAGGAGTGCAAATTCTCTCTGTTCCTGAAATGGTTTGAGCCTGGATGA"
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
            print(f"  ✗ {name}: {msg[:100]}")

    def summary(self):
        total = len(self.passed) + len(self.failed)
        print(f"\n{'='*60}")
        print(f"SKIPPED TOOLS TEST: {len(self.passed)}/{total} PASSED ({100*len(self.passed)/max(1,total):.0f}%)")
        print(f"{'='*60}")
        if self.failed:
            print("\nFailed tools:")
            for f in self.failed:
                print(f"  - {f['name']}: {f['message'][:80]}")


def safe_test(results, name, func):
    try:
        result = func()
        results.add(name, "PASS", str(result)[:50] if result else "OK")
    except Exception as e:
        results.add(name, "FAIL", str(e))


# ============================================================================
# MOCK DATA CREATION
# ============================================================================

def create_mock_image(size=(256, 256)):
    """Create mock grayscale image with cell-like structures"""
    path = str(TEST_DATA_DIR / "mock_image.png")
    try:
        from PIL import Image
        img = np.zeros(size, dtype=np.uint8)
        for _ in range(15):
            cx, cy = np.random.randint(30, size[0]-30, 2)
            for i in range(size[0]):
                for j in range(size[1]):
                    if (i-cx)**2 + (j-cy)**2 < 200:
                        img[i,j] = np.random.randint(150, 255)
        Image.fromarray(img).save(path)
    except:
        np.save(path.replace('.png', '.npy'), np.random.rand(*size))
    return path


def create_mock_image_sequence(n=5):
    """Create sequence of images"""
    paths = []
    for i in range(n):
        path = str(TEST_DATA_DIR / f"seq_{i}.png")
        try:
            from PIL import Image
            img = np.random.randint(0, 255, (256, 256), dtype=np.uint8)
            Image.fromarray(img).save(path)
            paths.append(path)
        except:
            paths.append(None)
    return paths


def create_mock_anndata():
    """Create mock AnnData h5ad file"""
    path = str(TEST_DATA_DIR / "mock.h5ad")
    try:
        import anndata as ad
        import pandas as pd
        import scipy.sparse as sp

        n_cells, n_genes = 100, 50
        X = sp.random(n_cells, n_genes, density=0.3, format='csr').astype(np.float32)
        obs = pd.DataFrame({
            'cell_type': np.random.choice(['T', 'B', 'NK'], n_cells),
            'batch': np.random.choice(['b1', 'b2'], n_cells)
        }, index=[f'cell_{i}' for i in range(n_cells)])
        var = pd.DataFrame(index=[f'gene_{i}' for i in range(n_genes)])

        adata = ad.AnnData(X=X, obs=obs, var=var)
        adata.obsm['X_pca'] = np.random.randn(n_cells, 20).astype(np.float32)
        adata.write_h5ad(path)
        return path
    except Exception as e:
        print(f"  Warning: Cannot create AnnData: {e}")
        return None


def create_mock_bam():
    """Create mock BAM file"""
    path = str(TEST_DATA_DIR / "mock.bam")
    try:
        import pysam
        header = {'HD': {'VN': '1.0'}, 'SQ': [{'LN': 10000, 'SN': 'chr1'}]}
        with pysam.AlignmentFile(path, "wb", header=header) as f:
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
        pysam.index(path)
        return path
    except Exception as e:
        print(f"  Warning: Cannot create BAM: {e}")
        return None


def create_mock_bed():
    """Create mock BED file"""
    path = str(TEST_DATA_DIR / "mock.bed")
    with open(path, 'w') as f:
        for i in range(50):
            f.write(f"chr1\t{i*1000}\t{i*1000+500}\tpeak_{i}\t100\t+\n")
    return path


def create_mock_fasta():
    """Create mock FASTA file"""
    path = str(TEST_DATA_DIR / "mock.fasta")
    with open(path, 'w') as f:
        for i in range(5):
            seq = ''.join(np.random.choice(list('ACGT'), 500))
            f.write(f">seq_{i}\n{seq}\n")
    return path


def create_mock_pdb():
    """Create mock PDB file"""
    path = str(TEST_DATA_DIR / "mock.pdb")
    pdb = """ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 20.00           N
ATOM      2  CA  ALA A   1       1.458   0.000   0.000  1.00 20.00           C
ATOM      3  C   ALA A   1       2.009   1.420   0.000  1.00 20.00           C
ATOM      4  O   ALA A   1       1.246   2.390   0.000  1.00 20.00           O
END
"""
    with open(path, 'w') as f:
        f.write(pdb)
    return path


def create_mock_fcs():
    """Create mock FCS file"""
    path = str(TEST_DATA_DIR / "mock.fcs")
    try:
        import fcswrite
        data = np.random.lognormal(10, 1, (1000, 5)).astype(np.float32)
        fcswrite.write_fcs(path, ['FSC', 'SSC', 'FITC', 'PE', 'APC'], data)
        return path
    except:
        # Create placeholder
        with open(path, 'wb') as f:
            f.write(b'FCS3.0' + b'\x00' * 500)
        return path


def create_mock_cool():
    """Create mock cooler file"""
    path = str(TEST_DATA_DIR / "mock.cool")
    try:
        import cooler
        import pandas as pd
        bins = pd.DataFrame({
            'chrom': ['chr1'] * 50,
            'start': np.arange(0, 500000, 10000),
            'end': np.arange(10000, 500010, 10000)
        })
        pixels = pd.DataFrame({
            'bin1_id': np.random.randint(0, 50, 500),
            'bin2_id': np.random.randint(0, 50, 500),
            'count': np.random.poisson(5, 500)
        })
        cooler.create_cooler(path, bins, pixels)
        return path
    except:
        return None


# ============================================================================
# TEST ALL SKIPPED TOOLS
# ============================================================================

def run_tests():
    print("="*60)
    print("TESTING PREVIOUSLY SKIPPED TOOLS ONLY")
    print("="*60)

    # Create all mock data
    print("\nCreating mock data...")
    paths = {
        'image': create_mock_image(),
        'image_seq': create_mock_image_sequence(),
        'anndata': create_mock_anndata(),
        'bam': create_mock_bam(),
        'bed': create_mock_bed(),
        'fasta': create_mock_fasta(),
        'pdb': create_mock_pdb(),
        'fcs': create_mock_fcs(),
        'cool': create_mock_cool(),
    }
    print(f"Created mock data: {[k for k,v in paths.items() if v]}")

    results = Results()

    # ========== DATABASE ==========
    print("\n--- database ---")
    try:
        from biomni.tool import database
        safe_test(results, "database.get_hpo_names",
                  lambda: database.get_hpo_names(["HP:0000001"], data_lake_path=str(TEST_DATA_DIR)))
    except ImportError as e:
        results.add("database.import", "FAIL", str(e))

    # ========== MOLECULAR BIOLOGY ==========
    print("\n--- molecular_biology ---")
    try:
        from biomni.tool import molecular_biology
        safe_test(results, "molecular_biology.design_knockout_sgrna",
                  lambda: molecular_biology.design_knockout_sgrna("TP53", data_lake_path=str(TEST_DATA_DIR)))
    except ImportError as e:
        results.add("molecular_biology.import", "FAIL", str(e))

    # ========== LITERATURE ==========
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

        if paths['cool']:
            safe_test(results, "genomics.analyze_chromatin_interactions",
                      lambda: genomics.analyze_chromatin_interactions(paths['cool']))
        else:
            results.add("genomics.analyze_chromatin_interactions", "FAIL", "No cooler file")

        if paths['fasta']:
            safe_test(results, "genomics.analyze_comparative_genomics_and_haplotypes",
                      lambda: genomics.analyze_comparative_genomics_and_haplotypes([paths['fasta']]))

        if paths['bed']:
            safe_test(results, "genomics.analyze_genomic_region_overlap",
                      lambda: genomics.analyze_genomic_region_overlap(paths['bed'], paths['bed']))
            safe_test(results, "genomics.find_enriched_motifs_with_homer",
                      lambda: genomics.find_enriched_motifs_with_homer(paths['bed']))

        if paths['anndata']:
            safe_test(results, "genomics.annotate_celltype_scRNA",
                      lambda: genomics.annotate_celltype_scRNA(paths['anndata']))
            safe_test(results, "genomics.annotate_celltype_with_panhumanpy",
                      lambda: genomics.annotate_celltype_with_panhumanpy(paths['anndata']))
            safe_test(results, "genomics.create_harmony_embeddings_scRNA",
                      lambda: genomics.create_harmony_embeddings_scRNA(paths['anndata'], batch_key='batch'))
            safe_test(results, "genomics.create_scvi_embeddings_scRNA",
                      lambda: genomics.create_scvi_embeddings_scRNA(paths['anndata']))
            safe_test(results, "genomics.generate_embeddings_with_state",
                      lambda: genomics.generate_embeddings_with_state(paths['anndata']))
            safe_test(results, "genomics.generate_transcriptformer_embeddings",
                      lambda: genomics.generate_transcriptformer_embeddings(paths['anndata']))
            safe_test(results, "genomics.get_uce_embeddings_scRNA",
                      lambda: genomics.get_uce_embeddings_scRNA(paths['anndata']))
            safe_test(results, "genomics.map_to_ima_interpret_scRNA",
                      lambda: genomics.map_to_ima_interpret_scRNA(paths['anndata']))
            safe_test(results, "genomics.unsupervised_celltype_transfer_between_scRNA_datasets",
                      lambda: genomics.unsupervised_celltype_transfer_between_scRNA_datasets(paths['anndata'], paths['anndata']))
        else:
            for name in ["annotate_celltype_scRNA", "create_harmony_embeddings_scRNA",
                        "create_scvi_embeddings_scRNA", "generate_embeddings_with_state",
                        "generate_transcriptformer_embeddings", "get_uce_embeddings_scRNA",
                        "map_to_ima_interpret_scRNA", "unsupervised_celltype_transfer_between_scRNA_datasets",
                        "annotate_celltype_with_panhumanpy"]:
                results.add(f"genomics.{name}", "FAIL", "No AnnData - install anndata")

        # GPU test
        safe_test(results, "genomics.generate_gene_embeddings_with_ESM_models",
                  lambda: genomics.generate_gene_embeddings_with_ESM_models([SAMPLE_PROTEIN[:30]]))

        if paths['bam']:
            safe_test(results, "genomics.perform_chipseq_peak_calling_with_macs2",
                      lambda: genomics.perform_chipseq_peak_calling_with_macs2(paths['bam']))

    except ImportError as e:
        results.add("genomics.import", "FAIL", str(e))

    # ========== BIOCHEMISTRY ==========
    print("\n--- biochemistry ---")
    try:
        from biomni.tool import biochemistry
        itc_data = {'injection_volume': [2.0]*10, 'heat': list(np.random.randn(10)*10),
                    'ligand_conc': list(np.linspace(0, 100, 10)), 'protein_conc': 10.0}
        safe_test(results, "biochemistry.analyze_itc_binding_thermodynamics",
                  lambda: biochemistry.analyze_itc_binding_thermodynamics(itc_data))
    except ImportError as e:
        results.add("biochemistry.import", "FAIL", str(e))

    # ========== MICROBIOLOGY ==========
    print("\n--- microbiology ---")
    try:
        from biomni.tool import microbiology

        if paths['fasta']:
            safe_test(results, "microbiology.annotate_bacterial_genome",
                      lambda: microbiology.annotate_bacterial_genome(paths['fasta']))

        if paths['image']:
            safe_test(results, "microbiology.count_bacterial_colonies",
                      lambda: microbiology.count_bacterial_colonies(paths['image']))
            safe_test(results, "microbiology.segment_and_analyze_microbial_cells",
                      lambda: microbiology.segment_and_analyze_microbial_cells(paths['image']))
            safe_test(results, "microbiology.segment_cells_with_deep_learning",
                      lambda: microbiology.segment_cells_with_deep_learning(paths['image']))

        waste = {'vfa': [10, 15, 20], 'ph': [7.0, 6.8, 6.5], 'temp': [35, 35, 35]}
        safe_test(results, "microbiology.optimize_anaerobic_digestion_process",
                  lambda: microbiology.optimize_anaerobic_digestion_process(waste))

        hplc = {'retention_time': [1.0, 2.0, 3.0], 'intensity': [100, 200, 150]}
        safe_test(results, "microbiology.analyze_arsenic_speciation_hplc_icpms",
                  lambda: microbiology.analyze_arsenic_speciation_hplc_icpms(hplc))

    except ImportError as e:
        results.add("microbiology.import", "FAIL", str(e))

    # ========== BIOPHYSICS ==========
    print("\n--- biophysics ---")
    try:
        from biomni.tool import biophysics
        if paths['image']:
            safe_test(results, "biophysics.analyze_cell_morphology_and_cytoskeleton",
                      lambda: biophysics.analyze_cell_morphology_and_cytoskeleton(paths['image']))
        if paths['image_seq'] and len([p for p in paths['image_seq'] if p]) >= 2:
            safe_test(results, "biophysics.analyze_tissue_deformation_flow",
                      lambda: biophysics.analyze_tissue_deformation_flow([p for p in paths['image_seq'] if p]))
    except ImportError as e:
        results.add("biophysics.import", "FAIL", str(e))

    # ========== PHARMACOLOGY ==========
    print("\n--- pharmacology ---")
    try:
        from biomni.tool import pharmacology

        # GPU/Model tests
        safe_test(results, "pharmacology.predict_admet_properties",
                  lambda: pharmacology.predict_admet_properties(SAMPLE_SMILES))
        safe_test(results, "pharmacology.predict_binding_affinity_protein_1d_sequence",
                  lambda: pharmacology.predict_binding_affinity_protein_1d_sequence(SAMPLE_SMILES, SAMPLE_PROTEIN))

        if paths['pdb']:
            safe_test(results, "pharmacology.docking_autodock_vina",
                      lambda: pharmacology.docking_autodock_vina(paths['pdb'], SAMPLE_SMILES))
            safe_test(results, "pharmacology.run_autosite",
                      lambda: pharmacology.run_autosite(paths['pdb']))
            safe_test(results, "pharmacology.run_diffdock_with_smiles",
                      lambda: pharmacology.run_diffdock_with_smiles(SAMPLE_SMILES, paths['pdb']))

        if paths['image']:
            safe_test(results, "pharmacology.analyze_western_blot",
                      lambda: pharmacology.analyze_western_blot(paths['image']))

        # Mock data tests
        clinical = {'patient_id': [1, 2], 'adverse_event': ['nausea', 'headache'], 'grade': [1, 2]}
        safe_test(results, "pharmacology.grade_adverse_events_using_vcog_ctcae",
                  lambda: pharmacology.grade_adverse_events_using_vcog_ctcae(clinical))

        tumor = {'time': [0, 7, 14], 'volume': [100, 150, 180]}
        safe_test(results, "pharmacology.analyze_xenograft_tumor_growth_inhibition",
                  lambda: pharmacology.analyze_xenograft_tumor_growth_inhibition(tumor))

        stability = {'time': [0, 30, 60], 'potency': [100, 98, 95], 'temp': 40}
        safe_test(results, "pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations",
                  lambda: pharmacology.analyze_accelerated_stability_of_pharmaceutical_formulations(stability))

        biodist = {'organ': ['liver', 'kidney'], 'uptake': [15.0, 8.0]}
        safe_test(results, "pharmacology.analyze_radiolabeled_antibody_biodistribution",
                  lambda: pharmacology.analyze_radiolabeled_antibody_biodistribution(biodist))

        dosimetry = {'tumor_volume': 10.0, 'activity': 1.0, 'half_life': 7.2}
        safe_test(results, "pharmacology.estimate_alpha_particle_radiotherapy_dosimetry",
                  lambda: pharmacology.estimate_alpha_particle_radiotherapy_dosimetry(dosimetry))

        meth = {'cpg_sites': [0.1, 0.2, 0.8], 'gene': ['CYP2C19']*3}
        safe_test(results, "pharmacology.perform_mwas_cyp2c19_metabolizer_status",
                  lambda: pharmacology.perform_mwas_cyp2c19_metabolizer_status(meth))

        safe_test(results, "pharmacology.retrieve_topk_repurposing_drugs_from_disease_txgnn",
                  lambda: pharmacology.retrieve_topk_repurposing_drugs_from_disease_txgnn("diabetes", k=3, data_lake_path=str(TEST_DATA_DIR)))

        cell = {'day': [0, 7, 14], 'diameter': [100, 200, 350]}
        safe_test(results, "pharmacology.run_3d_chondrogenic_aggregate_assay",
                  lambda: pharmacology.run_3d_chondrogenic_aggregate_assay(cell))

    except ImportError as e:
        results.add("pharmacology.import", "FAIL", str(e))

    # ========== SYNTHETIC BIOLOGY ==========
    print("\n--- synthetic_biology ---")
    try:
        from biomni.tool import synthetic_biology

        network = {'species': ['A', 'B'], 'reactions': [{'reactants': ['A'], 'products': ['B'], 'rate': 0.1}]}
        safe_test(results, "synthetic_biology.create_biochemical_network_sbml_model",
                  lambda: synthetic_biology.create_biochemical_network_sbml_model(network))

        if paths['fasta']:
            safe_test(results, "synthetic_biology.engineer_bacterial_genome_for_therapeutic_delivery",
                      lambda: synthetic_biology.engineer_bacterial_genome_for_therapeutic_delivery(paths['fasta'], "insulin"))

        circuit = np.array([[0, -1], [1, 0]])
        kinetic = {"basal_rates": [0.1, 0.1], "degradation_rates": [0.1, 0.1],
                   "hill_coefficients": [2, 2], "threshold_constants": [1, 1]}
        growth = {"max_growth_rate": 0.5, "growth_inhibition": 0.1, "gene_growth_weights": [0.5, 0.5]}
        safe_test(results, "synthetic_biology.simulate_gene_circuit_with_growth_feedback",
                  lambda: synthetic_biology.simulate_gene_circuit_with_growth_feedback(circuit, kinetic, growth, simulation_time=10))

        barcode = {'barcode': ['ACGT', 'TGCA'], 'count': [100, 50]}
        safe_test(results, "synthetic_biology.analyze_barcode_sequencing_data",
                  lambda: synthetic_biology.analyze_barcode_sequencing_data(barcode))

    except ImportError as e:
        results.add("synthetic_biology.import", "FAIL", str(e))

    # ========== SYSTEMS BIOLOGY ==========
    print("\n--- systems_biology ---")
    try:
        from biomni.tool import systems_biology

        safe_test(results, "systems_biology.query_chatnt",
                  lambda: systems_biology.query_chatnt("What is TP53?"))

        # Create mock SBML
        sbml_path = str(TEST_DATA_DIR / "mock.sbml")
        sbml = """<?xml version="1.0"?><sbml xmlns="http://www.sbml.org/sbml/level3/version2/core" level="3" version="2"><model id="m"><listOfCompartments><compartment id="c" size="1"/></listOfCompartments></model></sbml>"""
        with open(sbml_path, 'w') as f:
            f.write(sbml)

        safe_test(results, "systems_biology.perform_flux_balance_analysis",
                  lambda: systems_biology.perform_flux_balance_analysis(sbml_path))
        safe_test(results, "systems_biology.simulate_metabolic_network_perturbation",
                  lambda: systems_biology.simulate_metabolic_network_perturbation(sbml_path, {'A': 0.5}))

        if paths['pdb']:
            safe_test(results, "systems_biology.compare_protein_structures",
                      lambda: systems_biology.compare_protein_structures(paths['pdb'], paths['pdb']))

        network = {"B": [("A", 1)]}
        rxn = {("A", "B"): {"W": 1.0, "n": 2, "EC50": 0.5}}
        species = {"A": {"tau": 1.0, "y0": 1.0, "ymax": 1.0}, "B": {"tau": 2.0, "y0": 0.0, "ymax": 1.0}}
        safe_test(results, "systems_biology.simulate_protein_signaling_network",
                  lambda: systems_biology.simulate_protein_signaling_network(network, rxn, species))

        conc = {"renin": 1.0, "angiotensinogen": 100.0, "angiotensin_I": 0.0, "angiotensin_II": 0.0}
        rate = {"k_ren": 0.1, "k_agt": 0.05, "k_ace": 0.5}
        fb = {"fb_ang_II": 0.1}
        safe_test(results, "systems_biology.simulate_renin_angiotensin_system_dynamics",
                  lambda: systems_biology.simulate_renin_angiotensin_system_dynamics(conc, rate, fb))

    except ImportError as e:
        results.add("systems_biology.import", "FAIL", str(e))

    # ========== IMMUNOLOGY ==========
    print("\n--- immunology ---")
    try:
        from biomni.tool import immunology

        if paths['bam']:
            safe_test(results, "immunology.analyze_atac_seq_differential_accessibility",
                      lambda: immunology.analyze_atac_seq_differential_accessibility(paths['bam'], paths['bam']))

        if paths['fcs']:
            safe_test(results, "immunology.analyze_cfse_cell_proliferation",
                      lambda: immunology.analyze_cfse_cell_proliferation(paths['fcs']))
            safe_test(results, "immunology.analyze_cytokine_production_in_cd4_tcells",
                      lambda: immunology.analyze_cytokine_production_in_cd4_tcells(paths['fcs']))
            safe_test(results, "immunology.estimate_cell_cycle_phase_durations",
                      lambda: immunology.estimate_cell_cycle_phase_durations(paths['fcs']))

        if paths['image']:
            safe_test(results, "immunology.analyze_cns_lesion_histology",
                      lambda: immunology.analyze_cns_lesion_histology(paths['image']))
            safe_test(results, "immunology.analyze_immunohistochemistry_image",
                      lambda: immunology.analyze_immunohistochemistry_image(paths['image']))

        if paths['image_seq'] and len([p for p in paths['image_seq'] if p]) >= 2:
            safe_test(results, "immunology.track_immune_cells_under_flow",
                      lambda: immunology.track_immune_cells_under_flow([p for p in paths['image_seq'] if p]))

        elisa = {'dilution': [1, 10, 100], 'od': [2.0, 1.0, 0.3]}
        safe_test(results, "immunology.analyze_ebv_antibody_titers",
                  lambda: immunology.analyze_ebv_antibody_titers(elisa))

    except ImportError as e:
        results.add("immunology.import", "FAIL", str(e))

    # ========== CELL BIOLOGY ==========
    print("\n--- cell_biology ---")
    try:
        from biomni.tool import cell_biology

        if paths['fcs']:
            safe_test(results, "cell_biology.analyze_flow_cytometry_immunophenotyping",
                      lambda: cell_biology.analyze_flow_cytometry_immunophenotyping(paths['fcs']))

        if paths['image']:
            safe_test(results, "cell_biology.analyze_mitochondrial_morphology_and_potential",
                      lambda: cell_biology.analyze_mitochondrial_morphology_and_potential(paths['image']))
            safe_test(results, "cell_biology.quantify_cell_cycle_phases_from_microscopy",
                      lambda: cell_biology.quantify_cell_cycle_phases_from_microscopy(paths['image']))

        if paths['image_seq'] and len([p for p in paths['image_seq'] if p]) >= 2:
            safe_test(results, "cell_biology.quantify_and_cluster_cell_motility",
                      lambda: cell_biology.quantify_and_cluster_cell_motility([p for p in paths['image_seq'] if p]))

    except ImportError as e:
        results.add("cell_biology.import", "FAIL", str(e))

    # ========== CANCER BIOLOGY ==========
    print("\n--- cancer_biology ---")
    try:
        from biomni.tool import cancer_biology

        expr = {'gene': ['TP53', 'BRCA1'], 'expression': [10.5, 8.2]}
        mut = {'gene': ['TP53'], 'mutation': ['R273H']}
        safe_test(results, "cancer_biology.analyze_ddr_network_in_cancer",
                  lambda: cancer_biology.analyze_ddr_network_in_cancer(expr, mut))

        if paths['fcs']:
            safe_test(results, "cancer_biology.analyze_cell_senescence_and_apoptosis",
                      lambda: cancer_biology.analyze_cell_senescence_and_apoptosis(paths['fcs']))

        if paths['bam']:
            safe_test(results, "cancer_biology.analyze_copy_number_purity_ploidy_and_focal_events",
                      lambda: cancer_biology.analyze_copy_number_purity_ploidy_and_focal_events(paths['bam']))
            safe_test(results, "cancer_biology.detect_and_annotate_somatic_mutations",
                      lambda: cancer_biology.detect_and_annotate_somatic_mutations(paths['bam'], paths['bam']))
            safe_test(results, "cancer_biology.detect_and_characterize_structural_variations",
                      lambda: cancer_biology.detect_and_characterize_structural_variations(paths['bam']))

        # Create mock expression CSV
        expr_path = str(TEST_DATA_DIR / "expr.csv")
        with open(expr_path, 'w') as f:
            f.write("gene,sample1,sample2\nTP53,10,12\nBRCA1,8,9\n")
        safe_test(results, "cancer_biology.perform_gene_expression_nmf_analysis",
                  lambda: cancer_biology.perform_gene_expression_nmf_analysis(expr_path))

    except ImportError as e:
        results.add("cancer_biology.import", "FAIL", str(e))

    # ========== PHYSIOLOGY ==========
    print("\n--- physiology ---")
    try:
        from biomni.tool import physiology

        if paths['image_seq'] and len([p for p in paths['image_seq'] if p]) >= 2:
            safe_test(results, "physiology.analyze_ciliary_beat_frequency",
                      lambda: physiology.analyze_ciliary_beat_frequency([p for p in paths['image_seq'] if p]))

        # Mock GC data
        gc_path = str(TEST_DATA_DIR / "gc.csv")
        with open(gc_path, 'w') as f:
            f.write("retention_time,area\n1.0,1000\n2.0,2000\n3.0,1500\n")
        safe_test(results, "physiology.analyze_fatty_acid_composition_by_gc",
                  lambda: physiology.analyze_fatty_acid_composition_by_gc(gc_path))

        if paths['image']:
            safe_test(results, "physiology.analyze_protein_colocalization",
                      lambda: physiology.analyze_protein_colocalization(paths['image'], paths['image']))
            safe_test(results, "physiology.quantify_amyloid_beta_plaques",
                      lambda: physiology.quantify_amyloid_beta_plaques(paths['image']))

        # These need NIFTI format - mark as needing specific file format
        results.add("physiology.calculate_brain_adc_map", "FAIL", "Requires NIFTI DWI - create mock NIFTI")
        results.add("physiology.reconstruct_3d_face_from_mri", "FAIL", "Requires NIFTI MRI - create mock NIFTI")

    except ImportError as e:
        results.add("physiology.import", "FAIL", str(e))

    # ========== PATHOLOGY ==========
    print("\n--- pathology ---")
    try:
        from biomni.tool import pathology

        atp = {'well': ['A1', 'A2'], 'luminescence': [1000, 1200]}
        safe_test(results, "pathology.analyze_atp_luminescence_assay",
                  lambda: pathology.analyze_atp_luminescence_assay(atp))

        if paths['image']:
            safe_test(results, "pathology.analyze_aortic_diameter_and_geometry",
                      lambda: pathology.analyze_aortic_diameter_and_geometry(paths['image']))
            safe_test(results, "pathology.analyze_intracellular_calcium_with_rhod2",
                      lambda: pathology.analyze_intracellular_calcium_with_rhod2(paths['image']))
            safe_test(results, "pathology.analyze_thrombus_histology",
                      lambda: pathology.analyze_thrombus_histology(paths['image']))
            safe_test(results, "pathology.quantify_corneal_nerve_fibers",
                      lambda: pathology.quantify_corneal_nerve_fibers(paths['image']))
            safe_test(results, "pathology.segment_and_quantify_cells_in_multiplexed_images",
                      lambda: pathology.segment_and_quantify_cells_in_multiplexed_images(paths['image']))

        results.add("pathology.analyze_bone_microct_morphometry", "FAIL", "Requires DICOM/NIFTI microCT")

    except ImportError as e:
        results.add("pathology.import", "FAIL", str(e))

    # ========== BIOENGINEERING ==========
    print("\n--- bioengineering ---")
    try:
        from biomni.tool import bioengineering

        if paths['image_seq'] and len([p for p in paths['image_seq'] if p]) >= 2:
            safe_test(results, "bioengineering.analyze_calcium_imaging_data",
                      lambda: bioengineering.analyze_calcium_imaging_data([p for p in paths['image_seq'] if p]))
            safe_test(results, "bioengineering.analyze_cell_migration_metrics",
                      lambda: bioengineering.analyze_cell_migration_metrics([p for p in paths['image_seq'] if p]))

        if paths['image']:
            safe_test(results, "bioengineering.analyze_myofiber_morphology",
                      lambda: bioengineering.analyze_myofiber_morphology(paths['image']))

        neural = {'time': list(range(50)), 'spikes': np.random.randint(0, 2, (5, 50)).tolist()}
        safe_test(results, "bioengineering.decode_behavior_from_neural_trajectories",
                  lambda: bioengineering.decode_behavior_from_neural_trajectories(neural))

    except ImportError as e:
        results.add("bioengineering.import", "FAIL", str(e))

    # ========== GENETICS ==========
    print("\n--- genetics ---")
    try:
        from biomni.tool import genetics

        safe_test(results, "genetics.liftover_coordinates",
                  lambda: genetics.liftover_coordinates([("chr1", 1000000)], "hg19", "hg38", data_lake_path=str(TEST_DATA_DIR)))

        gwas = {'snp': ['rs1', 'rs2'], 'pvalue': [1e-8, 1e-6], 'beta': [0.1, 0.05]}
        ld = [[1.0, 0.5], [0.5, 1.0]]
        safe_test(results, "genetics.bayesian_finemapping_with_deep_vi",
                  lambda: genetics.bayesian_finemapping_with_deep_vi(gwas, ld))

        geno = np.random.randint(0, 3, (50, 20)).tolist()
        pheno = np.random.randn(50).tolist()
        safe_test(results, "genetics.fit_genomic_prediction_model",
                  lambda: genetics.fit_genomic_prediction_model(geno, pheno))

        safe_test(results, "genetics.perform_pcr_and_gel_electrophoresis",
                  lambda: genetics.perform_pcr_and_gel_electrophoresis(SAMPLE_DNA, "ATGAAATTCCTGATC", "TCATCCAGGCTCAAA"))

        safe_test(results, "genetics.simulate_demographic_history",
                  lambda: genetics.simulate_demographic_history(sample_size=5, population_size=1000))

    except ImportError as e:
        results.add("genetics.import", "FAIL", str(e))

    # ========== PROTOCOLS ==========
    print("\n--- protocols ---")
    try:
        from biomni.tool import protocols
        safe_test(results, "protocols.get_protocol_details",
                  lambda: protocols.get_protocol_details("12345"))
    except ImportError:
        results.add("protocols.get_protocol_details", "FAIL", "Module not available")

    # ========== LAB AUTOMATION ==========
    print("\n--- lab_automation ---")
    try:
        from biomni.tool import lab_automation
        script = "from pylabrobot.liquid_handling import LiquidHandler\nlh = LiquidHandler()"
        script_path = str(TEST_DATA_DIR / "test_script.py")
        with open(script_path, 'w') as f:
            f.write(script)
        safe_test(results, "lab_automation.test_pylabrobot_script",
                  lambda: lab_automation.test_pylabrobot_script(script_path))
    except ImportError as e:
        results.add("lab_automation.import", "FAIL", str(e))

    # Summary
    results.summary()

    # Save results
    output = "/tmp/biomni_skipped_tools_test.json"
    with open(output, 'w') as f:
        json.dump({"passed": results.passed, "failed": results.failed}, f, indent=2)
    print(f"\nResults saved to {output}")

    return results


if __name__ == "__main__":
    run_tests()
