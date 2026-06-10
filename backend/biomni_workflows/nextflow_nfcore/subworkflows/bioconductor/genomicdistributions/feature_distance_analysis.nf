#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicDistributions — feature_distance_analysis
// Calculate and visualize the distance of genomic ranges to the nearest genomic features (such as TSS or custom features).
// Input: queryFile.bed
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// Requires: GenomicDistributions, GenomicRanges, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import query genomic ranges
//  * 2. [Core Analysis] Calculate distances to TSS using calcFeatureDistRefTSS
//  * 3. [Visualization & Output] Plot TSS distance distribution using plotFeatureDist
//  * 4. [Core Analysis] Calculate distances to custom features using calcFeatureDist
//  * 5. [Visualization & Output] Plot custom feature distance distribution using plotFeatureDist

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GenomicDistributions", "GenomicRanges", "ggplot2", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("ggplot2")
    
    # Define input file
    queryFile <- "queryFile.bed"
    
    # Check if the input file exists
    if (!file.exists(queryFile)) {
      stop(paste("Error: Input file '", queryFile, "' not found in the working directory.", sep=""))
    }
    
    # 1. Import query genomic ranges
    message("Importing query genomic ranges...")
    query <- rtracklayer::import(queryFile)
    
    # 2. Calculate distances to TSS using calcFeatureDistRefTSS
    message("Calculating distances to TSS (single query)...")
    TSSdist <- calcFeatureDistRefTSS(query, "hg19")
    
    # Save calculated distances to a CSV file
    write.csv(as.data.frame(TSSdist), file = "TSS_distances_single.csv", row.names = FALSE)
    
    # 3. Plot TSS distance distribution using plotFeatureDist
    message("Plotting TSS distance distribution (single query)...")
    p1 <- plotFeatureDist(TSSdist, featureName="TSS")
    ggsave("TSS_distance_plot_single.pdf", plot = p1, width = 7, height = 5)
    
    # Multi-sample TSS distance calculation and plotting (as documented)
    message("Calculating distances to TSS (multiple queries)...")
    query2 <- GenomicRanges::shift(query, 1e6)
    queryList <- GRangesList(vistaEnhancers=query, shifted=query2)
    TSSdist2 <- calcFeatureDistRefTSS(queryList, "hg19")
    
    # Save multi-sample distances
    write.csv(as.data.frame(TSSdist2), file = "TSS_distances_multi.csv", row.names = FALSE)
    
    message("Plotting TSS distance distribution (multiple queries)...")
    p2 <- plotFeatureDist(TSSdist2, featureName="TSS")
    ggsave("TSS_distance_plot_multi.pdf", plot = p2, width = 7, height = 5)
    
    message("Plotting tiled TSS distance distribution...")
    p3 <- plotFeatureDist(TSSdist2, featureName="TSS", tile=TRUE, labelOrder = "center")
    ggsave("TSS_distance_plot_multi_tiled.pdf", plot = p3, width = 7, height = 5)
    
    # 4. Calculate distances to custom features using calcFeatureDist
    message("Calculating distances to custom features...")
    featureExample <- GenomicRanges::shift(query, round(rnorm(length(query), 0, 1000)))
    fdd <- calcFeatureDist(query, featureExample)
    
    # Save custom feature distances
    write.csv(as.data.frame(fdd), file = "custom_feature_distances.csv", row.names = FALSE)
    
    # 5. Plot custom feature distance distribution using plotFeatureDist
    message("Plotting custom feature distance distribution...")
    p4 <- plotFeatureDist(fdd)
    ggsave("custom_feature_distance_plot.pdf", plot = p4, width = 7, height = 5)
    
    message("Pipeline completed successfully. Outputs saved to current working directory.")

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS":',
        paste0('    GenomicDistributions: ', as.character(packageVersion('GenomicDistributions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_distance_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ queryFile.bed ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_FEATURE_DISTANCE_ANALYSIS.out.versions
}
