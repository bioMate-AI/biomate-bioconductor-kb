#!/usr/bin/env python3
"""
Biomni Workflow Execution Test
==============================
Date: 2026-01-20
Purpose: Test representative Galaxy workflows by executing their underlying Biomni tools

This test validates that workflows can be executed end-to-end by:
1. Creating proper mock data matching workflow inputs
2. Calling the underlying Biomni tool functions
3. Verifying outputs match expected structure

Selected workflows (matching validated tools at 95% pass rate):
1. genomics/create_harmony_embeddings_scRNA - scRNA batch integration
2. pharmacology/calculate_physicochemical_properties - Drug property calculation
3. pathology/analyze_atp_luminescence_assay - ATP assay analysis
4. genetics/liftover_coordinates - Genomic coordinate conversion
5. physiology/quantify_amyloid_beta_plaques - Plaque quantification
6. genomics/find_enriched_motifs_with_homer - Motif discovery
7. microbiology/annotate_bacterial_genome - Genome annotation
"""

import sys
import os
import json
import tempfile
import traceback
from pathlib import Path
from datetime import datetime
import numpy as np

# Add biomni to path
sys.path.insert(0, '/opt/biomni/src')

# Test data directory
TEST_DATA_DIR = Path(tempfile.mkdtemp(prefix='biomni_workflow_test_'))
print(f"Test data directory: {TEST_DATA_DIR}")


def setup_test_data():
    """Create all necessary test data files for workflow testing."""

    # === 1. scRNA AnnData for Harmony workflow ===
    scrna_dir = TEST_DATA_DIR / "scrna"
    scrna_dir.mkdir(exist_ok=True)

    try:
        import scanpy as sc
        import pandas as pd

        np.random.seed(42)
        n_cells, n_genes = 100, 200
        X = np.random.poisson(lam=3, size=(n_cells, n_genes)).astype(np.float32)

        adata = sc.AnnData(X)
        adata.obs_names = [f'cell_{i}' for i in range(n_cells)]
        adata.var_names = [f'gene_{i}' for i in range(n_genes)]
        adata.obs['batch'] = np.random.choice(['batch1', 'batch2'], n_cells)
        adata.obs['celltype'] = np.random.choice(['T_cell', 'B_cell', 'Monocyte'], n_cells)
        adata.obs['leiden'] = pd.Categorical(np.random.choice(['0', '1', '2'], n_cells))

        # Required preprocessing for Harmony
        sc.pp.normalize_total(adata)
        sc.pp.log1p(adata)
        sc.pp.highly_variable_genes(adata, n_top_genes=50)
        sc.pp.pca(adata, n_comps=30)

        adata_path = scrna_dir / "test_adata.h5ad"
        adata.write(str(adata_path))
        print(f"  Created: {adata_path}")
    except Exception as e:
        print(f"  Warning: Could not create scRNA test data: {e}")

    # === 2. ATP luminescence assay data ===
    assay_dir = TEST_DATA_DIR / "assay"
    assay_dir.mkdir(exist_ok=True)

    # Data file - luminescence readings
    data_file = assay_dir / "atp_data.csv"
    with open(data_file, 'w') as f:
        f.write("sample,luminescence\n")
        f.write("control,1000\n")
        f.write("treatment_1,2500\n")
        f.write("treatment_2,3200\n")
        f.write("treatment_3,1800\n")
    print(f"  Created: {data_file}")

    # Standard curve file
    std_curve_file = assay_dir / "standard_curve.csv"
    with open(std_curve_file, 'w') as f:
        f.write("concentration,luminescence\n")
        f.write("0,100\n")
        f.write("10,500\n")
        f.write("50,2000\n")
        f.write("100,4000\n")
        f.write("500,18000\n")
    print(f"  Created: {std_curve_file}")

    # Normalization data
    norm_file = assay_dir / "normalization.csv"
    with open(norm_file, 'w') as f:
        f.write("sample,cell_count\n")
        f.write("control,10000\n")
        f.write("treatment_1,10500\n")
        f.write("treatment_2,9800\n")
        f.write("treatment_3,10200\n")
    print(f"  Created: {norm_file}")

    # === 3. Image for plaque quantification ===
    image_dir = TEST_DATA_DIR / "images"
    image_dir.mkdir(exist_ok=True)

    try:
        from PIL import Image
        # Create synthetic image with bright spots (simulating plaques)
        img_array = np.zeros((512, 512, 3), dtype=np.uint8)
        img_array[:, :] = [50, 50, 50]  # Gray background

        # Add some bright spots to simulate plaques
        for _ in range(20):
            x, y = np.random.randint(50, 462, 2)
            r = np.random.randint(5, 15)
            for dx in range(-r, r+1):
                for dy in range(-r, r+1):
                    if dx*dx + dy*dy <= r*r:
                        img_array[y+dy, x+dx] = [200, 180, 150]

        img = Image.fromarray(img_array)
        img_path = image_dir / "brain_section.png"
        img.save(str(img_path))
        print(f"  Created: {img_path}")
    except Exception as e:
        print(f"  Warning: Could not create image test data: {e}")

    # === 4. BED file for HOMER motif analysis ===
    bed_dir = TEST_DATA_DIR / "genomics"
    bed_dir.mkdir(exist_ok=True)

    bed_file = bed_dir / "peaks.bed"
    with open(bed_file, 'w') as f:
        f.write("chr1\t1000\t2000\tpeak1\t100\t+\n")
        f.write("chr1\t5000\t6000\tpeak2\t150\t+\n")
        f.write("chr2\t10000\t11000\tpeak3\t200\t-\n")
        f.write("chr2\t15000\t16000\tpeak4\t120\t+\n")
        f.write("chr3\t20000\t21000\tpeak5\t180\t-\n")
    print(f"  Created: {bed_file}")

    # === 5. FASTA file for genome annotation ===
    fasta_file = bed_dir / "bacterial_contigs.fasta"
    # Generate random DNA sequence
    bases = ['A', 'T', 'G', 'C']
    seq = ''.join(np.random.choice(bases, 2000))
    with open(fasta_file, 'w') as f:
        f.write(">contig_1\n")
        f.write(seq[:1000] + "\n")
        f.write(">contig_2\n")
        f.write(seq[1000:] + "\n")
    print(f"  Created: {fasta_file}")

    return {
        'scrna_dir': scrna_dir,
        'scrna_adata': scrna_dir / "test_adata.h5ad",
        'atp_data': data_file,
        'atp_std_curve': std_curve_file,
        'atp_norm': norm_file,
        'brain_image': image_dir / "brain_section.png",
        'peaks_bed': bed_file,
        'bacterial_fasta': fasta_file,
    }


