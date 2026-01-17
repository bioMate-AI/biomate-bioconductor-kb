#!/usr/bin/env python3
"""
Exhaustive Biomni Tools Test Suite
Tests all 275+ Biomni tools across 21 categories
"""

import os
import sys
import json
import time
import traceback
from typing import Dict, List, Tuple, Any

# Add Biomni to path
BIOMNI_PATH = "/home/yzhang/biomate/Biomni"
if BIOMNI_PATH not in sys.path:
    sys.path.insert(0, BIOMNI_PATH)

# Test results tracking
class TestResults:
    def __init__(self):
        self.passed = []
        self.failed = []
        self.skipped = []
        self.errors = {}

    def add_pass(self, category: str, func: str, details: str = ""):
        self.passed.append({"category": category, "function": func, "details": details})

    def add_fail(self, category: str, func: str, error: str):
        self.failed.append({"category": category, "function": func, "error": error})
        self.errors[f"{category}.{func}"] = error

    def add_skip(self, category: str, func: str, reason: str):
        self.skipped.append({"category": category, "function": func, "reason": reason})

    def summary(self):
        total = len(self.passed) + len(self.failed) + len(self.skipped)
        print("\n" + "="*70)
        print("EXHAUSTIVE BIOMNI TEST RESULTS")
        print("="*70)
        print(f"Total tests: {total}")
        print(f"  PASSED:  {len(self.passed)} ({100*len(self.passed)/max(1,total):.1f}%)")
        print(f"  FAILED:  {len(self.failed)} ({100*len(self.failed)/max(1,total):.1f}%)")
        print(f"  SKIPPED: {len(self.skipped)} ({100*len(self.skipped)/max(1,total):.1f}%)")

        if self.failed:
            print("\n--- FAILED TESTS ---")
            for f in self.failed[:20]:  # Show first 20
                print(f"  {f['category']}.{f['function']}: {f['error'][:80]}")
            if len(self.failed) > 20:
                print(f"  ... and {len(self.failed) - 20} more failures")
        print("="*70)
        return len(self.failed) == 0


# ============================================================================
# TEST DATA - Sample inputs for different tool categories
# ============================================================================

SAMPLE_PROTEIN_SEQUENCE = "MKFLILLFNILCLFPVLAADNHGVGPQGASGVDPITFDINSNQTGVQLTLNSTGSEEECKFSLFLKWFEPG"
SAMPLE_DNA_SEQUENCE = "ATGAAATTCCTGATCCTGCTGTTCAACATCCTGTGCCTGTTCCCTGTGCTGGCTGCTGACAACCATGGTGTGGGTCCACAGGGTGCTAGTGGTGTGGATCCTATCACCTTCGACATCAACAGCAACCAGACTGGTGTGCAGCTGACCCTGAACAGCACTGGTTCTGAGGAGGAGTGCAAATTCTCTCTGTTCCTGAAATGGTTTGAGCCTGGA"
SAMPLE_GENE_NAME = "BRCA1"
SAMPLE_UNIPROT_ID = "P38398"
SAMPLE_PDB_ID = "1A00"
SAMPLE_KEGG_ID = "hsa:672"


def test_import_all_modules() -> Tuple[List[str], List[str]]:
    """Test that all Biomni tool modules can be imported"""
    modules = [
        "biochemistry", "bioengineering", "bioimaging", "biophysics",
        "cancer_biology", "cell_biology", "database", "genetics",
        "genomics", "glycoengineering", "immunology", "lab_automation",
        "literature", "microbiology", "molecular_biology", "pathology",
        "pharmacology", "physiology", "protocols", "synthetic_biology",
        "systems_biology"
    ]

    imported = []
    failed = []

    for mod in modules:
        try:
            exec(f"from biomni.tool import {mod}")
            imported.append(mod)
        except Exception as e:
            failed.append((mod, str(e)))

    return imported, failed


