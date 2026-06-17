#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicInstability — reference_based_gia
// Refine genomic instability analysis by using a subset of cells identified as normal (or an external normal dataset) as a reference null model.
// Input: tpm_matrix, nullmat
// Container: quay.io/biocontainers/bioconductor-genomicinstability:1.16.0--r45hdfd78af_0
// R packages: genomicInstability
// Bioconductor: 3.20 | R: 4.4
// Requires: genomicInstability
// Visualizations: density plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run inferCNV() providing the normal reference matrix to the nullmat argument
//  * 2. [Core Analysis] Calculate GIS and estimate likelihood simultaneously using genomicInstabilityScore() with likelihood=TRUE
//  * 3. [Visualization & Output] Visualize the GIS density, fitted models, and null model using giDensityPlot()
//  * 4. [Visualization & Output] Plot the loci-block enrichment heatmap using plot()

nextflow.enable.dsl = 2

process BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA {
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
    .bm_deps <- c("genomicInstability")
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
        library(genomicInstability)
        
        # Helper function to read matrix inputs (supporting RDS, CSV, TSV, TXT)
        read_matrix <- function(base_name) {
          possible_files <- c(
            base_name,
            paste0(base_name, ".rds"),
            paste0(base_name, ".csv"),
            paste0(base_name, ".tsv"),
            paste0(base_name, ".txt")
          )
          
          found_file <- NULL
          for (f in possible_files) {
            if (file.exists(f)) {
              found_file <- f
              break
            }
          }
          
          if (is.null(found_file)) {
            stop(paste("Error: Input file for", base_name, "not found in the working directory."))
          }
          
          message("Reading: ", found_file)
          if (grepl("\\\\.rds\$", found_file, ignore.case = TRUE)) {
            return(readRDS(found_file))
          } else if (grepl("\\\\.csv\$", found_file, ignore.case = TRUE)) {
            return(as.matrix(read.csv(found_file, row.names = 1, check.names = FALSE)))
          } else if (grepl("\\\\.(tsv|txt)\$", found_file, ignore.case = TRUE)) {
            return(as.matrix(read.delim(found_file, row.names = 1, check.names = FALSE)))
          } else {
            # Fallback default read
            return(as.matrix(read.table(found_file, header = TRUE, row.names = 1, check.names = FALSE)))
          }
        }
        
        # 1. Read User Inputs
        target_matrix <- read_matrix("tpm_matrix")
        reference_matrix <- read_matrix("nullmat")
        
        # Ensure column names are unique across target and reference
        colnames(target_matrix) <- paste0("Target_", colnames(target_matrix))
        colnames(reference_matrix) <- paste0("Ref_", colnames(reference_matrix))
        
        # 2. Run inferCNV using the normal reference matrix
        message("Running inferCNV...")
        cnv_norm <- inferCNV(target_matrix, nullmat=reference_matrix)
        
        # 3. Calculate GIS and estimate likelihood simultaneously
        message("Calculating Genomic Instability Score and Likelihood...")
        cnv_norm <- genomicInstabilityScore(cnv_norm, likelihood=TRUE)
        
        # 4. Visualize the GIS density, fitted models, and null model
        message("Generating GIS density plot...")
        pdf("gi_density_plot.pdf", width = 7, height = 6)
        giDensityPlot(cnv_norm, ylim=c(0, 1.1))
        dev.off()
        
        # 5. Plot the loci-block enrichment heatmap
        message("Generating enrichment heatmap...")
        plot(cnv_norm, output="heatmap.png", resolution=120, gamma=2)
        
        # 6. Save meaningful results
        message("Saving results...")
        saveRDS(cnv_norm, "cnv_norm_results.rds")
        
        # Export GIS and Likelihood table
        results_df <- data.frame(
          Cell_ID = names(cnv_norm\$gis),
          GIS = cnv_norm\$gis,
          GI_Likelihood = cnv_norm\$gi_likelihood,
          stringsAsFactors = FALSE
        )
        write.csv(results_df, "genomic_instability_scores.csv", row.names = FALSE)
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA":',
        paste0('    genomicInstability: ', as.character(packageVersion('genomicInstability')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_based_gia.csv versions.yml
    """
}

workflow BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tpm_matrix, nullmat ] ]

    main:
    BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA(ch_input)

    emit:
    tables   = BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA.out.tables
    plots    = BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA.out.plots
    objects  = BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA.out.objects
    versions = BIOC_GENOMICINSTABILITY_REFERENCE_BASED_GIA.out.versions
}
