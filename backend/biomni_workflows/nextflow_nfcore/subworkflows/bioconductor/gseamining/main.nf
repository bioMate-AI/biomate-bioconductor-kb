#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSEAmining — gsea_clustering_and_visualization
// Filter, cluster, and visualize GSEA results based on leading-edge gene similarity, and generate a comprehensive PDF report.
// Input: gsea_results.csv
// Container: quay.io/biocontainers/bioconductor-gseamining:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEAmining
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter GSEA results using gm_filter
//  * 2. [Core Analysis] Perform hierarchical clustering of gene sets using gm_clust
//  * 3. [Visualization & Output] Plot the cluster dendrogram using gm_dendplot
//  * 4. [Visualization & Output] Visualize enriched terms in gene set names per cluster using gm_enrichterms
//  * 5. [Visualization & Output] Visualize enriched genes in leading edge subsets per cluster using gm_enrichcores
//  * 6. [Visualization & Output] Generate a comprehensive PDF report using gm_enrichreport

nextflow.enable.dsl = 2

process BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION {
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
    .bm_deps <- c("GSEAmining")
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
    library(GSEAmining)
    
    # 1. Read the user input GSEA results file
    # The input file must contain at least: ID, NES, p.adjust, and core_enrichment columns
    genesets_sel <- read.csv("gsea_results.csv", stringsAsFactors = FALSE)
    
    # 2. Filter GSEA results using gm_filter
    gs.filt <- gm_filter(genesets_sel, 
                         p.adj = 0.05, 
                         neg_NES = 2.6, 
                         pos_NES = 2)
    
    # Save the filtered gene sets to a CSV file
    write.csv(gs.filt, "gs_filtered.csv", row.names = FALSE)
    
    # 3. Perform hierarchical clustering of gene sets using gm_clust
    gs.cl <- gm_clust(gs.filt)
    
    # Save the cluster object as an RDS file
    saveRDS(gs.cl, "gs_clusters.rds")
    
    # 4. Plot the cluster dendrograms and save to PDF
    pdf("gm_dendrogram_plots.pdf", width = 10, height = 8)
    gm_dendplot(gs.filt, 
                gs.cl)
    
    gm_dendplot(gs.filt, 
                gs.cl, 
                col_pos = 'orange', 
                col_neg = 'black', 
                rect = TRUE,
                dend_len = 20, 
                rect_len = 2)
    dev.off()
    
    # 5. Visualize enriched terms in gene set names per cluster and save to PDF
    pdf("gm_enrichterms_plots.pdf", width = 10, height = 8)
    print(gm_enrichterms(gs.filt, gs.cl))
    
    print(gm_enrichterms(gs.filt, 
                   gs.cl, 
                   clust = FALSE,
                   col_pos = 'chocolate3',
                   col_neg = 'skyblue3'))
    dev.off()
    
    # 6. Visualize enriched genes in leading edge subsets per cluster and save to PDF
    pdf("gm_enrichcores_plots.pdf", width = 10, height = 12)
    print(gm_enrichcores(gs.filt, gs.cl))
    dev.off()
    
    # 7. Generate a comprehensive PDF report
    gm_enrichreport(gs.filt, gs.cl, output = 'gm_report')

    writeLines(c(
        '"BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION":',
        paste0('    GSEAmining: ', as.character(packageVersion('GSEAmining')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsea_clustering_and_visualization.csv versions.yml
    """
}

workflow BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gsea_results.csv ] ]

    main:
    BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION.out.tables
    plots    = BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION.out.plots
    objects  = BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION.out.objects
    versions = BIOC_GSEAMINING_GSEA_CLUSTERING_AND_VISUALIZATION.out.versions
}
