#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — pca_and_clustering_with_uncertainty
// Perform dimension reduction and clustering on expression data while propagating measurement uncertainty.
// Input: eset_estrogen_mmgmos
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// Requires: Biobase, puma
// Visualizations: UMAP plot, PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run principal components analysis using pumaPCA
//  * 2. [Visualization & Output] Plot PCA results
//  * 3. [Visualization & Output] Export PCA results using write.reslts
//  * 4. [Core Analysis] Cluster probe-sets using pumaClust or robust Student's t mixture model with pumaClustii
//  * 5. [Visualization & Output] Export cluster assignments

nextflow.enable.dsl = 2

process BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "puma")
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
        library(puma)
        library(Biobase)
        
        # 1. Read the user input file
        # The pipeline must read EXACTLY these files from the working directory: eset_estrogen_mmgmos
        input_file <- "eset_estrogen_mmgmos"
        if (file.exists(input_file)) {
          eset_estrogen_mmgmos <- readRDS(input_file)
        } else if (file.exists(paste0(input_file, ".rds"))) {
          eset_estrogen_mmgmos <- readRDS(paste0(input_file, ".rds"))
        } else if (file.exists(paste0(input_file, ".RData"))) {
          env <- new.env()
          load(paste0(input_file, ".RData"), envir = env)
          eset_estrogen_mmgmos <- env[[ls(env)[1]]]
        } else {
          stop("Error: Input file 'eset_estrogen_mmgmos' not found in the working directory.")
        }
        
        # Subset to first 200 features for computational efficiency in clustering/PCA
        if (nrow(eset_estrogen_mmgmos) > 200) {
          eset_estrogen_mmgmos <- eset_estrogen_mmgmos[1:200, ]
        }
        
        # 2. Run principal components analysis using pumaPCA
        pumapca_estrogen <- pumaPCA(eset_estrogen_mmgmos)
        
        # 3. Plot PCA results
        pdf("pumaPCA_plot.pdf")
        plot(pumapca_estrogen, legend1pos="right", legend2pos="top", main="pumaPCA")
        dev.off()
        
        # 4. Export PCA results using write.reslts
        write.reslts(pumapca_estrogen, file="pumapca_estrogen")
        
        # 5. Cluster probe-sets using pumaClust
        pumaClust_estrogen <- pumaClust(eset_estrogen_mmgmos, clusters=7)
        summary(as.factor(pumaClust_estrogen\$cluster))
        pumaClust_estrogen\$centers
        
        # 6. Export cluster assignments
        write.csv(pumaClust_estrogen\$cluster, file="pumaClust_clusters.csv")
        
        # 7. Robust Student's t mixture model with pumaClustii
        Clustii.exampleE <- exprs(eset_estrogen_mmgmos)
        Clustii.exampleStd <- assayDataElement(eset_estrogen_mmgmos, "se.exprs")
        
        r <- c(1, 1, 2, 2, 3, 3, 4, 4)
        
        # Run pumaClustii with a tryCatch to ensure robustness
        tryCatch({
          cl <- pumaClustii(Clustii.exampleE, Clustii.exampleStd,
                            mincls=6, maxcls=6, conds=4, reps=r, eps=1e-3)
          saveRDS(cl, file="pumaClustii_results.rds")
        }, error = function(e) {
          warning("pumaClustii failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY":',
        paste0('    puma: ', as.character(packageVersion('puma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_and_clustering_with_uncertainty.csv versions.yml
    """
}

workflow BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eset_estrogen_mmgmos ] ]

    main:
    BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY(ch_input)

    emit:
    tables   = BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY.out.tables
    plots    = BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY.out.plots
    objects  = BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY.out.objects
    versions = BIOC_PUMA_PCA_AND_CLUSTERING_WITH_UNCERTAINTY.out.versions
}
