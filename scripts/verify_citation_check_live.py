#!/usr/bin/env python3
"""Live check of citation_check against NCBI E-utilities and Crossref (free, no key).
Usage: PYTHONPATH=backend/lib python3 scripts/verify_citation_check_live.py
10 known-real citations must be 'verified'; 10 deliberately fake ones must be rejected."""
import sys
from galaxy.ai.agents import citation_check as cc

REAL = [
    {"pmid": "25516281", "title": "Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2"},
    {"pmid": "19451168", "title": "Fast and accurate short read alignment with Burrows-Wheeler transform"},
    {"pmid": "20644199", "title": "The Genome Analysis Toolkit: a MapReduce framework for analyzing next-generation DNA sequencing data"},
    {"pmid": "22388286", "title": "Fast gapped-read alignment with Bowtie 2"},
    {"pmid": "19910308", "title": "edgeR: a Bioconductor package for differential expression analysis of digital gene expression data"},
    {"pmid": "2231712", "title": "Basic local alignment search tool"},
    {"doi": "10.1038/nature14539", "title": "Deep learning"},
    {"doi": "10.1038/s41586-021-03819-2", "title": "Highly accurate protein structure prediction with AlphaFold"},
    {"doi": "10.1038/171737a0", "title": "Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid"},
    {"pmid": "34265844", "doi": "10.1038/s41586-021-03819-2", "title": "Highly accurate protein structure prediction with AlphaFold"},
]
FAKE = [
    {"pmid": "99999991", "title": "A study that does not exist"},                       # absent PMID
    {"pmid": "88888888", "title": "Another invented trial of a kinase inhibitor"},     # absent PMID
    {"pmid": "2551628100", "title": "Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2"},  # malformed
    {"doi": "10.1038/nature99999999", "title": "Deep learning"},                        # absent DOI
    {"doi": "10.1186/s13059-014-0550-9999", "title": "Moderated estimation of fold change"},  # wrong digits
    {"doi": "10.1234/fake.2020.001", "title": "Invented paper"},                        # absent DOI
    {"doi": "10.1038/nature14539", "title": "Transformer attention improves protein folding"},      # real DOI, wrong title
    {"doi": "10.1038/171737a0", "title": "CRISPR screens identify regulators of T cell exhaustion"}, # real DOI, wrong title
    {"pmid": "25516281", "title": "Efficacy of drug X in rheumatoid arthritis: a randomised trial"}, # real PMID, wrong title
    {"pmid": "2231712", "doi": "10.1038/nature99999998", "title": "Basic local alignment search tool"},  # real PMID + fake DOI
]


def main() -> int:
    bad = 0
    print("%-5s %-9s %-30s %-20s %-6s %s" % ("set", "expect", "id", "status", "sim", "registry/note"))
    for name, rows, ok in (("real", REAL, {"verified"}), ("fake", FAKE, {"not_found", "title_mismatch"})):
        for c in rows:
            r = cc.verify_citation(c, offline=False)
            ident = ("PMID " + c["pmid"]) if c.get("pmid") else ("DOI " + c["doi"])
            if c.get("pmid") and c.get("doi"):
                ident += "+DOI"
            good = r["status"] in ok
            bad += not good
            print("%-5s %-9s %-30s %-20s %-6s %s%s" % (
                name, "pass" if good else "FAIL", ident[:30], r["status"], r.get("similarity"),
                (r.get("registry_title") or r.get("note") or "")[:60], "" if good else "   <-- UNEXPECTED"))
    print("\n%d/%d as expected" % (len(REAL) + len(FAKE) - bad, len(REAL) + len(FAKE)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
