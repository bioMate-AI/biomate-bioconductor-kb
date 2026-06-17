#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RnBeads — bisulfite_sequencing_vanilla_analysis
// Perform an automatic, comprehensive end-to-end analysis of bisulfite sequencing data (WGBS or RRBS) from BED files.
// Input: bed, sample_annotation.csv
// Container: quay.io/biocontainers/bioconductor-rnbeads:2.28.0--r45hdfd78af_0
// R packages: RnBeads
// Bioconductor: 3.20 | R: 4.4
// Requires: RnBeads
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the data source vector containing the BED directory and sample annotation
//  * 2. [Core Analysis] Run the complete analysis pipeline using the "bs.bed.dir" data type

nextflow.enable.dsl = 2

process BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS {
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
    .bm_deps <- c("RnBeads")
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
        library(RnBeads)
        
        # Define input paths from the working directory
        bed.dir <- "bed"
        sample.annotation <- "sample_annotation.csv"
        
        # Validate that the required user inputs exist
        if (!dir.exists(bed.dir)) {
          stop("Error: 'bed' directory containing methylation BED files not found in the working directory.")
        }
        if (!file.exists(sample.annotation)) {
          stop("Error: 'sample_annotation.csv' metadata sheet not found in the working directory.")
        }
        
        # Read sample annotation to determine the identifier column dynamically
        annot <- read.csv(sample.annotation, stringsAsFactors = FALSE)
        id.col <- colnames(annot)[1]
        if ("Sample_ID" %in% colnames(annot)) {
          id.col <- "Sample_ID"
        } else if ("sampleID" %in% colnames(annot)) {
          id.col <- "sampleID"
        }
        
        # Configure RnBeads options
        rnb.options(
          filtering.sex.chromosomes.removal = TRUE,
          identifiers.column = id.col,
          disk.dump.big.matrices = TRUE,
          differential = FALSE
        )
        
        # Define report directory (must not exist prior to running)
        report.dir <- "rnbeads_reports"
        if (dir.exists(report.dir)) {
          unlink(report.dir, recursive = TRUE)
        }
        
        # 1. Define the data source vector containing the BED directory and sample annotation
        data.source <- c(bed.dir, sample.annotation)
        
        # 2. Run the complete analysis pipeline using the "bs.bed.dir" data type
        analysis.result <- rnb.run.analysis(dir.reports=report.dir, data.source=data.source,
            data.type="bs.bed.dir")
        
        # Post-analysis: Extract and save meaningful results to named output files
        tryCatch({
          logger.start("Exporting results to structured files")
          
          # Extract the processed RnBSet object
          rnb.set <- analysis.result\$rnb.set
          
          # Save the RnBSet object as an RDS file
          saveRDS(rnb.set, file = "rnbeads_set.rds")
          
          # Export phenotypic metadata
          metadata <- pheno(rnb.set)
          write.csv(metadata, file = "sample_metadata_output.csv", row.names = TRUE)
          
          # Export methylation beta values
          beta_values <- meth(rnb.set)
          write.csv(beta_values, file = "methylation_beta_values.csv", row.names = TRUE)
          
          # Export coverage information if available
          if (hasCovg(rnb.set)) {
            coverage_vals <- covg(rnb.set)
            write.csv(coverage_vals, file = "coverage_values.csv", row.names = TRUE)
          }
          
          # Generate a PDF plot of the beta distribution
          pdf("methylation_beta_distribution.pdf", width = 8, height = 6)
          hist(beta_values[, 1], col = "steelblue", breaks = 50, 
               main = "Distribution of Methylation Beta Values",
               xlab = "Beta Value", ylab = "Frequency")
          dev.off()
          
          logger.completed()
        }, error = function(e) {
          message("An error occurred during post-analysis export: ", e\$message)
        })

    writeLines(c(
        '"BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS":',
        paste0('    RnBeads: ', as.character(packageVersion('RnBeads')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bisulfite_sequencing_vanilla_analysis.csv versions.yml
    """
}

workflow BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bed, sample_annotation.csv ] ]

    main:
    BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS.out.tables
    plots    = BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS.out.plots
    objects  = BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS.out.objects
    versions = BIOC_RNBEADS_BISULFITE_SEQUENCING_VANILLA_ANALYSIS.out.versions
}
