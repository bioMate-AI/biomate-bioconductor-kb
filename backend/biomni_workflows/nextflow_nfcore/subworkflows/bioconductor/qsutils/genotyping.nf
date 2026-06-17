#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QSutils — genotyping
// Classify an unknown target haplotype into a genotype based on reference standards and within-genotype variability.
// Input: Unknown-Genotype.fna, GenotypeStandards_A-H.fas
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// R packages: Biostrings, QSutils, ape
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, QSutils, ape
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load target sequence and reference sequences using ReadAmplSeqs
//  * 2. [Core Analysis] Compute distance matrix using DNA.dist
//  * 3. [Core Analysis] Extract distances between references and from target to references
//  * 4. [Core Analysis] Classify the target sequence using DBrule

nextflow.enable.dsl = 2

process BIOC_QSUTILS_GENOTYPING {
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
    .bm_deps <- c("Biostrings", "QSutils", "ape")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(ape)
    
    # Verify input files exist
    if (!file.exists("Unknown-Genotype.fna")) {
      stop("Error: Input file 'Unknown-Genotype.fna' not found in the working directory.")
    }
    if (!file.exists("GenotypeStandards_A-H.fas")) {
      stop("Error: Input file 'GenotypeStandards_A-H.fas' not found in the working directory.")
    }
    
    # 1. Load target sequence
    filepath <- "Unknown-Genotype.fna"
    lst2Geno <- ReadAmplSeqs(filepath, type="DNA")
    
    # Robust handling of potential list element name discrepancy (hseq vs hseqs)
    hseq <- lst2Geno\$hseq[1]
    if (is.null(hseq)) {
      hseq <- lst2Geno\$hseqs[1]
    }
    
    # 2. Load reference sequences
    filepath <- "GenotypeStandards_A-H.fas"
    lstRefs <- ReadAmplSeqs(filepath, type="DNA")
    
    # Robust handling of potential list element name discrepancy (hseq vs hseqs)
    RefSeqs <- lstRefs\$hseq
    if (is.null(RefSeqs)) {
      RefSeqs <- lstRefs\$hseqs
    }
    
    # 3. Compute distance matrix using DNA.dist
    dm <- as.matrix(DNA.dist(c(hseq, RefSeqs), model="K80"))
    
    # 4. Extract distances between references and from target to references
    dgrp <- dm[-1, -1]
    d <- dm[1, -1]
    grp <- factor(substr(rownames(dgrp), 1, 1))
    hr <- as.integer(grp)
    
    # 5. Classify the target sequence using DBrule
    dsc <- DBrule(dgrp, hr, d, levels(grp))
    print(dsc)
    
    # 6. Save meaningful results to output files
    # Save the full classification object
    saveRDS(dsc, "genotyping_results.rds")
    
    # Save the classification metrics as a CSV table
    phi2_names <- names(dsc\$Phi2)
    clean_names <- gsub("^Phi2\\\\.", "", phi2_names)
    results_df <- data.frame(
      Genotype = clean_names,
      Phi2_Value = as.numeric(dsc\$Phi2),
      Predicted_Genotype = dsc\$Type,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "genotyping_results.csv", row.names = FALSE)
    
    # Generate and save a PDF plot of the Phi2 values
    pdf("phi2_distances.pdf", width = 7, height = 5)
    barplot(
      dsc\$Phi2, 
      main = paste("Genotyping Phi2 Values (Predicted Genotype:", dsc\$Type, ")"),
      names.arg = clean_names,
      col = "skyblue", 
      ylab = "Phi2 Value",
      xlab = "Genotype Reference Standards",
      las = 1
    )
    dev.off()
    
    cat("\nPipeline completed successfully.\n")
    cat("Outputs generated:\n")
    cat("- genotyping_results.rds (RDS object of classification results)\n")
    cat("- genotyping_results.csv (CSV table of Phi2 values and predicted genotype)\n")
    cat("- phi2_distances.pdf (Barplot of Phi2 values per genotype)\n")

    writeLines(c(
        '"BIOC_QSUTILS_GENOTYPING":',
        paste0('    QSutils: ', as.character(packageVersion('QSutils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genotyping.csv versions.yml
    """
}

workflow BIOC_QSUTILS_GENOTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Unknown-Genotype.fna, GenotypeStandards_A-H.fas ] ]

    main:
    BIOC_QSUTILS_GENOTYPING(ch_input)

    emit:
    tables   = BIOC_QSUTILS_GENOTYPING.out.tables
    plots    = BIOC_QSUTILS_GENOTYPING.out.plots
    objects  = BIOC_QSUTILS_GENOTYPING.out.objects
    versions = BIOC_QSUTILS_GENOTYPING.out.versions
}
