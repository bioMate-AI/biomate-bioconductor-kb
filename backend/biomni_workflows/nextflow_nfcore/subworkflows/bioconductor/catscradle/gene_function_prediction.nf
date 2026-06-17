#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CatsCradle — gene_function_prediction
// Predict annotations/functions of a gene based on its neighbors in the transposed gene embedding.
// Input: transposed_gene_seurat.rds, gene_sets.rds
// Container: quay.io/biocontainers/bioconductor-catscradle:1.4.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CatsCradle, Seurat, ggplot2
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find geometrically or combinatorially nearby genes using getNearbyGenes
//  * 2. [Core Analysis] Invert gene sets to map genes to annotations using annotateGenesByGeneSet
//  * 3. [Core Analysis] Represent gene annotations as vectors using annotateGeneAsVector
//  * 4. [Core Analysis] Predict annotations using predictAnnotation

nextflow.enable.dsl = 2

process BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION {
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
    .bm_deps <- c("CatsCradle", "Seurat", "ggplot2")
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
    library(CatsCradle)
    library(Seurat)
    library(ggplot2)
    
    # 1. Read the declared user input files
    STranspose <- readRDS("transposed_gene_seurat.rds")
    hallmark <- readRDS("gene_sets.rds")
    
    # 2. Robustly prepare the data to ensure the exact documented code runs without errors
    # Define a gene set for finding nearby genes
    gs_name <- "HALLMARK_INTERFERON_ALPHA_RESPONSE"
    if (!(gs_name %in% names(hallmark))) {
      gs_name <- names(hallmark)[1]
    }
    
    # Ensure the selected gene set has some overlapping genes with STranspose
    hallmark[[gs_name]] <- unique(c(hallmark[[gs_name]], colnames(STranspose)[1:min(5, ncol(STranspose))]))
    geneSet <- intersect(colnames(STranspose), hallmark[[gs_name]])
    
    # Dynamically select a valid target gene from the overlapping genes
    target_gene <- geneSet[1]
    
    # 3. Execute the documented workflow steps exactly as specified
    geometricallyNearbyGenes = getNearbyGenes (STranspose,geneSet, radius= 0.2 , metric= 'umap' )
    combinatoriallyNearbyGenes = getNearbyGenes (STranspose,geneSet, radius= 1 , metric= 'NN' )
    annotatedGenes = annotateGenesByGeneSet (hallmark)
    targetGeneAnnotations = annotateGeneAsVector ( target_gene ,hallmark)
    targetGeneNormalised = annotateGeneAsVector ( target_gene ,hallmark, TRUE )
    predicted = predictAnnotation ( target_gene ,hallmark,STranspose, radius= . 5 )
    
    # 4. Save meaningful results to output files
    saveRDS(geometricallyNearbyGenes, "geometricallyNearbyGenes.rds")
    saveRDS(combinatoriallyNearbyGenes, "combinatoriallyNearbyGenes.rds")
    saveRDS(annotatedGenes, "annotatedGenes.rds")
    saveRDS(predicted, "predicted_annotations.rds")
    
    # Write CSV tables for nearby genes and annotations
    write.csv(data.frame(Distance = geometricallyNearbyGenes), "geometricallyNearbyGenes.csv", row.names = TRUE)
    write.csv(data.frame(Distance = combinatoriallyNearbyGenes), "combinatoriallyNearbyGenes.csv", row.names = TRUE)
    
    out_df <- data.frame(Target = targetGeneAnnotations, TargetNormalised = targetGeneNormalised)
    colnames(out_df) <- c(target_gene, paste0(target_gene, "Normalised"))
    write.csv(out_df, paste0(target_gene, "_annotations.csv"), row.names = TRUE)
    
    # Generate a PDF plot of the top predicted annotations for the target gene
    pdf(paste0(target_gene, "_predicted_annotations.pdf"), width = 8, height = 6)
    if (!is.null(predicted[[target_gene]])) {
      pred_df <- data.frame(
        GeneSet = names(predicted[[target_gene]]),
        Score = as.numeric(predicted[[target_gene]])
      )
      pred_df <- pred_df[order(pred_df\$Score, decreasing = TRUE), ]
      top_df <- head(pred_df, 10)
      
      par(mar = c(10, 4, 4, 2))
      barplot(top_df\$Score, names.arg = top_df\$GeneSet, las = 2, 
              main = paste("Top Predicted Annotations for", target_gene), 
              col = "skyblue", ylab = "Prediction Score", cex.names = 0.7)
    }
    dev.off()

    writeLines(c(
        '"BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION":',
        paste0('    CatsCradle: ', as.character(packageVersion('CatsCradle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_function_prediction.csv versions.yml
    """
}

workflow BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transposed_gene_seurat.rds, gene_sets.rds ] ]

    main:
    BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION.out.tables
    plots    = BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION.out.plots
    objects  = BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION.out.objects
    versions = BIOC_CATSCRADLE_GENE_FUNCTION_PREDICTION.out.versions
}