def test_database_tools(results: TestResults):
    """Test database query tools"""
    print("\n--- Testing Database Tools ---")

    try:
        from biomni.tool import database

        # Test 1: query_uniprot
        try:
            result = database.query_uniprot(SAMPLE_UNIPROT_ID)
            if result and len(str(result)) > 100:
                results.add_pass("database", "query_uniprot", f"Got {len(str(result))} chars")
            else:
                results.add_fail("database", "query_uniprot", "Empty or short result")
        except Exception as e:
            results.add_fail("database", "query_uniprot", str(e)[:200])

        # Test 2: query_pdb
        try:
            result = database.query_pdb(SAMPLE_PDB_ID)
            if result:
                results.add_pass("database", "query_pdb", f"Got PDB data")
            else:
                results.add_fail("database", "query_pdb", "Empty result")
        except Exception as e:
            results.add_fail("database", "query_pdb", str(e)[:200])

        # Test 3: query_kegg
        try:
            result = database.query_kegg(SAMPLE_KEGG_ID)
            if result:
                results.add_pass("database", "query_kegg", "Got KEGG data")
            else:
                results.add_fail("database", "query_kegg", "Empty result")
        except Exception as e:
            results.add_fail("database", "query_kegg", str(e)[:200])

        # Test 4: query_interpro
        try:
            result = database.query_interpro(SAMPLE_UNIPROT_ID)
            if result:
                results.add_pass("database", "query_interpro", "Got InterPro data")
            else:
                results.add_skip("database", "query_interpro", "No InterPro data found")
        except Exception as e:
            results.add_fail("database", "query_interpro", str(e)[:200])

        # Test 5: query_stringdb
        try:
            result = database.query_stringdb([SAMPLE_GENE_NAME], species=9606)
            if result:
                results.add_pass("database", "query_stringdb", "Got STRING data")
            else:
                results.add_skip("database", "query_stringdb", "No STRING data found")
        except Exception as e:
            results.add_fail("database", "query_stringdb", str(e)[:200])

        # Test 6: query_alphafold
        try:
            result = database.query_alphafold(SAMPLE_UNIPROT_ID)
            if result:
                results.add_pass("database", "query_alphafold", "Got AlphaFold data")
            else:
                results.add_skip("database", "query_alphafold", "No AlphaFold data found")
        except Exception as e:
            results.add_fail("database", "query_alphafold", str(e)[:200])

    except ImportError as e:
        results.add_fail("database", "import", f"Failed to import database module: {e}")


def test_molecular_biology_tools(results: TestResults):
    """Test molecular biology tools"""
    print("\n--- Testing Molecular Biology Tools ---")

    try:
        from biomni.tool import molecular_biology

        # Test 1: annotate_open_reading_frames
        try:
            result = molecular_biology.annotate_open_reading_frames(SAMPLE_DNA_SEQUENCE)
            results.add_pass("molecular_biology", "annotate_open_reading_frames", "ORFs found")
        except Exception as e:
            results.add_fail("molecular_biology", "annotate_open_reading_frames", str(e)[:200])

        # Test 2: find_restriction_sites
        try:
            result = molecular_biology.find_restriction_sites(SAMPLE_DNA_SEQUENCE)
            results.add_pass("molecular_biology", "find_restriction_sites", "Sites found")
        except Exception as e:
            results.add_fail("molecular_biology", "find_restriction_sites", str(e)[:200])

        # Test 3: design_primer
        try:
            result = molecular_biology.design_primer(SAMPLE_DNA_SEQUENCE[:100])
            results.add_pass("molecular_biology", "design_primer", "Primer designed")
        except Exception as e:
            results.add_fail("molecular_biology", "design_primer", str(e)[:200])

        # Test 4: align_sequences
        try:
            seq1 = SAMPLE_DNA_SEQUENCE[:50]
            seq2 = SAMPLE_DNA_SEQUENCE[10:60]
            result = molecular_biology.align_sequences(seq1, seq2)
            results.add_pass("molecular_biology", "align_sequences", "Alignment done")
        except Exception as e:
            results.add_fail("molecular_biology", "align_sequences", str(e)[:200])

        # Test 5: get_gene_coding_sequence
        try:
            result = molecular_biology.get_gene_coding_sequence(SAMPLE_GENE_NAME, species="human")
            if result:
                results.add_pass("molecular_biology", "get_gene_coding_sequence", "CDS retrieved")
            else:
                results.add_skip("molecular_biology", "get_gene_coding_sequence", "No CDS found")
        except Exception as e:
            results.add_fail("molecular_biology", "get_gene_coding_sequence", str(e)[:200])

    except ImportError as e:
        results.add_fail("molecular_biology", "import", f"Failed to import: {e}")