# ============================================================
# WORKFLOW TEST FUNCTIONS
# ============================================================

def test_workflow_harmony_scrna(test_files):
    """
    Workflow: genomics/create_harmony_embeddings_scRNA
    Tool: biomni.tool.genomics.create_harmony_embeddings_scRNA
    """
    from biomni.tool.genomics import create_harmony_embeddings_scRNA

    result = create_harmony_embeddings_scRNA(
        adata_filename="test_adata.h5ad",
        data_dir=str(test_files['scrna_dir']),
        batch_column="batch"
    )

    # Verify output
    assert result is not None, "Result should not be None"
    assert 'embedding_file' in str(result) or os.path.exists(result), \
        f"Should return embedding file path, got: {result}"

    return True


def test_workflow_physicochemical_properties(test_files):
    """
    Workflow: pharmacology/calculate_physicochemical_properties
    Tool: biomni.tool.pharmacology.calculate_physicochemical_properties
    """
    from biomni.tool.pharmacology import calculate_physicochemical_properties

    # Aspirin SMILES
    result = calculate_physicochemical_properties(
        smiles="CC(=O)OC1=CC=CC=C1C(=O)O"
    )

    # Verify output contains expected properties
    assert result is not None, "Result should not be None"
    result_str = str(result)

    # Should contain molecular weight, LogP, etc.
    assert any(prop in result_str.lower() for prop in ['molecular', 'weight', 'logp', 'mw']), \
        f"Should contain physicochemical properties, got: {result_str[:200]}"

    return True


def test_workflow_atp_luminescence(test_files):
    """
    Workflow: pathology/analyze_atp_luminescence_assay
    Tool: biomni.tool.pathology.analyze_atp_luminescence_assay
    """
    from biomni.tool.pathology import analyze_atp_luminescence_assay

    result = analyze_atp_luminescence_assay(
        data_file=str(test_files['atp_data']),
        standard_curve_file=str(test_files['atp_std_curve']),
        normalization_data=str(test_files['atp_norm'])
    )

    # Verify output
    assert result is not None, "Result should not be None"
    result_str = str(result)

    # Should contain ATP concentration values
    assert any(term in result_str.lower() for term in ['atp', 'concentration', 'nmol', 'sample']), \
        f"Should contain ATP analysis results, got: {result_str[:200]}"

    return True


def test_workflow_liftover_coordinates(test_files):
    """
    Workflow: genetics/liftover_coordinates
    Tool: biomni.tool.genetics.liftover_coordinates
    """
    from biomni.tool.genetics import liftover_coordinates

    # Test hg19 to hg38 liftover
    result = liftover_coordinates(
        chromosome="chr1",
        start=1000000,
        end=1001000,
        source_assembly="hg19",
        target_assembly="hg38"
    )

    # Verify output
    assert result is not None, "Result should not be None"
    result_str = str(result)

    # Should contain coordinates
    assert any(term in result_str.lower() for term in ['chr', 'coordinate', 'start', 'end', 'position']), \
        f"Should contain converted coordinates, got: {result_str[:200]}"

    return True


