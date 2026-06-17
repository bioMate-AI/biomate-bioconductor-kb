#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiCcompare — standard_hic_comparison
// Jointly normalize and detect differential chromatin interactions between two Hi-C datasets for a single chromosome.
// Input: HMEC.chr22, NHEK.chr22
// Container: quay.io/biocontainers/bioconductor-hiccompare:1.32.0--r45hdfd78af_0
// R packages: InteractionSet, HiCcompare
// Bioconductor: 3.20 | R: 4.4
// Requires: HiCcompare, InteractionSet, knitr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the sparse chromatin interaction matrices from user
//  * 2. [Input & Preparation] Create a hic.table object using create.hic.table
//  * 3. [Input & Preparation] Jointly normalize the datasets using hic_loess
//  * 4. [Input & Preparation] Evaluate filtering parameters using filter_params
//  * 5. [Input & Preparation] Detect differential interactions using hic_compare
//  * 6. [Input & Preparation] Convert the results to an InteractionSet object using

nextflow.enable.dsl = 2

process BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("InteractionSet", "HiCcompare")
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
    library(HiCcompare)
    library(InteractionSet)
    
    # Helper function to robustly read the input files from the working directory
    read_hic_file <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file '", filepath, "' not found in the working directory.", sep = ""))
      }
      
      # Attempt to read with header
      df <- read.table(filepath, header = TRUE, stringsAsFactors = FALSE)
      
      # If columns are not named correctly, try reading without header and assign names
      required_cols <- c("region1", "region2", "IF")
      if (!all(required_cols %in% colnames(df))) {
        df <- read.table(filepath, header = FALSE, stringsAsFactors = FALSE)
        if (ncol(df) >= 3) {
          colnames(df)[1:3] <- required_cols
          df <- df[, 1:3]
        } else {
          stop(paste("File '", filepath, "' does not have at least 3 columns (region1, region2, IF).", sep = ""))
        }
      }
      return(df)
    }
    
    # --- Load the sparse chromatin interaction matrices from user ---
    message("Loading input datasets...")
    HMEC.chr22 <- read_hic_file("HMEC.chr22")
    NHEK.chr22 <- read_hic_file("NHEK.chr22")
    
    print(head(HMEC.chr22))
    
    # --- Create a hic.table object using create.hic.table ---
    message("Creating hic.table object...")
    chr22.table <- create.hic.table(HMEC.chr22, NHEK.chr22, chr = 'chr22')
    print(head(chr22.table))
    
    # --- Jointly normalize the datasets using hic_loess ---
    message("Performing joint normalization using hic_loess...")
    pdf("hic_loess_plot.pdf", width = 7, height = 5)
    hic.table <- hic_loess(chr22.table, Plot = TRUE, Plot.smooth = FALSE)
    dev.off()
    
    # Print normalized table head
    if (requireNamespace("knitr", quietly = TRUE)) {
      print(knitr::kable(head(hic.table)))
    } else {
      print(head(hic.table))
    }
    
    # --- Evaluate filtering parameters using filter_params ---
    message("Evaluating filtering parameters...")
    pdf("filter_params_plot.pdf", width = 7, height = 5)
    tryCatch({
      filter_params(hic.table)
    }, error = function(e) {
      message("Warning: filter_params failed with error: ", e\$message)
    })
    dev.off()
    
    # --- Detect differential interactions using hic_compare ---
    message("Detecting differential chromatin interactions using hic_compare...")
    pdf("hic_compare_plot.pdf", width = 7, height = 5)
    hic.table <- hic_compare(hic.table, A.min = 15, adjust.dist = TRUE, p.method = 'fdr', Plot = TRUE)
    dev.off()
    
    # Print comparison table head
    if (requireNamespace("knitr", quietly = TRUE)) {
      print(knitr::kable(head(hic.table)))
    } else {
      print(head(hic.table))
    }
    
    # Save the final comparison table to a CSV file
    write.csv(hic.table, "hic_compare_results.csv", row.names = FALSE)
    message("Saved comparison results to 'hic_compare_results.csv'")
    
    # --- Convert the results to an InteractionSet object using ---
    message("Converting results to an InteractionSet object...")
    IntSet <- make_InteractionSet(hic.table)
    
    # Save the InteractionSet object to an RDS file
    saveRDS(IntSet, "InteractionSet_results.rds")
    message("Saved InteractionSet object to 'InteractionSet_results.rds'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON":',
        paste0('    HiCcompare: ', as.character(packageVersion('HiCcompare')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_hic_comparison.csv versions.yml
    """
}

workflow BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HMEC.chr22, NHEK.chr22 ] ]

    main:
    BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON(ch_input)

    emit:
    tables   = BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON.out.tables
    plots    = BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON.out.plots
    objects  = BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON.out.objects
    versions = BIOC_HICCOMPARE_STANDARD_HIC_COMPARISON.out.versions
}
