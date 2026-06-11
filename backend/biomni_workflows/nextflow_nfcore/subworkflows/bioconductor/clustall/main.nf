#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClustAll — patient_stratification_workflow
// Perform unsupervised patient stratification on clinical data, identify robust cluster representatives, visualize similarities and patient flows, and validate re
// Input: clinical_data.csv
// Container: quay.io/biocontainers/bioconductor-clustall:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ClustAll, htmlwidgets
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load clinical data
//  * 2. [Input & Preparation] Create the ClustAll object using createClustAll
//  * 3. [Core Analysis] Run the ClustAll clustering pipeline using runClustAll
//  * 4. [Visualization & Output] Visualize stratification similarities using plotJACCARD
//  * 5. [Core Analysis] Retrieve representative stratifications using resStratification
//  * 6. [Visualization & Output] Compare stratifications or compare against ground truth using plotSANKEY
//  * 7. [Core Analysis] Append selected stratifications to the original dataset using cluster2data
//  * 8. [Core Analysis] Validate stratifications against ground truth using validateStratification

nextflow.enable.dsl = 2

process BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        library(ClustAll)
        
        # 1. Load clinical data
        # Read the user-provided clinical dataset from the working directory
        data_use <- read.csv("clinical_data.csv", stringsAsFactors = FALSE)
        
        # If an ID column is present, remove it as in the documented workflow
        if ("ID" %in% colnames(data_use)) {
          data_use <- subset(data_use, select = -ID)
        }
        
        # Check missing values and dimensions
        na_count <- sum(is.na(data_use))
        data_dim <- dim(data_use)
        message("Number of missing values: ", na_count)
        message("Dataset dimensions: ", paste(data_dim, collapse = " x "))
        
        # Identify potential ground truth column if present, otherwise NULL
        possible_val_cols <- c("Diagnosis", "diagnosis", "label", "Label", "class", "Class", "ground_truth", "target", "Target")
        val_col <- intersect(possible_val_cols, colnames(data_use))
        if (length(val_col) > 0) {
          val_col <- val_col[1]
        } else {
          char_cols <- names(data_use)[sapply(data_use, function(x) is.character(x) || is.factor(x))]
          if (length(char_cols) == 1) {
            val_col <- char_cols[1]
          } else {
            val_col <- NULL
          }
        }
        
        # 2. Create the ClustAll object
        obj_noNA <- createClustAll(data = data_use, nImputation = NULL, 
                                   dataImputed = NULL, colValidation = val_col)
        
        # 3. Run the ClustAll clustering pipeline
        obj_noNA1 <- runClustAll(Object = obj_noNA, threads = 2, simplify = FALSE)
        
        # Print object summary
        print(obj_noNA1)
        saveRDS(obj_noNA1, "clustall_object.rds")
        
        # 4. Visualize stratification similarities
        pdf("jaccard_heatmap.pdf", width = 12, height = 12)
        tryCatch({
          plotJACCARD(Object = obj_noNA1, stratification_similarity = 0.9, paint = TRUE)
        }, error = function(e) {
          message("Error plotting Jaccard similarity: ", e\$message)
        })
        dev.off()
        
        # 5. Retrieve representative stratifications
        res_strat <- tryCatch({
          resStratification(Object = obj_noNA1, population = 0.05, 
                            stratification_similarity = 0.9, all = FALSE)
        }, error = function(e) {
          message("Error retrieving representative stratifications: ", e\$message)
          NULL
        })
        
        if (!is.null(res_strat)) {
          saveRDS(res_strat, "representative_stratifications.rds")
        }
        
        # Extract dynamic stratification names
        strat_names <- if (!is.null(res_strat)) names(res_strat) else character(0)
        
        # 6. Compare stratifications or compare against ground truth using Sankey diagrams
        tryCatch({
          if (length(strat_names) >= 2) {
            p1 <- plotSANKEY(Object = obj_noNA1, clusters = strat_names[1:2], 
                             validationData = FALSE)
            if (inherits(p1, "htmlwidget")) {
              htmlwidgets::saveWidget(p1, "sankey_comparison.html")
            }
          } else {
            message("Not enough stratifications to compare in Sankey diagram.")
          }
        }, error = function(e) {
          message("Error plotting Sankey comparison: ", e\$message)
        })
        
        tryCatch({
          if (length(strat_names) >= 1 && !is.null(val_col)) {
            p2 <- plotSANKEY(Object = obj_noNA1, clusters = strat_names[1], 
                             validationData = TRUE)
            if (inherits(p2, "htmlwidget")) {
              htmlwidgets::saveWidget(p2, "sankey_validation.html")
            }
          } else {
            message("Skipping Sankey validation: missing stratifications or ground truth column.")
          }
        }, error = function(e) {
          message("Error plotting Sankey validation: ", e\$message)
        })
        
        # 7. Append selected stratifications to the original dataset
        df <- tryCatch({
          if (length(strat_names) > 0) {
            cluster2data(Object = obj_noNA1,
                         stratificationName = strat_names)
          } else {
            NULL
          }
        }, error = function(e) {
          message("Error appending stratifications to dataset: ", e\$message)
          NULL
        })
        
        if (!is.null(df)) {
          write.csv(df, "stratified_patient_data.csv", row.names = FALSE)
          message("First 3 rows of stratified dataset:")
          print(head(df, 3))
        }
        
        # 8. Validate stratifications against ground truth
        validation_results <- list()
        
        if (!is.null(val_col)) {
          for (s_name in strat_names) {
            tryCatch({
              validation_results[[s_name]] <- validateStratification(obj_noNA1, s_name)
              message("Validation for ", s_name, ":")
              print(validation_results[[s_name]])
            }, error = function(e) {
              message("Error validating ", s_name, ": ", e\$message)
            })
          }
        } else {
          message("Skipping validation: no ground truth column identified.")
        }
        
        if (length(validation_results) > 0) {
          saveRDS(validation_results, "validation_results.rds")
        }
        
        # Display session info
        sessionInfo()

    writeLines(c(
        '"BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW":',
        paste0('    ClustAll: ', as.character(packageVersion('ClustAll')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_patient_stratification_workflow.csv versions.yml
    """
}

workflow BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ clinical_data.csv ] ]

    main:
    BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW.out.tables
    plots    = BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW.out.plots
    objects  = BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW.out.objects
    versions = BIOC_CLUSTALL_PATIENT_STRATIFICATION_WORKFLOW.out.versions
}
