#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metabolomicsWorkbenchR — metabolomics_workbench_annotation
// Query the Metabolomics Workbench API to annotate local feature matrices and find related public studies based on sample conditions.
// Input: intensity.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, metabolomicsWorkbenchR
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    library(metabolomicsWorkbenchR)
    
    # --- Load local data ---
    message("Stage 1: Loading local data...")
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'intensity.csv' or 'coldata.csv' are missing.")
    }
    
    intensity <- read.csv("intensity.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity), rownames(coldata))
    if (length(common_samples) == 0) {
        stop("No common samples found between intensity.csv and coldata.csv")
    }
    intensity <- intensity[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # --- Create SummarizedExperiment ---
    message("Stage 2: Creating SummarizedExperiment...")
    se <- SummarizedExperiment(
        assays = list(intensity = as.matrix(intensity)),
        colData = DataFrame(coldata)
    )
    
    # --- Query Metabolomics Workbench for related studies ---
    message("Stage 3: Querying Metabolomics Workbench for related studies...")
    conditions <- unique(coldata\$condition)
    study_list <- list()
    
    for (cond in conditions) {
        if (is.na(cond) || cond == "") next
        message("Searching studies for condition: ", cond)
        res <- tryCatch({
            do_query(
                context = 'study',
                input_item = 'study_title',
                input_value = cond,
                output_item = 'summary'
            )
        }, error = function(e) {
            message("Query failed for condition '", cond, "': ", e\$message)
            NULL
        })
        if (!is.null(res) && is.data.frame(res) && nrow(res) > 0) {
            res\$queried_condition <- cond
            study_list[[cond]] <- res
        }
    }
    
    if (length(study_list) > 0) {
        # Standardize columns before binding
        all_study_cols <- unique(unlist(lapply(study_list, colnames)))
        standardized_studies <- lapply(study_list, function(df) {
            missing_cols <- setdiff(all_study_cols, colnames(df))
            df[missing_cols] <- NA
            df[, all_study_cols, drop = FALSE]
        })
        matched_studies <- do.call(rbind, standardized_studies)
    } else {
        matched_studies <- data.frame(
            queried_condition = conditions,
            status = "No matching studies found or API query failed"
        )
    }
    
    # --- Query Metabolomics Workbench for feature annotations ---
    message("Stage 4: Querying Metabolomics Workbench for feature annotations...")
    feature_ids <- rownames(se)
    # Limit to first 20 features to avoid API rate limits/timeout
    features_to_query <- head(feature_ids, 20)
    
    # Retrieve valid inputs/outputs dynamically to ensure API compatibility
    refmet_inputs <- tryCatch(context_inputs('refmet'), error = function(e) NULL)
    refmet_outputs <- tryCatch(context_outputs('refmet'), error = function(e) NULL)
    compound_inputs <- tryCatch(context_inputs('compound'), error = function(e) NULL)
    compound_outputs <- tryCatch(context_outputs('compound'), error = function(e) NULL)
    protein_inputs <- tryCatch(context_inputs('protein'), error = function(e) NULL)
    protein_outputs <- tryCatch(context_outputs('protein'), error = function(e) NULL)
    
    query_annotation <- function(fid) {
        # 1. Try RefMet
        if (!is.null(refmet_inputs) && !is.null(refmet_outputs) && length(refmet_inputs) > 0 && length(refmet_outputs) > 0) {
            res <- tryCatch({
                do_query(
                    context = 'refmet',
                    input_item = refmet_inputs[1],
                    input_value = fid,
                    output_item = refmet_outputs[1]
                )
            }, error = function(e) NULL)
            if (!is.null(res) && is.data.frame(res) && nrow(res) > 0) {
                res\$source_context <- "refmet"
                return(res[1, , drop = FALSE])
            }
        }
        # 2. Try Compound
        if (!is.null(compound_inputs) && !is.null(compound_outputs) && length(compound_inputs) > 0 && length(compound_outputs) > 0) {
            res <- tryCatch({
                do_query(
                    context = 'compound',
                    input_item = compound_inputs[1],
                    input_value = fid,
                    output_item = compound_outputs[1]
                )
            }, error = function(e) NULL)
            if (!is.null(res) && is.data.frame(res) && nrow(res) > 0) {
                res\$source_context <- "compound"
                return(res[1, , drop = FALSE])
            }
        }
        # 3. Try Protein
        if (!is.null(protein_inputs) && !is.null(protein_outputs) && length(protein_inputs) > 0 && length(protein_outputs) > 0) {
            res <- tryCatch({
                do_query(
                    context = 'protein',
                    input_item = protein_inputs[1],
                    input_value = fid,
                    output_item = protein_outputs[1]
                )
            }, error = function(e) NULL)
            if (!is.null(res) && is.data.frame(res) && nrow(res) > 0) {
                res\$source_context <- "protein"
                return(res[1, , drop = FALSE])
            }
        }
        return(NULL)
    }
    
    ann_results <- list()
    for (fid in features_to_query) {
        message("Querying annotation for feature: ", fid)
        ann <- query_annotation(fid)
        if (!is.null(ann)) {
            ann\$feature_id <- fid
            ann_results[[fid]] <- ann
        }
    }
    
    if (length(ann_results) > 0) {
        all_ann_cols <- unique(unlist(lapply(ann_results, colnames)))
        standardized_ann <- lapply(ann_results, function(df) {
            missing_cols <- setdiff(all_ann_cols, colnames(df))
            df[missing_cols] <- NA
            df[, all_ann_cols, drop = FALSE]
        })
        annotations_df <- do.call(rbind, standardized_ann)
    } else {
        annotations_df <- data.frame(
            feature_id = feature_ids,
            annotation_status = "No annotation found or API query failed"
        )
    }
    
    # --- Integrate annotations into SummarizedExperiment rowData ---
    message("Stage 5: Integrating annotations into SummarizedExperiment...")
    row_df <- data.frame(feature_id = feature_ids, row.names = feature_ids, stringsAsFactors = FALSE)
    if (nrow(annotations_df) > 0 && "feature_id" %in% colnames(annotations_df)) {
        row_df <- merge(row_df, annotations_df, by = "feature_id", all.x = TRUE)
        rownames(row_df) <- row_df\$feature_id
        row_df <- row_df[feature_ids, , drop = FALSE]
    }
    rowData(se) <- DataFrame(row_df)
    
    # --- Write outputs ---
    message("Stage 6: Writing outputs...")
    write.csv(matched_studies, "matched_studies.csv", row.names = FALSE)
    write.csv(row_df, "feature_annotations.csv", row.names = FALSE)
    saveRDS(se, "annotated_summarized_experiment.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION":',
        paste0('    metabolomicsWorkbenchR: ', as.character(packageVersion('metabolomicsWorkbenchR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolomics_workbench_annotation.csv versions.yml
    """
}

workflow BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION.out.tables
    plots    = BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION.out.plots
    objects  = BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION.out.objects
    versions = BIOC_METABOLOMICSWORKBENCHR_METABOLOMICS_WORKBENCH_ANNOTATION.out.versions
}
