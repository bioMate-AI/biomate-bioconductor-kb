#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDblFinder — find_doublet_clusters
// Identify entire clusters that are likely composed of doublets by testing for lack of intermediacy in expression profiles.
// Input: sce.rds
// Container: quay.io/biocontainers/bioconductor-scdblfinder:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, bluster, scDblFinder, scater, scran, scuttle
// Visualizations: t-SNE plot, cluster plot
// QC: doublet detection QC, cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize counts using logNormCounts
//  * 2. [Core Analysis] Model gene variance and run PCA
//  * 3. [Core Analysis] Cluster cells using clusterRows
//  * 4. [Core Analysis] Run findDoubletClusters to test each cluster against the doublet null hypothesis

nextflow.enable.dsl = 2

process BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS {
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
    .bm_deps <- c("scuttle", "scran", "scater", "bluster", "scDblFinder")
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
    library(scuttle)
    library(scran)
    library(scater)
    library(bluster)
    library(scDblFinder)
    
    # 1. Read the user input file
    sce <- readRDS("sce.rds")
    
    # 2. Normalize counts using logNormCounts
    sce <- logNormCounts(sce)
    
    # 3. Model gene variance and run PCA
    dec <- modelGeneVar(sce)
    
    set.seed(1000)
    sce <- runPCA(sce, ncomponents=10, subset_row=getTopHVGs(dec, n=1000))
    
    # 4. Cluster cells using clusterRows
    clusters <- clusterRows(reducedDim(sce, "PCA"), NNGraphParam())
    
    # 5. Run t-SNE and plot
    sce <- runTSNE(sce, dimred="PCA")
    
    # Save the t-SNE plot to a PDF file
    pdf("tsne_clusters.pdf", width=8, height=6)
    p <- plotTSNE(sce, colour_by=I(clusters), text_by=I(clusters))
    print(p)
    dev.off()
    
    # 6. Run findDoubletClusters to test each cluster against the doublet null hypothesis
    tab <- findDoubletClusters(sce, clusters)
    
    # 7. Write outputs
    # Save the doublet clusters table as a CSV file
    write.csv(as.data.frame(tab), file="doublet_clusters.csv", row.names=TRUE)
    
    # Save the updated SingleCellExperiment object
    saveRDS(sce, file="sce_processed.rds")

    writeLines(c(
        '"BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS":',
        paste0('    scDblFinder: ', as.character(packageVersion('scDblFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_find_doublet_clusters.csv versions.yml
    """
}

workflow BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.rds ] ]

    main:
    BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS(ch_input)

    emit:
    tables   = BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS.out.tables
    plots    = BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS.out.plots
    objects  = BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS.out.objects
    versions = BIOC_SCDBLFINDER_FIND_DOUBLET_CLUSTERS.out.versions
}
