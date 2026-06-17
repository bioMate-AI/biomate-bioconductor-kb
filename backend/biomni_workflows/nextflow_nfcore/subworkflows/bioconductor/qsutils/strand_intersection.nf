#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QSutils — strand_intersection
// Select high-confidence haplotypes present in both forward and reverse sequencing strands above a minimum frequency threshold to perform error correction.
// Input: ToyData_FWReads.fna, ToyData_RVReads.fna
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// R packages: Biostrings, QSutils
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, QSutils
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load forward and reverse sequences using ReadAmplSeqs
//  * 2. [Core Analysis] Intersect strand haplotypes and update frequencies using IntersectStrandHpls

nextflow.enable.dsl = 2

process BIOC_QSUTILS_STRAND_INTERSECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "QSutils")
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
    library(QSutils)
    library(Biostrings)
    
    # Define input file paths in the working directory
    filepath_fw <- "ToyData_FWReads.fna"
    filepath_rv <- "ToyData_RVReads.fna"
    
    # Check if input files exist
    if (!file.exists(filepath_fw)) {
      stop(paste("Required input file missing:", filepath_fw))
    }
    if (!file.exists(filepath_rv)) {
      stop(paste("Required input file missing:", filepath_rv))
    }
    
    # 1. Load forward and reverse sequences using ReadAmplSeqs
    lstFW <- ReadAmplSeqs(filepath_fw, type="DNA")
    cat("Forward - Reads: ", sum(lstFW\$nr), ", Haplotypes: ", length(lstFW\$nr), "\n", sep="")
    
    lstRV <- ReadAmplSeqs(filepath_rv, type="DNA")
    cat("Reverse - Reads: ", sum(lstRV\$nr), ", Haplotypes: ", length(lstRV\$nr), "\n", sep="")
    
    # 2. Intersect strand haplotypes and update frequencies using IntersectStrandHpls
    lstI <- IntersectStrandHpls(lstFW\$nr, lstFW\$hseqs, lstRV\$nr, lstRV\$hseqs)
    
    # Print summary statistics of the intersection
    cat("FW and Rv total reads:", sum(lstFW\$nr) + sum(lstRV\$nr), "\n")
    cat("FW and Rv reads above thr:", sum(lstI\$pFW) + sum(lstI\$pRV), "\n")
    cat("FW haplotypes above thr:", sum(lstFW\$nr / sum(lstFW\$nr) > 0.001), "\n")
    cat("RV haplotypes above thr:", sum(lstRV\$nr / sum(lstRV\$nr) > 0.001), "\n")
    cat("Reads in FW unique haplotypes:", sum(lstI\$pFW[lstI\$pRV == 0]), "\n")
    cat("Reads in RV unique haplotypes:", sum(lstI\$pRV[lstI\$pFW == 0]), "\n")
    cat("Reads in common:", sum(lstI\$nr), "\n")
    cat("Haplotypes in common:", length(lstI\$nr), "\n")
    
    # Save the meaningful results to output files
    # Save the complete list object as RDS
    saveRDS(lstI, file = "intersect_results.rds")
    
    # Create and save a summary table of the metrics
    summary_metrics <- data.frame(
      Metric = c(
        "FW_Total_Reads", 
        "RV_Total_Reads", 
        "FW_Total_Haplotypes", 
        "RV_Total_Haplotypes",
        "FW_Haplotypes_Above_0.1pct",
        "RV_Haplotypes_Above_0.1pct",
        "Common_Haplotypes",
        "Common_Reads"
      ),
      Value = c(
        sum(lstFW\$nr),
        sum(lstRV\$nr),
        length(lstFW\$nr),
        length(lstRV\$nr),
        sum(lstFW\$nr / sum(lstFW\$nr) > 0.001),
        sum(lstRV\$nr / sum(lstRV\$nr) > 0.001),
        length(lstI\$nr),
        sum(lstI\$nr)
      )
    )
    write.csv(summary_metrics, file = "intersection_summary_metrics.csv", row.names = FALSE)
    
    # Export the intersected haplotypes to a FASTA file if sequences are present in the output
    # IntersectStrandHpls returns a list containing the intersected sequences, typically in 'hseqs' or 'seqs'
    seqs_field <- intersect(names(lstI), c("hseqs", "seqs"))
    if (length(seqs_field) > 0) {
      intersected_seqs <- lstI[[seqs_field[1]]]
      # Assign names incorporating the updated frequencies
      names(intersected_seqs) <- paste0("Hpl_", seq_along(lstI\$nr), "|", lstI\$nr)
      writeXStringSet(intersected_seqs, filepath = "intersected_haplotypes.fna")
      
      # Also save a CSV of the intersected haplotypes and their counts
      intersected_df <- data.frame(
        Haplotype_ID = names(intersected_seqs),
        Sequence = as.character(intersected_seqs),
        Count = lstI\$nr,
        pFW = lstI\$pFW[lstI\$pFW > 0 & lstI\$pRV > 0], # corresponding non-zero proportions
        pRV = lstI\$pRV[lstI\$pFW > 0 & lstI\$pRV > 0]
      )
      write.csv(intersected_df, file = "intersected_haplotypes_table.csv", row.names = FALSE)
    }
    
    cat("Workflow completed successfully. Outputs saved to 'intersect_results.rds', 'intersection_summary_metrics.csv', and 'intersected_haplotypes.fna'.\n")

    writeLines(c(
        '"BIOC_QSUTILS_STRAND_INTERSECTION":',
        paste0('    QSutils: ', as.character(packageVersion('QSutils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_strand_intersection.csv versions.yml
    """
}

workflow BIOC_QSUTILS_STRAND_INTERSECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyData_FWReads.fna, ToyData_RVReads.fna ] ]

    main:
    BIOC_QSUTILS_STRAND_INTERSECTION(ch_input)

    emit:
    tables   = BIOC_QSUTILS_STRAND_INTERSECTION.out.tables
    plots    = BIOC_QSUTILS_STRAND_INTERSECTION.out.plots
    objects  = BIOC_QSUTILS_STRAND_INTERSECTION.out.objects
    versions = BIOC_QSUTILS_STRAND_INTERSECTION.out.versions
}