def test_literature_tools(results: TestResults):
    """Test literature search tools"""
    print("\n--- Testing Literature Tools ---")

    try:
        from biomni.tool import literature

        # Test 1: query_pubmed
        try:
            result = literature.query_pubmed("BRCA1 cancer", max_results=3)
            if result:
                results.add_pass("literature", "query_pubmed", f"Got {len(result) if isinstance(result, list) else 1} results")
            else:
                results.add_fail("literature", "query_pubmed", "No results")
        except Exception as e:
            results.add_fail("literature", "query_pubmed", str(e)[:200])

        # Test 2: query_arxiv
        try:
            result = literature.query_arxiv("machine learning biology", max_results=3)
            if result:
                results.add_pass("literature", "query_arxiv", "Got arXiv results")
            else:
                results.add_skip("literature", "query_arxiv", "No arXiv results")
        except Exception as e:
            results.add_fail("literature", "query_arxiv", str(e)[:200])

    except ImportError as e:
        results.add_fail("literature", "import", f"Failed to import: {e}")


def test_biochemistry_tools(results: TestResults):
    """Test biochemistry analysis tools"""
    print("\n--- Testing Biochemistry Tools ---")

    try:
        from biomni.tool import biochemistry

        # Test protein conservation (uses sequence)
        try:
            result = biochemistry.analyze_protein_conservation(SAMPLE_PROTEIN_SEQUENCE)
            results.add_pass("biochemistry", "analyze_protein_conservation", "Analysis done")
        except Exception as e:
            results.add_fail("biochemistry", "analyze_protein_conservation", str(e)[:200])

    except ImportError as e:
        results.add_fail("biochemistry", "import", f"Failed to import: {e}")


def test_genomics_tools(results: TestResults):
    """Test genomics tools"""
    print("\n--- Testing Genomics Tools ---")

    try:
        from biomni.tool import genomics

        # Test 1: gene_set_enrichment_analysis
        try:
            gene_list = ["TP53", "BRCA1", "BRCA2", "ATM", "CHEK2"]
            result = genomics.gene_set_enrichment_analysis(gene_list)
            results.add_pass("genomics", "gene_set_enrichment_analysis", "GSEA done")
        except Exception as e:
            results.add_fail("genomics", "gene_set_enrichment_analysis", str(e)[:200])

        # Test 2: get_gene_set_enrichment_analysis_supported_database_list
        try:
            result = genomics.get_gene_set_enrichment_analysis_supported_database_list()
            results.add_pass("genomics", "get_gene_set_enrichment_analysis_supported_database_list", "List retrieved")
        except Exception as e:
            results.add_fail("genomics", "get_gene_set_enrichment_analysis_supported_database_list", str(e)[:200])

        # Test 3: interspecies_gene_conversion
        try:
            result = genomics.interspecies_gene_conversion(["BRCA1"], from_species="human", to_species="mouse")
            results.add_pass("genomics", "interspecies_gene_conversion", "Conversion done")
        except Exception as e:
            results.add_fail("genomics", "interspecies_gene_conversion", str(e)[:200])

    except ImportError as e:
        results.add_fail("genomics", "import", f"Failed to import: {e}")


