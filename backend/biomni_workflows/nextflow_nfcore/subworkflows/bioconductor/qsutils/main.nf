#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsutils — collapse_and_correct_gaps_ns
// Load raw amplicon reads, collapse them to unique haplotypes with frequencies, correct gaps and indeterminate bases (Ns) against a reference sequence, and recoll
// Input: Toy.GapsAndNs.fna
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// R packages: ape, Biostrings, ggplot2, psych, QSutils
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("ape", "Biostrings", "ggplot2", "psych", "QSutils")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(Biostrings)
    library(QSutils)
    
    # Define input file path (must be in the working directory)
    filepath <- "Toy.GapsAndNs.fna"
    
    # Check if the input file exists
    if (!file.exists(filepath)) {
      stop(paste("Error: Input file", filepath, "not found in the working directory."))
    }
    
    # 1. Read raw sequences using readDNAStringSet
    reads <- readDNAStringSet(filepath)
    
    # 2. Collapse reads to unique haplotypes and frequencies using Collapse
    lstCollapsed <- Collapse(reads)
    
    # 3. Correct gaps and Ns against a reference sequence (dominant haplotype) using CorrectGapsAndNs
    lstCorrected <- CorrectGapsAndNs(lstCollapsed\$hseqs[2:length(lstCollapsed\$hseqs)],
                                      lstCollapsed\$hseqs[[1]])
    
    # Add again the most abundant haplotype
    lstCorrected <- c(lstCollapsed\$hseqs[1], lstCorrected)
    
    # 4. Recollapse the corrected sequences to update frequencies using Recollapse
    lstRecollapsed <- Recollapse(lstCorrected, lstCollapsed\$nr)
    
    # Save meaningful results to output files
    # Save RDS objects for downstream R analysis
    saveRDS(lstCollapsed, "collapsed_data.rds")
    saveRDS(lstCorrected, "corrected_sequences.rds")
    saveRDS(lstRecollapsed, "recollapsed_data.rds")
    
    # Export collapsed haplotypes to CSV
    collapsed_df <- data.frame(
      Haplotype = as.character(lstCollapsed\$hseqs),
      Count = lstCollapsed\$nr,
      stringsAsFactors = FALSE
    )
    write.csv(collapsed_df, "collapsed_haplotypes.csv", row.names = FALSE)
    
    # Export recollapsed (corrected) haplotypes to CSV
    recollapsed_df <- data.frame(
      Haplotype = as.character(lstRecollapsed\$seqs),
      Count = lstRecollapsed\$nr,
      stringsAsFactors = FALSE
    )
    write.csv(recollapsed_df, "recollapsed_haplotypes.csv", row.names = FALSE)
    
    # Export final corrected haplotypes to a FASTA file
    writeXStringSet(lstRecollapsed\$seqs, "recollapsed_haplotypes.fasta")
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS":
        qsutils: \$(Rscript -e 'cat(as.character(packageVersion("qsutils")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_collapse_and_correct_gaps_ns.csv versions.yml
    """
}

workflow BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Toy.GapsAndNs.fna ] ]

    main:
    BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS(ch_input)

    emit:
    tables   = BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS.out.tables
    plots    = BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS.out.plots
    objects  = BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS.out.objects
    versions = BIOC_QSUTILS_COLLAPSE_AND_CORRECT_GAPS_NS.out.versions
}
