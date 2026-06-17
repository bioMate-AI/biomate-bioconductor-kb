#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cTRAP — predict_targeting_drugs_and_descriptors
// Predict drugs targeting the user's differential expression profile and analyze the enrichment of molecular descriptors among candidate drugs.
// Input: diffExprStat
// Container: quay.io/biocontainers/bioconductor-ctrap:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cTRAP
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load expression and drug sensitivity association data
//  * 2. [Core Analysis] Predict targeting drugs based on the differential expression profile
//  * 3. [Visualization & Output] Plot targeting drug predictions and compare against similar perturbations
//  * 4. [Input & Preparation] Load drug descriptors and prepare drug sets
//  * 5. [Visualization & Output] Analyze and plot drug set enrichment

nextflow.enable.dsl = 2

process BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS {
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
    .bm_deps <- c("cTRAP")
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
        
        # Load required library
        library(cTRAP)
        
        # 1. Load user input
        if (file.exists("diffExprStat.rds")) {
          diffExprStat <- readRDS("diffExprStat.rds")
        } else if (file.exists("diffExprStat.csv")) {
          df <- read.csv("diffExprStat.csv", row.names = 1)
          diffExprStat <- df[[1]]
          names(diffExprStat) <- rownames(df)
        } else {
          stop("Input file 'diffExprStat.rds' or 'diffExprStat.csv' not found in the working directory.")
        }
        
        # 2. Load expression and drug sensitivity association data
        listExpressionDrugSensitivityAssociation()
        ctrp      <- listExpressionDrugSensitivityAssociation()[[2]]
        assoc     <- loadExpressionDrugSensitivityAssociation(ctrp)
        
        # 3. Predict targeting drugs based on the differential expression profile
        predicted <- predictTargetingDrugs(diffExprStat, assoc)
        
        # Save predicted targeting drugs results
        saveRDS(predicted, "predicted_targeting_drugs.rds")
        write.csv(as.data.frame(predicted), "predicted_targeting_drugs.csv", row.names = FALSE)
        
        # 4. Plot targeting drug predictions
        pdf("predicted_targeting_drugs_plots.pdf")
        print(plot(predicted, method="rankProduct"))
        print(plot(predicted, predicted[[1, 1]], method="spearman"))
        print(plot(predicted, predicted[[1, 1]], method="gsea"))
        dev.off()
        
        # Compute similar perturbations using CMap reference data
        cmapMetadata <- loadCMapData("cmapMetadata.txt", type="metadata")
        cmapMetadataCompounds <- filterCMapMetadata(
          cmapMetadata, cellLine="HepG2", perturbationType="Compound")
        cmapPerturbationsCompounds <- prepareCMapPerturbations(
          metadata=cmapMetadataCompounds, zscores="cmapZscores.gctx",
          geneInfo="cmapGeneInfo.txt", compoundInfo="cmapCompoundInfo.txt", ask = FALSE)
        compareCompounds <- rankSimilarPerturbations(diffExprStat, cmapPerturbationsCompounds)
        
        # Plot targeting drugs vs similar perturbations
        tryCatch({
          pdf("targeting_vs_similar_plots.pdf")
          print(plotTargetingDrugsVSsimilarPerturbations(
            predicted, compareCompounds, column="spearman_rank"))
          print(plotTargetingDrugsVSsimilarPerturbations(
            predicted, compareCompounds, column="spearman_rank", labelBy="target"))
          print(plotTargetingDrugsVSsimilarPerturbations(
            predicted, compareCompounds, column="spearman_rank", labelBy="moa"))
          dev.off()
        }, error = function(e) {
          warning("Could not plot targeting drugs vs similar perturbations: ", e\$message)
          if (names(dev.cur()) != "null device") dev.off()
        })
        
        # 5. Load drug descriptors and prepare drug sets
        descriptors <- loadDrugDescriptors("CMap", "2D")
        drugSets    <- prepareDrugSets(descriptors)
        
        # 6. Analyze and plot drug set enrichment
        dsea        <- analyseDrugSetEnrichment(drugSets, predicted)
        write.csv(dsea, "drug_set_enrichment_results.csv", row.names = FALSE)
        
        pdf("drug_set_enrichment_plots.pdf")
        print(plotDrugSetEnrichment(drugSets, predicted,
                              selectedSets=head(dsea\$descriptor, 6)))
        dev.off()

    writeLines(c(
        '"BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS":',
        paste0('    cTRAP: ', as.character(packageVersion('cTRAP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_targeting_drugs_and_descriptors.csv versions.yml
    """
}

workflow BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ diffExprStat ] ]

    main:
    BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS(ch_input)

    emit:
    tables   = BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS.out.tables
    plots    = BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS.out.plots
    objects  = BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS.out.objects
    versions = BIOC_CTRAP_PREDICT_TARGETING_DRUGS_AND_DESCRIPTORS.out.versions
}
