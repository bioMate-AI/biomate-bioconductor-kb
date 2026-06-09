#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTN — regulon_activity_profiling_and_cohort_projection
// Calculate sample-specific regulon activity profiles (RAPs) for a cohort and project previously calculated regulons onto a new cohort.
// Input: cohort_a_tni.RData, cohort_b_expression.csv
// Container: quay.io/biocontainers/bioconductor-rtn:2.34.0--r45hdfd78af_0
// Requires: RTN, SummarizedExperiment, pheatmap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute sample-specific regulon activity for Cohort A using tni.gsea2
//  * 2. [Core Analysis] Retrieve activity scores using tni.get
//  * 3. [Core Analysis] Replace the expression data and sample annotations of the Cohort A TNI object with Cohort B using tni.replace.samples
//  * 4. [Core Analysis] Compute sample-specific regulon activity for Cohort B using tni.gsea2
//  * 5. [Core Analysis] Retrieve Cohort B activity scores using tni.get

nextflow.enable.dsl = 2

process BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
        # Load required libraries
        library(RTN)
        library(SummarizedExperiment)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        if (!file.exists("cohort_a_tni.RData")) {
          stop("Error: 'cohort_a_tni.RData' not found in the working directory.")
        }
        if (!file.exists("cohort_b_expression.csv")) {
          stop("Error: 'cohort_b_expression.csv' not found in the working directory.")
        }
        
        # Load Cohort A TNI object
        env <- new.env()
        load("cohort_a_tni.RData", envir = env)
        
        # Find the TNI object in the loaded environment
        tni_names <- ls(env)
        rtni1st <- NULL
        for (name in tni_names) {
          if (inherits(env[[name]], "TNI")) {
            rtni1st <- env[[name]]
            break
          }
        }
        if (is.null(rtni1st)) {
          # Fallback to the first object if class check is too strict
          rtni1st <- env[[tni_names[1]]]
        }
        
        # Read Cohort B expression matrix
        cohort_b_expr <- as.matrix(read.csv("cohort_b_expression.csv", row.names = 1, check.names = FALSE))
        
        # Retrieve the regulatory elements (TFs) from the loaded TNI object
        risk.tfs <- tni.get(rtni1st, what = "regulatoryElements")
        if (is.null(risk.tfs) || length(risk.tfs) == 0) {
          stop("Error: No regulatory elements found in the provided Cohort A TNI object.")
        }
        
        # -----------------------------------------------------------------------------
        # 2. Execute Documented Workflow
        # -----------------------------------------------------------------------------
        
        # Stage 1: Compute sample-specific regulon activity for Cohort A using tni.gsea2
        rtni1st <- tni.gsea2(rtni1st, regulatoryElements = risk.tfs)
        
        # Stage 2: Retrieve activity scores using tni.get
        metabric_regact <- tni.get(rtni1st, what = "regulonActivity")
        
        # Stage 3: Replace the expression data and sample annotations of the Cohort A TNI object with Cohort B using tni.replace.samples
        rtni1st_tcgasamples <- tni.replace.samples(rtni1st, expData = cohort_b_expr)
        
        # Stage 4: Compute sample-specific regulon activity for Cohort B using tni.gsea2
        rtni1st_tcgasamples <- tni.gsea2(rtni1st_tcgasamples, regulatoryElements = risk.tfs)
        
        # Stage 5: Retrieve Cohort B activity scores using tni.get
        tcga_regact <- tni.get(rtni1st_tcgasamples, what = "regulonActivity")
        
        # -----------------------------------------------------------------------------
        # 3. Write Named Output Files
        # -----------------------------------------------------------------------------
        
        # Save Cohort A regulon activity profiles
        write.csv(metabric_regact\$dif, file = "cohort_a_regulon_activity_dif.csv", row.names = TRUE)
        write.csv(metabric_regact\$pos, file = "cohort_a_regulon_activity_pos.csv", row.names = TRUE)
        write.csv(metabric_regact\$neg, file = "cohort_a_regulon_activity_neg.csv", row.names = TRUE)
        saveRDS(metabric_regact, file = "cohort_a_regulon_activity.rds")
        
        # Save Cohort B projected regulon activity profiles
        write.csv(tcga_regact\$dif, file = "cohort_b_projected_regulon_activity_dif.csv", row.names = TRUE)
        write.csv(tcga_regact\$pos, file = "cohort_b_projected_regulon_activity_pos.csv", row.names = TRUE)
        write.csv(tcga_regact\$neg, file = "cohort_b_projected_regulon_activity_neg.csv", row.names = TRUE)
        saveRDS(tcga_regact, file = "cohort_b_projected_regulon_activity.rds")
        
        # Save updated TNI objects
        save(rtni1st, file = "cohort_a_tni_with_activity.RData")
        save(rtni1st_tcgasamples, file = "cohort_b_projected_tni.RData")
        
        # Generate PDF plots of the regulon activity profiles
        pdf("regulon_activity_profiles.pdf", width = 10, height = 8)
        if (requireNamespace("pheatmap", quietly = TRUE)) {
          pheatmap::pheatmap(
            t(metabric_regact\$dif),
            main = "Cohort A Regulon Activity Profiles (dif)",
            show_colnames = FALSE,
            clustering_method = "ward.D2",
            clustering_distance_rows = "correlation",
            clustering_distance_cols = "correlation"
          )
          pheatmap::pheatmap(
            t(tcga_regact\$dif),
            main = "Cohort B Projected Regulon Activity Profiles (dif)",
            show_colnames = FALSE,
            clustering_method = "ward.D2",
            clustering_distance_rows = "correlation",
            clustering_distance_cols = "correlation"
          )
        } else {
          heatmap(t(metabric_regact\$dif), main = "Cohort A Regulon Activity Profiles (dif)", LabCol = FALSE)
          heatmap(t(tcga_regact\$dif), main = "Cohort B Projected Regulon Activity Profiles (dif)", LabCol = FALSE)
        }
        dev.off()

    writeLines(c(
        '"BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION":',
        paste0('    RTN: ', as.character(packageVersion('RTN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regulon_activity_profiling_and_cohort_projection.csv versions.yml
    """
}

workflow BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cohort_a_tni.RData, cohort_b_expression.csv ] ]

    main:
    BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION(ch_input)

    emit:
    tables   = BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION.out.tables
    plots    = BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION.out.plots
    objects  = BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION.out.objects
    versions = BIOC_RTN_REGULON_ACTIVITY_PROFILING_AND_COHORT_PROJECTION.out.versions
}
