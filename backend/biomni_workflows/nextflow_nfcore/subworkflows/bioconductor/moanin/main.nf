#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: moanin — weekly_timepoint_de
// Perform differential expression analysis comparing conditions or timepoints at individual weekly intervals using limma and voom weights.
// Input: preData, preMeta
// Container: quay.io/biocontainers/bioconductor-moanin:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: moanin
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a Moanin model object using create_moanin_model
//  * 2. [Core Analysis] Generate timepoint contrasts using create_timepoints_contrasts
//  * 3. [Core Analysis] Run weekly differential expression analysis using DE_timepoints

nextflow.enable.dsl = 2

process BIOC_MOANIN_WEEKLY_TIMEPOINT_DE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # Load required libraries
            library(moanin)
            
            # Read user input files from the working directory
            # Supporting RDS, CSV, and TSV formats for preData and preMeta
            if (file.exists("preData.rds")) {
              preData <- readRDS("preData.rds")
            } else if (file.exists("preData.csv")) {
              preData <- as.matrix(read.csv("preData.csv", row.names = 1, check.names = FALSE))
            } else if (file.exists("preData.tsv")) {
              preData <- as.matrix(read.delim("preData.tsv", row.names = 1, check.names = FALSE))
            } else if (file.exists("preData")) {
              preData <- tryCatch(readRDS("preData"), error = function(e) {
                as.matrix(read.csv("preData", row.names = 1, check.names = FALSE))
              })
            } else {
              stop("Error: preData file not found in the working directory.")
            }
            
            if (file.exists("preMeta.rds")) {
              preMeta <- readRDS("preMeta.rds")
            } else if (file.exists("preMeta.csv")) {
              preMeta <- read.csv("preMeta.csv", row.names = 1, check.names = FALSE)
            } else if (file.exists("preMeta.tsv")) {
              preMeta <- read.delim("preMeta.tsv", row.names = 1, check.names = FALSE)
            } else if (file.exists("preMeta")) {
              preMeta <- tryCatch(readRDS("preMeta"), error = function(e) {
                read.csv("preMeta", row.names = 1, check.names = FALSE)
              })
            } else {
              stop("Error: preMeta file not found in the working directory.")
            }
            
            # Ensure preData is a matrix
            preData <- as.matrix(preData)
            
            # Dynamically identify group and time variables
            is_char_or_factor <- sapply(preMeta, function(x) is.character(x) || is.factor(x))
            is_numeric <- sapply(preMeta, is.numeric)
            
            group_var <- if (any(is_char_or_factor)) names(is_char_or_factor)[is_char_or_factor][1] else colnames(preMeta)[1]
            
            numeric_cols <- names(is_numeric)[is_numeric]
            numeric_cols <- numeric_cols[numeric_cols != group_var]
            time_var <- if (length(numeric_cols) > 0) numeric_cols[1] else setdiff(colnames(preMeta), group_var)[1]
            
            # 1. Create a Moanin model object using create_moanin_model
            moaninObject <- create_moanin_model(data=preData, meta=preMeta, 
                                        group_variable=group_var, time_variable=time_var,
                                        log_transform=TRUE)
            
            # 2. Generate timepoint contrasts using create_timepoints_contrasts
            groups <- unique(as.character(preMeta[[group_var]]))
            
            all_contrasts <- c()
            if (length(groups) > 1) {
              for (i in 1:(length(groups)-1)) {
                for (j in (i+1):length(groups)) {
                  all_contrasts <- c(all_contrasts, create_timepoints_contrasts(moaninObject, groups[i], groups[j]))
                }
              }
            }
            
            # 3. Run weekly differential expression analysis using DE_timepoints
            weeklyPre <- DE_timepoints(moaninObject, 
                contrasts=all_contrasts,
                 use_voom_weights=TRUE)
            
            if (length(groups) > 1) {
              preGroupDiffContrasts <- create_timepoints_contrasts(
                  moaninObject, groups[1], groups[2] ,type="group_and_timepoint_diff")
              
              weeklyGroupDiffPre <- DE_timepoints(moaninObject, 
                  contrasts=preGroupDiffContrasts,
                   use_voom_weights=TRUE)
            } else {
              weeklyGroupDiffPre <- data.frame()
            }
            
            # Write outputs to the working directory
            write.csv(weeklyPre, "weekly_timepoint_de_results.csv", row.names = TRUE)
            write.csv(weeklyGroupDiffPre, "weekly_group_diff_de_results.csv", row.names = TRUE)
            saveRDS(moaninObject, "moanin_model.rds")

    writeLines(c(
        '"BIOC_MOANIN_WEEKLY_TIMEPOINT_DE":',
        paste0('    moanin: ', as.character(packageVersion('moanin')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weekly_timepoint_de.csv versions.yml
    """
}

workflow BIOC_MOANIN_WEEKLY_TIMEPOINT_DE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ preData, preMeta ] ]

    main:
    BIOC_MOANIN_WEEKLY_TIMEPOINT_DE(ch_input)

    emit:
    tables   = BIOC_MOANIN_WEEKLY_TIMEPOINT_DE.out.tables
    plots    = BIOC_MOANIN_WEEKLY_TIMEPOINT_DE.out.plots
    objects  = BIOC_MOANIN_WEEKLY_TIMEPOINT_DE.out.objects
    versions = BIOC_MOANIN_WEEKLY_TIMEPOINT_DE.out.versions
}
