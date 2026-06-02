#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: easier
// This package provides a workflow for the use of EaSIeR tool, developed to assess patients' likelihoo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/easier/inst/doc/easier_user_manual.R
// Upstream  : SummarizedExperiment, easierData, knitr
// Downstream: none
//
// Install: BiocManager::install("easier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EASIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-easier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-easier:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-easier:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_easier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_easier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_easier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(easier)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    library(knitr)
    table1 <- "
    | Quantitative descriptor  | Descriptor conception  | Prior knowledge |
    | -----------------------  | ----------------------------------- | ----------------------------------- |
    | Pathway activity | @HOLLAND2020194431; @Schubert2018 | @HOLLAND2020194431; @Schubert2018 |
    | Immune cell quantification | @Finotello2019 | @Finotello2019 |
    | TF activity | @Garcia-Alonso01082019 | @Garcia-Alonso01082019 |
    | Ligand-Receptor pairs | @LAPUENTESANTANA2021100293 | @Ramilowski2015; @Barretina2012 |
    | Cell-cell interaction | @LAPUENTESANTANA2021100293 | @Ramilowski2015; @Barretina2012 |
    Table: Quantitative descriptors of the TME

    # --- Table2 [] ---
    # Key functions: activity, score, signature, resistance, get_Mariathasan2018_PDL1_treatment, colData, metadata, assays
    table2 <- "
    | Hallmark of the immune response | Original study |
    |-------------------------------- | -------------- |
    | Cytolytic activity (CYT) | @ROONEY201548 |
    | Roh immune score (Roh_IS) | @Roheaah3560 |
    | Chemokine signature (chemokines) | @Messina2012 |
    | Davoli immune signature (Davoli_IS) | @Davolieaaf8399 |
    | IFNy signature (IFNy) | @Ayers2017 |
    | Expanded immune signature (Ayers_expIS) | @Ayers2017 |
    | T-cell inflamed signature (Tcell_inflamed) | @Ayers2017 |
    dataset_mariathasan <- get_Mariathasan2018_PDL1_treatment()

    # patient response
    patient_ICBresponse <- colData(dataset_mariathasan)[["BOR"]]
    names(patient_ICBresponse) <- colData(dataset_mariathasan)[["pat_id"]]

    # tumor mutational burden
    TMB <- colData(dataset_mariathasan)[["TMB"]]
    names(TMB) <- colData(dataset_mariathasan)[["pat_id"]]

    # --- Eval=true [] ---
    # Key functions: compute_scores_immune_response, Roh_IS, chemokines, Davoli_IS, Ayers_expIS, Tcell_inflamed, compute_cell_fractions
    hallmarks_of_immune_response <- c("CYT", "Roh_IS", "chemokines", "Davoli_IS", "IFNy", "Ayers_expIS", "Tcell_inflamed", "RIR", "TLS")
    immune_response_scores <- compute_scores_immune_response(RNA_tpm = RNA_tpm, 
                                                             selected_scores = hallmarks_of_immune_response)
    head(immune_response_scores)
    cell_fractions <- compute_cell_fractions(RNA_tpm = RNA_tpm)
    head(cell_fractions)

    # --- Eval=true [] ---
    # Key functions: compute_pathway_activity, compute_TF_activity
    pathway_activities <- compute_pathway_activity(RNA_counts = RNA_counts,
                                                   remove_sig_genes_immune_response = TRUE)
    head(pathway_activities)
    tf_activities <- compute_TF_activity(RNA_tpm = RNA_tpm)
    head(tf_activities[,1:5])

    # --- Eval=true [] ---
    # Key functions: compute_LR_pairs, pancan, compute_CC_pairs
    lrpair_weights <- compute_LR_pairs(RNA_tpm = RNA_tpm,
                                       cancer_type = "pancan")
    head(lrpair_weights[,1:5])
    ccpair_scores <- compute_CC_pairs(lrpairs = lrpair_weights, 
                                      cancer_type = "pancan")
    head(ccpair_scores[,1:5])

    # --- Eval=true [] ---
    # Key functions: predict_immune_response, assess_immune_response, weighted_average
    predictions <- predict_immune_response(pathways = pathway_activities,
                                           immunecells = cell_fractions,
                                           tfs = tf_activities,
                                           lrpairs = lrpair_weights,
                                           ccpairs = ccpair_scores,
                                           cancer_type = cancer_type, 
                                           verbose = TRUE)
    output_eval_with_resp <- assess_immune_response(predictions_immune_response = predictions,
                                                    patient_response = patient_ICBresponse,
                                                    RNA_tpm = RNA_tpm,
                                                    TMB_values = TMB,
                                                    easier_with_TMB = "weighted_average",
                                                    weight_penalty = 0.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_easier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_easier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_easier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EASIER:", paste0("    easier: ", packageVersion("easier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easier_results.csv
    touch ${prefix}_easier_output.rds
    echo "BIOC_EASIER:" > versions.yml
    echo "    easier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EASIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EASIER(ch_input)

    emit:
    results  = BIOC_EASIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EASIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EASIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EASIER.out.versions  // channel: path(versions.yml)
}