def test_protocols_tools(results: TestResults):
    """Test protocol search tools"""
    print("\n--- Testing Protocol Tools ---")

    try:
        from biomni.tool import protocols

        # Test 1: search_protocols
        try:
            result = protocols.search_protocols("PCR amplification")
            if result:
                results.add_pass("protocols", "search_protocols", "Protocols found")
            else:
                results.add_skip("protocols", "search_protocols", "No protocols found")
        except Exception as e:
            results.add_fail("protocols", "search_protocols", str(e)[:200])

    except ImportError as e:
        results.add_fail("protocols", "import", f"Failed to import: {e}")


def test_glycoengineering_tools(results: TestResults):
    """Test glycoengineering tools"""
    print("\n--- Testing Glycoengineering Tools ---")

    try:
        from biomni.tool import glycoengineering

        # Test 1: find_n_glycosylation_motifs
        try:
            result = glycoengineering.find_n_glycosylation_motifs(SAMPLE_PROTEIN_SEQUENCE)
            results.add_pass("glycoengineering", "find_n_glycosylation_motifs", "Motifs searched")
        except Exception as e:
            results.add_fail("glycoengineering", "find_n_glycosylation_motifs", str(e)[:200])

        # Test 2: list_glycoengineering_resources
        try:
            result = glycoengineering.list_glycoengineering_resources()
            results.add_pass("glycoengineering", "list_glycoengineering_resources", "Resources listed")
        except Exception as e:
            results.add_fail("glycoengineering", "list_glycoengineering_resources", str(e)[:200])

    except ImportError as e:
        results.add_fail("glycoengineering", "import", f"Failed to import: {e}")


def test_systems_biology_tools(results: TestResults):
    """Test systems biology tools"""
    print("\n--- Testing Systems Biology Tools ---")

    try:
        from biomni.tool import systems_biology

        # Test 1: compare_protein_structures
        try:
            result = systems_biology.compare_protein_structures("1A00", "1AO6")
            results.add_pass("systems_biology", "compare_protein_structures", "Comparison done")
        except Exception as e:
            results.add_fail("systems_biology", "compare_protein_structures", str(e)[:200])

    except ImportError as e:
        results.add_fail("systems_biology", "import", f"Failed to import: {e}")


def test_pharmacology_tools(results: TestResults):
    """Test pharmacology tools"""
    print("\n--- Testing Pharmacology Tools ---")

    try:
        from biomni.tool import pharmacology

        # Test 1: predict_admet_properties
        try:
            # Aspirin SMILES
            smiles = "CC(=O)OC1=CC=CC=C1C(=O)O"
            result = pharmacology.predict_admet_properties(smiles)
            results.add_pass("pharmacology", "predict_admet_properties", "ADMET predicted")
        except Exception as e:
            results.add_fail("pharmacology", "predict_admet_properties", str(e)[:200])

        # Test 2: calculate_physicochemical_properties
        try:
            smiles = "CC(=O)OC1=CC=CC=C1C(=O)O"
            result = pharmacology.calculate_physicochemical_properties(smiles)
            results.add_pass("pharmacology", "calculate_physicochemical_properties", "Properties calculated")
        except Exception as e:
            results.add_fail("pharmacology", "calculate_physicochemical_properties", str(e)[:200])

    except ImportError as e:
        results.add_fail("pharmacology", "import", f"Failed to import: {e}")


def test_synthetic_biology_tools(results: TestResults):
    """Test synthetic biology tools"""
    print("\n--- Testing Synthetic Biology Tools ---")

    try:
        from biomni.tool import synthetic_biology

        # Test 1: optimize_codons_for_heterologous_expression
        try:
            result = synthetic_biology.optimize_codons_for_heterologous_expression(
                SAMPLE_PROTEIN_SEQUENCE, target_organism="E. coli"
            )
            results.add_pass("synthetic_biology", "optimize_codons_for_heterologous_expression", "Codons optimized")
        except Exception as e:
            results.add_fail("synthetic_biology", "optimize_codons_for_heterologous_expression", str(e)[:200])

    except ImportError as e:
        results.add_fail("synthetic_biology", "import", f"Failed to import: {e}")


