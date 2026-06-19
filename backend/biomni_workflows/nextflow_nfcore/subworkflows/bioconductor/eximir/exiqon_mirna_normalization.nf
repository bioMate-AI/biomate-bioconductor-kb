#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eximir — exiqon_mirna_normalization
// Read, annotate, and normalize Exiqon dual-channel raw TXT files using spike-in or quantile normalization.
// Input: TXT files, GAL file, samplesinfo.txt
// Container: quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0
// R packages: ExiMiR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: box plot

nextflow.enable.dsl = 2

process BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0"

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
    .bm_deps <- c("ExiMiR")
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
    
    # Check for required input files in the working directory
    if (!file.exists("samplesinfo.txt")) {
      stop("Error: 'samplesinfo.txt' not found in the working directory.")
    }
    
    gal_files <- list.files(pattern = "\\\\.gal\$", ignore.case = TRUE)
    if (length(gal_files) == 0) {
      stop("Error: No GAL annotation file (.gal) found in the working directory.")
    }
    
    txt_files <- list.files(pattern = "\\\\.txt\$", ignore.case = TRUE)
    txt_files <- txt_files[txt_files != "samplesinfo.txt"]
    if (length(txt_files) == 0) {
      stop("Error: No raw ImaGene TXT files found in the working directory.")
    }
    
    # Load required package
    library(ExiMiR)
    
    # --- Create the GAL annotation environment using make.gal.env ---
    # Reading from the current working directory ('.')
    make.gal.env(galname='galenv', gal.path='.')
    
    # --- Read raw TXT files into an AffyBatch object using ReadExi ---
    # Reading from the current working directory ('.')
    ebatch <- ReadExi(galname='galenv', txtfile.path='.')
    
    # --- Normalize and summarize the data using NormiR to produce ---
    eset.spike <- NormiR(ebatch, bg.correct=FALSE,
                                 normalize.method='spikein',
                                 summary.method='medianpolish')
    
    # --- Write named output files for the results ---
    # Save the complete ExpressionSet object
    saveRDS(eset.spike, file = "eset_spike.rds")
    
    # Save the normalized expression matrix as a CSV table
    write.csv(exprs(eset.spike), file = "normalized_mirna_expression.csv", row.names = TRUE)
    
    # Generate a diagnostic boxplot of the normalized intensities
    pdf("normalized_expression_boxplot.pdf", width = 8, height = 6)
    boxplot(exprs(eset.spike), 
            main = "Normalized miRNA Expression (Spike-in)", 
            las = 2, 
            col = "skyblue", 
            ylab = "Log2 Intensity")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'eset_spike.rds', 'normalized_mirna_expression.csv', and 'normalized_expression_boxplot.pdf'.\n")

    writeLines(c(
        '"BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION":',
        paste0('        eximir: ', as.character(packageVersion("eximir")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exiqon_mirna_normalization.csv versions.yml
    """
}

workflow BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TXT files, GAL file, samplesinfo.txt ] ]

    main:
    BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION.out.tables
    plots    = BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION.out.plots
    objects  = BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION.out.objects
    versions = BIOC_EXIMIR_EXIQON_MIRNA_NORMALIZATION.out.versions
}