def test_workflow_quantify_plaques(test_files):
    """
    Workflow: physiology/quantify_amyloid_beta_plaques
    Tool: biomni.tool.physiology.quantify_amyloid_beta_plaques
    """
    from biomni.tool.physiology import quantify_amyloid_beta_plaques

    result = quantify_amyloid_beta_plaques(
        image_path=str(test_files['brain_image']),
        threshold=100,
        min_area=10,
        max_area=1000
    )

    # Verify output
    assert result is not None, "Result should not be None"
    result_str = str(result)

    # Should contain plaque count/area
    assert any(term in result_str.lower() for term in ['plaque', 'count', 'area', 'detected', 'total']), \
        f"Should contain plaque quantification results, got: {result_str[:200]}"

    return True


def test_workflow_homer_motifs(test_files):
    """
    Workflow: genomics/find_enriched_motifs_with_homer
    Tool: biomni.tool.genomics.find_enriched_motifs_with_homer
    """
    from biomni.tool.genomics import find_enriched_motifs_with_homer

    result = find_enriched_motifs_with_homer(
        bed_file_path=str(test_files['peaks_bed']),
        genome="hg38",
        motif_size="8,10,12"
    )

    # Verify output
    assert result is not None, "Result should not be None"
    result_str = str(result)

    # Should contain motif information
    assert any(term in result_str.lower() for term in ['motif', 'enriched', 'homer', 'sequence', 'output']), \
        f"Should contain motif analysis results, got: {result_str[:200]}"

    return True


def test_workflow_annotate_genome(test_files):
    """
    Workflow: microbiology/annotate_bacterial_genome
    Tool: biomni.tool.microbiology.annotate_bacterial_genome
    """
    from biomni.tool.microbiology import annotate_bacterial_genome

    result = annotate_bacterial_genome(
        fasta_file=str(test_files['bacterial_fasta']),
        output_format="gff3"
    )

    # Verify output
    assert result is not None, "Result should not be None"
    result_str = str(result)

    # Should contain annotation information
    assert any(term in result_str.lower() for term in ['gene', 'cds', 'annotation', 'gff', 'contig']), \
        f"Should contain genome annotation results, got: {result_str[:200]}"

    return True


def test_workflow_scvi_embeddings(test_files):
    """
    Workflow: genomics/create_scvi_embeddings_scRNA
    Tool: biomni.tool.genomics.create_scvi_embeddings_scRNA
    """
    from biomni.tool.genomics import create_scvi_embeddings_scRNA

    result = create_scvi_embeddings_scRNA(
        adata_filename="test_adata.h5ad",
        data_dir=str(test_files['scrna_dir']),
        batch_column="batch",
        label_column="celltype"
    )

    # Verify output
    assert result is not None, "Result should not be None"
    assert 'embedding' in str(result).lower() or os.path.exists(str(result)), \
        f"Should return embedding file path, got: {result}"

    return True


# ============================================================
# MAIN TEST RUNNER
# ============================================================

def run_all_workflow_tests():
    """Run all workflow tests and collect results."""

    print("=" * 60)
    print("BIOMNI WORKFLOW EXECUTION TEST")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    print()

    # Setup test data
    print("Setting up test data...")
    test_files = setup_test_data()
    print()

    # Define all workflow tests
    workflow_tests = [
        ("genomics/create_harmony_embeddings_scRNA", test_workflow_harmony_scrna),
        ("genomics/create_scvi_embeddings_scRNA", test_workflow_scvi_embeddings),
        ("pharmacology/calculate_physicochemical_properties", test_workflow_physicochemical_properties),
        ("pathology/analyze_atp_luminescence_assay", test_workflow_atp_luminescence),
        ("genetics/liftover_coordinates", test_workflow_liftover_coordinates),
        ("physiology/quantify_amyloid_beta_plaques", test_workflow_quantify_plaques),
        ("genomics/find_enriched_motifs_with_homer", test_workflow_homer_motifs),
        ("microbiology/annotate_bacterial_genome", test_workflow_annotate_genome),
    ]

    results = []
    passed = 0
    failed = 0

    print("Running workflow tests...")
    print("-" * 60)

    for workflow_name, test_func in workflow_tests:
        try:
            print(f"\nTesting: {workflow_name}")
            test_func(test_files)
            print(f"  [PASS] {workflow_name}")
            results.append((workflow_name, "PASS", None))
            passed += 1
        except Exception as e:
            error_msg = str(e)
            print(f"  [FAIL] {workflow_name}")
            print(f"         Error: {error_msg[:100]}")
            results.append((workflow_name, "FAIL", error_msg))
            failed += 1

    # Print summary
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total workflows tested: {len(workflow_tests)}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Pass rate: {100 * passed / len(workflow_tests):.1f}%")
    print()

    # Print detailed results
    print("Detailed Results:")
    print("-" * 60)
    for workflow, status, error in results:
        status_icon = "✓" if status == "PASS" else "✗"
        print(f"  {status_icon} {workflow}")
        if error:
            print(f"      Error: {error[:80]}...")

    print()
    print(f"Test data directory: {TEST_DATA_DIR}")

    return results, passed, failed


if __name__ == "__main__":
    results, passed, failed = run_all_workflow_tests()
    sys.exit(0 if failed == 0 else 1)
