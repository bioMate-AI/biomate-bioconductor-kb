#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicSuperSignature — transcriptomic_dataset_validation
// Validate a user's transcriptomic dataset against a pre-built RAVmodel to identify and biologically interpret the most relevant Replicable Axes of Variation (RAV
// Input: dataset.rds
// Container: quay.io/biocontainers/bioconductor-genomicsupersignature:1.18.0--r45hdfd78af_0
// R packages: bcellviper, biocmanager, GenomicSuperSignature
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicSuperSignature
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the GenomicSuperSignature package and download/load
//  * 2. [Visualization & Output] Load the user's transcriptomic dataset (ensuring gene
//  * 3. [Visualization & Output] Validate the dataset against the RAVmodel
//  * 4. [Visualization & Output] Visualize the validation results
//  * 5. [Visualization & Output] Extract the indices of the top validated RAVs
//  * 6. [Visualization & Output] Interpret the validated RAVs
//  * 7. [Visualization & Output] Search for specific biological themes using keyword-based

nextflow.enable.dsl = 2

process BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION {
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
    .bm_deps <- c("bcellviper", "biocmanager", "GenomicSuperSignature")
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
    
    # --- Load the GenomicSuperSignature package and download/load ---
    library(GenomicSuperSignature)
    
    # Download/load the pre-built RAVmodel
    RAVmodel <- getModel("PLIERpriors", load = TRUE)
    
    # --- Load the user's transcriptomic dataset (ensuring gene ---
    # The user input file is exactly "dataset.rds"
    dset <- readRDS("dataset.rds")
    
    # --- Validate the dataset against the RAVmodel ---
    val_all <- validate(dset, RAVmodel)
    write.csv(as.data.frame(val_all), "validation_scores.csv", row.names = TRUE)
    
    # Print head of validation results
    print(head(val_all))
    
    # --- Visualize the validation results ---
    # Save heatmapTable to PDF
    pdf("heatmap_table.pdf", width = 10, height = 8)
    tryCatch({
      heatmapTable(val_all, RAVmodel, num.out = 5, swCutoff = 0)
    }, error = function(e) {
      message("Error plotting heatmapTable: ", e\$message)
    })
    dev.off()
    
    # Save plotValidate to PDF
    pdf("validation_plot.pdf", width = 8, height = 6)
    tryCatch({
      plotValidate(val_all, interactive = FALSE)
    }, error = function(e) {
      message("Error plotting plotValidate: ", e\$message)
    })
    dev.off()
    
    # --- Extract the indices of the top validated RAVs ---
    validated_ind <- validatedSignatures(val_all, RAVmodel, num.out = 3, swCutoff = 0, indexOnly = TRUE)
    saveRDS(validated_ind, "validated_indices.rds")
    print(validated_ind)
    
    # --- Interpret the validated RAVs ---
    # Draw word clouds of MeSH terms
    pdf("wordclouds.pdf", width = 7, height = 7)
    set.seed(1)
    tryCatch({
      drawWordcloud(RAVmodel, validated_ind[1])
    }, error = function(e) {
      message("Error drawing wordcloud 1: ", e\$message)
    })
    
    tryCatch({
      drawWordcloud(RAVmodel, validated_ind[2])
    }, error = function(e) {
      message("Error drawing wordcloud 2: ", e\$message)
    })
    
    tryCatch({
      drawWordcloud(RAVmodel, validated_ind[3])
    }, error = function(e) {
      message("Error drawing wordcloud 3: ", e\$message)
    })
    dev.off()
    
    # GSEA pathway annotations
    tryCatch({
      ann_rav2 <- annotateRAV(RAVmodel, validated_ind[2])
      write.csv(as.data.frame(ann_rav2), "annotate_rav_2.csv", row.names = TRUE)
    }, error = function(e) {
      message("Error annotating RAV index 2: ", e\$message)
    })
    
    tryCatch({
      pathways_rav2 <- subsetEnrichedPathways(RAVmodel, validated_ind[2], include_nes = TRUE)
      write.csv(as.data.frame(pathways_rav2), "enriched_pathways_rav2.csv", row.names = TRUE)
    }, error = function(e) {
      message("Error subsetting enriched pathways for RAV index 2: ", e\$message)
    })
    
    tryCatch({
      pathways_all <- subsetEnrichedPathways(RAVmodel, validated_ind, include_nes = TRUE)
      write.csv(as.data.frame(pathways_all), "enriched_pathways_all.csv", row.names = TRUE)
    }, error = function(e) {
      message("Error subsetting enriched pathways for all validated indices: ", e\$message)
    })
    
    # --- Search for specific biological themes using keyword-based ---
    sig_bcell <- findSignature(RAVmodel, "Bcell")
    write.csv(as.data.frame(sig_bcell), "signature_search_bcell.csv", row.names = TRUE)
    
    sig_bcell_k5 <- findSignature(RAVmodel, "Bcell", k = 5)
    saveRDS(sig_bcell_k5, "signature_search_bcell_k5.rds")
    
    kw_695 <- findKeywordInRAV(RAVmodel, "Bcell", ind = 695)
    saveRDS(kw_695, "keyword_rank_695.rds")
    
    tryCatch({
      pathways_both_rav2 <- subsetEnrichedPathways(RAVmodel, ind = validated_ind[2], n = 3, both = TRUE)
      write.csv(as.data.frame(pathways_both_rav2), "pathways_both_rav2.csv", row.names = TRUE)
    }, error = function(e) {
      message("Error subsetting both enriched pathways for RAV index 2: ", e\$message)
    })
    
    pathways_both_695 <- subsetEnrichedPathways(RAVmodel, ind = 695, n = 3, both = TRUE)
    write.csv(as.data.frame(pathways_both_695), "pathways_both_695.csv", row.names = TRUE)
    
    pathways_both_953 <- subsetEnrichedPathways(RAVmodel, ind = 953, n = 3, both = TRUE)
    write.csv(as.data.frame(pathways_both_953), "pathways_both_953.csv", row.names = TRUE)
    
    pathways_both_1994 <- subsetEnrichedPathways(RAVmodel, ind = 1994, n = 3, both = TRUE)
    write.csv(as.data.frame(pathways_both_1994), "pathways_both_1994.csv", row.names = TRUE)
    
    # Associated prior studies
    tryCatch({
      studies_rav2 <- findStudiesInCluster(RAVmodel, validated_ind[2])
      write.csv(as.data.frame(studies_rav2), "studies_in_cluster_rav2.csv", row.names = FALSE)
    }, error = function(e) {
      message("Error finding studies in cluster for RAV index 2: ", e\$message)
    })
    
    tryCatch({
      studies_title_rav2 <- findStudiesInCluster(RAVmodel, validated_ind[2], studyTitle = TRUE)
      write.csv(as.data.frame(studies_title_rav2), "studies_in_cluster_title_rav2.csv", row.names = FALSE)
    }, error = function(e) {
      message("Error finding studies with titles in cluster for RAV index 2: ", e\$message)
    })
    
    # Print session info
    sessionInfo()

    writeLines(c(
        '"BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION":',
        paste0('    GenomicSuperSignature: ', as.character(packageVersion('GenomicSuperSignature')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcriptomic_dataset_validation.csv versions.yml
    """
}

workflow BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset.rds ] ]

    main:
    BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION(ch_input)

    emit:
    tables   = BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION.out.tables
    plots    = BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION.out.plots
    objects  = BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION.out.objects
    versions = BIOC_GENOMICSUPERSIGNATURE_TRANSCRIPTOMIC_DATASET_VALIDATION.out.versions
}
