#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sangerseqr — sanger_sequencing_analysis
// Analyze Sanger sequencing chromatograms to make basecalls, phase alleles against a reference, and align the resulting sequences.
// Input: heterozygous.ab1, homozygous.scf
// Container: quay.io/biocontainers/bioconductor-sangerseqr:1.46.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sangerseqr:1.46.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "sangerseqr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required Bioconductor libraries
    suppressPackageStartupMessages({
      library(sangerseqR)
      library(Biostrings)
    })
    
    # Define expected input files in the working directory
    ab1_file <- "heterozygous.ab1"
    scf_file <- "homozygous.scf"
    
    # Validate existence of input files
    if (!file.exists(ab1_file)) {
      stop(paste("Error: Required input file missing in working directory:", ab1_file))
    }
    if (!file.exists(scf_file)) {
      stop(paste("Error: Required input file missing in working directory:", scf_file))
    }
    
    # ==========================================
    # 1. Load Chromatogram Data
    # ==========================================
    message("Loading chromatogram data...")
    hetab1 <- read.abif(ab1_file)
    homoscf <- read.scf(scf_file)
    
    # Create sangerseq class objects
    homosangerseq <- sangerseq(homoscf)
    hetsangerseq <- readsangerseq(ab1_file)
    
    # Save raw sangerseq objects for downstream inspection
    saveRDS(homosangerseq, "homosangerseq.rds")
    saveRDS(hetsangerseq, "hetsangerseq.rds")
    
    # ==========================================
    # 2. Extract and Manipulate Sequences
    # ==========================================
    message("Extracting and manipulating sequences...")
    Seq1 <- primarySeq(homosangerseq)
    
    # Perform reverse complementation
    rev_seq <- reverseComplement(Seq1)
    writeXStringSet(DNAStringSet(rev_seq), "homo_reverse_complement.fasta")
    
    # Extract primary sequence as a character string
    prim_seq_str <- primarySeq(homosangerseq, string=TRUE)
    writeLines(prim_seq_str, "homo_primary_seq.txt")
    
    # ==========================================
    # 3. Plot Chromatograms
    # ==========================================
    # Saving to PDF to prevent graphics device dimension errors
    message("Plotting initial chromatogram to PDF...")
    pdf("chromatogram_hetsangerseq.pdf", width=11, height=8.5)
    chromatogram(hetsangerseq, width=80, height=3, trim5=50, trim3=100, 
                 showcalls='both')
    dev.off()
    
    # ==========================================
    # 4. Make Primary and Secondary Basecalls
    # ==========================================
    message("Making basecalls with ratio cutoff...")
    hetcalls <- makeBaseCalls(hetsangerseq, ratio=0.33)
    saveRDS(hetcalls, "hetcalls.rds")
    
    message("Plotting basecalled chromatogram to PDF...")
    pdf("chromatogram_hetcalls.pdf", width=11, height=8.5)
    chromatogram(hetcalls, width=80, height=3, trim5=50, trim3=100, 
                 showcalls='both')
    dev.off()
    
    # ==========================================
    # 5. Phase Alleles Against a Reference
    # ==========================================
    message("Phasing alleles against reference sequence...")
    ref <- subseq(primarySeq(homosangerseq, string=TRUE), start=30, width=500)
    hetseqalleles <- setAllelePhase(hetcalls, ref, trim5=50, trim3=300)
    saveRDS(hetseqalleles, "hetseqalleles.rds")
    
    # ==========================================
    # 6. Align and Compare Phased Alleles
    # ==========================================
    message("Aligning phased alleles...")
    pa <- pairwiseAlignment(primarySeq(hetseqalleles)[1:400], 
                            secondarySeq(hetseqalleles)[1:400], 
                            type="global-local")
    saveRDS(pa, "pairwise_alignment.rds")
    
    # Capture the exact writePairwiseAlignments output to a text file
    message("Writing pairwise alignment report...")
    sink("pairwise_alignment.txt")
    writePairwiseAlignments(pa)
    sink()
    
    message("Sanger sequencing analysis pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS":
        sangerseqr: \$(Rscript -e 'cat(as.character(packageVersion("sangerseqr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sanger_sequencing_analysis.csv versions.yml
    """
}

workflow BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ heterozygous.ab1, homozygous.scf ] ]

    main:
    BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS.out.tables
    plots    = BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS.out.plots
    objects  = BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS.out.objects
    versions = BIOC_SANGERSEQR_SANGER_SEQUENCING_ANALYSIS.out.versions
}
