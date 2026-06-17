#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: les — les_detection_and_region_identification
// Identify regulated genomic regions (Loci of Enhanced Significance) from probe positions and p-values, estimate confidence intervals, and export the results.
// Input: pos, pval
// Container: quay.io/biocontainers/bioconductor-les:1.60.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: les
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create Les object
//  * 2. [Core Analysis] Estimate local significance (Lambda) using a sliding window
//  * 3. [Core Analysis] Estimate the significance threshold
//  * 4. [Core Analysis] Detect regulated regions
//  * 5. [Core Analysis] Calculate confidence intervals for a subset of probes
//  * 6. [Visualization & Output] Export regions and statistics to BED, GFF, and WIG files

nextflow.enable.dsl = 2

process BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("les")
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
    library(les)
    
    # ---------------------------------------------------------
    # 1. Read User Input Files
    # ---------------------------------------------------------
    find_and_read <- function(base_name, is_integer = FALSE) {
      extensions <- c("", ".txt", ".csv")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          # Try reading with scan
          res <- tryCatch({
            scan(file_path, quiet = TRUE)
          }, error = function(e) NULL)
          
          if (!is.null(res) && length(res) > 0) {
            if (is_integer) return(as.integer(res))
            return(as.numeric(res))
          }
          
          # Try reading with read.csv
          res_csv <- tryCatch({
            df <- read.csv(file_path, header = FALSE)
            df[[1]]
          }, error = function(e) NULL)
          
          if (!is.null(res_csv) && length(res_csv) > 0) {
            if (is_integer) return(as.integer(res_csv))
            return(as.numeric(res_csv))
          }
        }
      }
      stop(paste("Error: Could not find or read input file for", base_name))
    }
    
    pos <- find_and_read("pos", is_integer = TRUE)
    pval <- find_and_read("pval", is_integer = FALSE)
    
    # ---------------------------------------------------------
    # 2. Execute Documented Workflow
    # ---------------------------------------------------------
    res <- Les(pos, pval)
    res2 <- estimate(res, win=200, weighting=rectangWeight)
    res2 <- threshold(res2, grenander=TRUE, verbose=TRUE)
    res2 <- regions(res2, verbose=TRUE)
    res2["regions"]
    
    # Define subset robustly: if the hardcoded range contains no probes,
    # fall back to a window around the most significant probe to prevent ci() failure.
    subset <- pos >= 5232400 & pos <= 5233100
    if (sum(subset) == 0) {
      center <- which.min(pval)
      subset <- seq_along(pos) %in% (max(1, center - 25):min(length(pos), center + 25))
    }
    
    res2 <- ci(res2, subset, nBoot=50, alpha=0.1)
    
    bedFile <- paste(tempfile(), "bed", sep=".")
    gffFile <- paste(tempfile(), "gff", sep=".")
    wigFile <- paste(tempfile(), "wig", sep=".")
    
    export(res2, bedFile)
    export(res2, gffFile, format="gff")
    export(res2, wigFile, format="wig")
    
    # ---------------------------------------------------------
    # 3. Save Outputs to Working Directory
    # ---------------------------------------------------------
    # Save regions table
    regions_df <- res2["regions"]
    write.csv(regions_df, "detected_regions.csv", row.names = FALSE)
    
    # Save RDS object
    saveRDS(res2, "les_results.rds")
    
    # Save PDF plot
    pdf("les_results_plot.pdf", width = 10, height = 7)
    tryCatch({
      plot(res2, error = "ci", region = TRUE)
    }, error = function(e) {
      plot(res2, region = TRUE)
    })
    dev.off()
    
    # Copy exported files to standard names in the working directory
    if (file.exists(bedFile)) file.copy(bedFile, "regions.bed", overwrite = TRUE)
    if (file.exists(gffFile)) file.copy(gffFile, "regions.gff", overwrite = TRUE)
    if (file.exists(wigFile)) file.copy(wigFile, "regions.wig", overwrite = TRUE)

    writeLines(c(
        '"BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION":',
        paste0('    les: ', as.character(packageVersion('les')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_les_detection_and_region_identification.csv versions.yml
    """
}

workflow BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pos, pval ] ]

    main:
    BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION(ch_input)

    emit:
    tables   = BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION.out.tables
    plots    = BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION.out.plots
    objects  = BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION.out.objects
    versions = BIOC_LES_LES_DETECTION_AND_REGION_IDENTIFICATION.out.versions
}
