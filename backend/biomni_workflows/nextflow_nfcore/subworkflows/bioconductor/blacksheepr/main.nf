#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: blacksheepr — deva_standard_workflow
// Perform differential extreme value analysis (deva) using a SummarizedExperiment object and extract tables and heatmaps of significant outliers.
// Input: phosphotable.csv, comptable.csv
// Container: quay.io/biocontainers/bioconductor-blacksheepr:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, SummarizedExperiment, blacksheepr
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and read in count and annotation data
//  * 2. [Visualization & Output] Create a SummarizedExperiment object, ensuring counts are formatted as a matrix and annotations as a DataFrame
//  * 3. [Visualization & Output] Run the high-level deva function to perform outlier analysis and generate heatmaps
//  * 4. [Visualization & Output] Extract and explore significant tables and heatmaps using the deva_results utility function

nextflow.enable.dsl = 2

process BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW {
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
    .bm_deps <- c("blacksheepr", "SummarizedExperiment")
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
        
        # 1. Load the package and read in count and annotation data
        library(blacksheepr)
        suppressPackageStartupMessages(library(SummarizedExperiment))
        
        # Read user input files from the working directory
        comptable <- read.csv("comptable.csv", row.names = 1, check.names = FALSE)
        # Ensure annotation columns are character strings as required by blacksheepr
        comptable[] <- lapply(comptable, as.character)
        
        phosphotable <- read.csv("phosphotable.csv", row.names = 1, check.names = FALSE)
        
        # 2. Create a SummarizedExperiment object
        blacksheep_SE <- SummarizedExperiment(
            assays=list(counts=as.matrix(phosphotable)), 
            colData=DataFrame(comptable))
        
        # 3. Run the high-level deva function to perform outlier analysis
        deva_out <- deva(se = blacksheep_SE, 
            analyze_negative_outliers = FALSE, aggregate_features = TRUE, 
            feature_delineator = "-", fraction_samples_cutoff = 0.3, 
            fdrcutoffvalue = 0.1)
        
        # Explore the output structure
        names(deva_out)
        deva_results(deva_out)
        
        # Save the complete deva output object
        saveRDS(deva_out, "deva_out.rds")
        
        # 4. Extract and explore significant tables and heatmaps using the deva_results utility function
        # Use the first column name of the annotation table as a generic ID to avoid hardcoding
        analysis_id <- colnames(comptable)[1]
        
        tryCatch({
            subanalysis_table <- deva_results(deva_out, ID = analysis_id, type = "table")
            print(head(subanalysis_table))
            write.csv(subanalysis_table, paste0("subanalysis_", analysis_id, ".csv"), row.names = FALSE)
        }, error = function(e) {
            message("Extraction of ", analysis_id, " table skipped or failed: ", e\$message)
        })
        
        tryCatch({
            subanalysis_HM <- deva_results(deva_out, ID = analysis_id, type = "heatmap")
            if (!is.null(subanalysis_HM)) {
                pdf(paste0("subanalysis_", analysis_id, "_heatmap.pdf"))
                if (requireNamespace("ComplexHeatmap", quietly = TRUE)) {
                    ComplexHeatmap::draw(subanalysis_HM)
                } else {
                    print(subanalysis_HM)
                }
                dev.off()
            }
        }, error = function(e) {
            message("Extraction of ", analysis_id, " heatmap skipped or failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW":',
        paste0('    blacksheepr: ', as.character(packageVersion('blacksheepr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deva_standard_workflow.csv versions.yml
    """
}

workflow BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phosphotable.csv, comptable.csv ] ]

    main:
    BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW.out.tables
    plots    = BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW.out.plots
    objects  = BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW.out.objects
    versions = BIOC_BLACKSHEEPR_DEVA_STANDARD_WORKFLOW.out.versions
}