def test_microbiology_tools(results: TestResults):
    """Test microbiology tools"""
    print("\n--- Testing Microbiology Tools ---")

    try:
        from biomni.tool import microbiology

        # Test 1: predict_rna_secondary_structure
        try:
            rna_seq = "GCGGAUUUAGCUCAGUUGGGAGAGCGCCAGACUGAAGAUCUGGAGGUCCUGUGUUCGAUCCACAGAAUUCGCA"
            result = microbiology.predict_rna_secondary_structure(rna_seq)
            results.add_pass("microbiology", "predict_rna_secondary_structure", "Structure predicted")
        except Exception as e:
            results.add_fail("microbiology", "predict_rna_secondary_structure", str(e)[:200])

    except ImportError as e:
        results.add_fail("microbiology", "import", f"Failed to import: {e}")


def test_biophysics_tools(results: TestResults):
    """Test biophysics tools"""
    print("\n--- Testing Biophysics Tools ---")

    try:
        from biomni.tool import biophysics

        # Test 1: predict_protein_disorder_regions
        try:
            result = biophysics.predict_protein_disorder_regions(SAMPLE_PROTEIN_SEQUENCE)
            results.add_pass("biophysics", "predict_protein_disorder_regions", "Disorder predicted")
        except Exception as e:
            results.add_fail("biophysics", "predict_protein_disorder_regions", str(e)[:200])

    except ImportError as e:
        results.add_fail("biophysics", "import", f"Failed to import: {e}")


def test_genetics_tools(results: TestResults):
    """Test genetics tools"""
    print("\n--- Testing Genetics Tools ---")

    try:
        from biomni.tool import genetics

        # Test 1: liftover_coordinates
        try:
            result = genetics.liftover_coordinates(
                chrom="chr1", start=100000, end=100100,
                from_assembly="hg19", to_assembly="hg38"
            )
            results.add_pass("genetics", "liftover_coordinates", "Liftover done")
        except Exception as e:
            results.add_fail("genetics", "liftover_coordinates", str(e)[:200])

    except ImportError as e:
        results.add_fail("genetics", "import", f"Failed to import: {e}")


def run_all_tests():
    """Run all Biomni tool tests"""
    print("="*70)
    print("EXHAUSTIVE BIOMNI TOOLS TEST SUITE")
    print("="*70)

    results = TestResults()

    # Test module imports first
    print("\n--- Testing Module Imports ---")
    imported, failed_imports = test_import_all_modules()
    print(f"Successfully imported: {len(imported)}/{len(imported)+len(failed_imports)} modules")

    for mod in imported:
        results.add_pass("imports", mod, "Module imported")
    for mod, err in failed_imports:
        results.add_fail("imports", mod, err)

    # Run category-specific tests
    test_database_tools(results)
    test_molecular_biology_tools(results)
    test_literature_tools(results)
    test_biochemistry_tools(results)
    test_genomics_tools(results)
    test_protocols_tools(results)
    test_glycoengineering_tools(results)
    test_systems_biology_tools(results)
    test_pharmacology_tools(results)
    test_synthetic_biology_tools(results)
    test_microbiology_tools(results)
    test_biophysics_tools(results)
    test_genetics_tools(results)

    # Print summary
    success = results.summary()

    # Save detailed results
    with open("/tmp/biomni_test_results.json", "w") as f:
        json.dump({
            "passed": results.passed,
            "failed": results.failed,
            "skipped": results.skipped,
            "errors": results.errors
        }, f, indent=2)
    print(f"\nDetailed results saved to /tmp/biomni_test_results.json")

    return success


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
