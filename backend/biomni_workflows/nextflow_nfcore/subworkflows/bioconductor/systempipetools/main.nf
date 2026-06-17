#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: systemPipeTools — rna_seq_exploration_and_visualization
// Perform exploratory data analysis, dimensionality reduction, clustering, and differential expression visualization on RNA-seq count data.
// Input: targets.txt, countDFeByg.xls
// Container: quay.io/biocontainers/bioconductor-systempipetools:1.18.0--r45hdfd78af_0
// R packages: systemPipeR, systemPipeTools
// Bioconductor: 3.20 | R: 4.4
// Requires: systemPipeR, systemPipeTools
// Visualizations: volcano plot, heatmap, MA plot, t-SNE plot
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load metadata and raw count matrix
//  * 2. [Core Analysis] Transform raw counts using exploreDDS
//  * 3. [Visualization & Output] Visualize transformation effects with exploreDDSplot
//  * 4. [Visualization & Output] Perform hierarchical clustering with hclustplot and heatMaplot
//  * 5. [Core Analysis] Perform dimensionality reduction using PCAplot, MDSplot, GLMplot, and tSNEplot
//  * 6. [Visualization & Output] Run differential expression analysis and visualize results using MAplot and volcanoplot

nextflow.enable.dsl = 2

process BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION {
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
    .bm_deps <- c("systemPipeR", "systemPipeTools")
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
    library(systemPipeTools)
    library(systemPipeR)
    
    # ==========================================
    # 1. Load metadata and raw count matrix
    # ==========================================
    
    # Read targets and comparisons directly from the working directory
    targetspath <- "targets.txt"
    targets <- read.delim(targetspath, comment = "#")
    cmp <- systemPipeR::readComp(file = targetspath, format = "matrix", delim = "-")
    
    # Read raw count matrix directly from the working directory
    countMatrixPath <- "countDFeByg.xls"
    countMatrix <- read.delim(countMatrixPath, row.names = 1)
    
    # Display count matrix (reproduced from documented code)
    showDT(countMatrix)
    
    # ==========================================
    # 2. Transform raw counts using exploreDDS
    # ==========================================
    
    exploredds <- exploreDDS(countMatrix, targets, cmp = cmp[[1]], preFilter = NULL, transformationMethod = "rlog")
    saveRDS(exploredds, "exploredds_rlog.rds")
    
    # ==========================================
    # 3. Visualize transformation effects
    # ==========================================
    
    pdf("exploreDDSplot.pdf")
    print(exploreDDSplot(countMatrix, targets, cmp = cmp[[1]], preFilter = NULL, samples = colnames(countMatrix)[1:min(4, ncol(countMatrix))], scattermatrix = TRUE))
    dev.off()
    
    # ==========================================
    # 4. Hierarchical clustering
    # ==========================================
    
    pdf("hclustplot.pdf")
    print(hclustplot(exploredds, method = "spearman"))
    dev.off()
    
    pdf("heatMaplot_samples.pdf")
    print(heatMaplot(exploredds, clust = "samples", plotly = FALSE))
    dev.off()
    
    # ==========================================
    # 5. Differential expression analysis
    # ==========================================
    
    degseqDF <- systemPipeR::run_DESeq2(countDF = countMatrix, targets = targets, cmp = cmp[[1]], independent = FALSE)
    write.csv(degseqDF, "degseqDF.csv", row.names = TRUE)
    
    DEG_list <- systemPipeR::filterDEGs(degDF = degseqDF, filter = c(Fold = 2, FDR = 10))
    saveRDS(DEG_list, "DEG_list.rds")
    
    pdf("heatMaplot_ind.pdf")
    print(heatMaplot(exploredds, clust = "ind", DEGlist = unique(as.character(unlist(DEG_list[[1]])))))
    dev.off()
    
    # ==========================================
    # 6. Dimensionality reduction and visualization
    # ==========================================
    
    pdf("PCAplot.pdf")
    print(PCAplot(exploredds, plotly = FALSE))
    dev.off()
    
    pdf("MDSplot.pdf")
    print(MDSplot(exploredds, plotly = FALSE))
    dev.off()
    
    exploredds_r <- exploreDDS(countMatrix, targets, cmp = cmp[[1]], preFilter = NULL, transformationMethod = "raw")
    saveRDS(exploredds_r, "exploredds_raw.rds")
    
    pdf("GLMplot.pdf")
    print(GLMplot(exploredds_r, plotly = FALSE))
    dev.off()
    
    # Extract first comparison name and first gene for plotting dynamically
    comp_name <- paste(cmp[[1]][1, 1], cmp[[1]][2, 1], sep = "-")
    plot_gene <- rownames(degseqDF)[1]
    
    pdf("MAplot.pdf")
    print(MAplot(degseqDF, comparison = comp_name, filter = c(Fold = 1, FDR = 20), genes = plot_gene))
    dev.off()
    
    pdf("tSNEplot.pdf")
    print(tSNEplot(countMatrix, targets, perplexity = 5))
    dev.off()
    
    pdf("volcanoplot.pdf")
    print(volcanoplot(degseqDF, comparison = comp_name, filter = c(Fold = 1, FDR = 20), genes = plot_gene))
    dev.off()

    writeLines(c(
        '"BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION":',
        paste0('    systemPipeTools: ', as.character(packageVersion('systemPipeTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_exploration_and_visualization.csv versions.yml
    """
}

workflow BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, countDFeByg.xls ] ]

    main:
    BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION.out.objects
    versions = BIOC_SYSTEMPIPETOOLS_RNA_SEQ_EXPLORATION_AND_VISUALIZATION.out.versions
}
