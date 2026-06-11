#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HIPPO — hippo_scrnaseq_analysis
// Perform simultaneous feature selection, hierarchical clustering, dimension reduction, visualization, and differential expression analysis on single-cell RNA-seq
// Input: counts_matrix.rds, gene_annotation.rds
// Container: quay.io/biocontainers/bioconductor-hippo:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HIPPO, SingleCellExperiment
// Visualizations: UMAP plot, t-SNE plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the count data and reference annotations. 2. Generate a diagnostic plot to visualize zero inflation compared to the expected 

nextflow.enable.dsl = 2

process BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(HIPPO)
    
    # 1. Load the count data and reference annotations
    if (!file.exists("counts_matrix.rds")) {
      stop("Error: 'counts_matrix.rds' is required but was not found in the working directory.")
    }
    
    counts <- readRDS("counts_matrix.rds")
    toydata <- SingleCellExperiment(assays = list(counts = counts))
    
    if (file.exists("gene_annotation.rds")) {
      ensg_hgnc <- readRDS("gene_annotation.rds")
    } else {
      # Fallback: Create a dummy mapping using rownames to ensure the exact code runs
      ensg_hgnc <- data.frame(
        ensg = rownames(toydata),
        hgnc = rownames(toydata),
        stringsAsFactors = FALSE
      )
    }
    
    # 2. Generate a diagnostic plot
    pdf("hippo_diagnostic_plot.pdf", width = 6, height = 4)
    print(hippo_diagnostic_plot(toydata, 
                          show_outliers = TRUE, 
                          zvalue_thresh = 2))
    dev.off()
    
    # 3. Run the main HIPPO algorithm
    set.seed(20200321)
    toydata = hippo(toydata, K = 10, 
                    z_threshold = 2, outlier_proportion = 0.00001)
    
    # 4. Perform dimension reduction and visualize
    toydata = hippo_dimension_reduction(toydata, method="umap")
    pdf("hippo_umap_plot.pdf", width = 6, height = 4)
    print(hippo_umap_plot(toydata))
    dev.off()
    
    toydata = hippo_dimension_reduction(toydata, method="tsne")
    pdf("hippo_tsne_plot.pdf", width = 6, height = 4)
    print(hippo_tsne_plot(toydata))
    dev.off()
    
    # 5. Visualize selected features and zero-inflation reduction
    pdf("zero_proportion_plot.pdf", width = 6, height = 3)
    print(zero_proportion_plot(toydata, 
                         switch_to_hgnc = TRUE, 
                         ref = ensg_hgnc))
    dev.off()
    
    pdf("hippo_feature_heatmap.pdf", width = 6, height = 4)
    print(hippo_feature_heatmap(toydata, k = 3, 
                          switch_to_hgnc = TRUE, 
                          ref = ensg_hgnc, 
                          top.n = 20))
    dev.off()
    
    # 6. Conduct differential expression analysis
    toydata = hippo_diffexp(toydata, 
                      top.n = 5, 
                      switch_to_hgnc = TRUE, 
                      ref = ensg_hgnc)
    
    # Extract and save results
    de_round1 <- get_hippo_diffexp(toydata, 1)
    write.csv(de_round1, "hippo_de_round1.csv", row.names = TRUE)
    print(head(de_round1))
    
    # Save the final processed object
    saveRDS(toydata, "hippo_output.rds")

    writeLines(c(
        '"BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS":',
        paste0('    HIPPO: ', as.character(packageVersion('HIPPO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hippo_scrnaseq_analysis.csv versions.yml
    """
}

workflow BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.rds, gene_annotation.rds ] ]

    main:
    BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS.out.tables
    plots    = BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS.out.plots
    objects  = BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS.out.objects
    versions = BIOC_HIPPO_HIPPO_SCRNASEQ_ANALYSIS.out.versions
}
