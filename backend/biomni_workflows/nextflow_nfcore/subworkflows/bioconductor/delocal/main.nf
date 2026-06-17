#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DELocal — delocal_fixed_neighborhood
// Identify differentially expressed genes relative to a fixed number of nearest chromosomal neighbors and visualize their neighborhood expression.
// Input: tooth_RNASeq_counts.txt, gene_location.txt
// Container: quay.io/biocontainers/bioconductor-delocal:1.6.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DELocal, SummarizedExperiment, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw count values and define sample conditions
//  * 2. [Input & Preparation] Load gene chromosomal location information
//  * 3. [Visualization & Output] Integrate counts, gene locations, and sample metadata into a SummarizedExperiment object
//  * 4. [Core Analysis] Filter genes by chromosome to reduce runtime
//  * 5. [Core Analysis] Run DELocal to identify DE genes
//  * 6. [Visualization & Output] Plot the expression pattern of a gene and its neighborhood

nextflow.enable.dsl = 2

process BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD {
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
    .bm_deps <- c("DELocal", "dplyr", "ggplot2", "SummarizedExperiment")
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
    
    # Load required libraries
    library(DELocal)
    library(SummarizedExperiment)
    library(dplyr)
    library(ggplot2)
    
    # 1. Read raw count values and define sample conditions
    count_matrix <- as.matrix(read.table(file = "tooth_RNASeq_counts.txt", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
    colData <- data.frame(condition = gsub("\\\\..*", x = colnames(count_matrix), replacement = ""))
    rownames(colData) <- colnames(count_matrix)
    
    # 2. Load gene chromosomal location information
    gene_location <- read.table(file = "gene_location.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    if ("ensembl_gene_id" %in% colnames(gene_location)) {
      rownames(gene_location) <- gene_location\$ensembl_gene_id
    }
    
    # 3. Integrate counts, gene locations, and sample metadata into a SummarizedExperiment object
    smrExpt <- SummarizedExperiment(assays = list(counts = count_matrix), rowData = gene_location, colData = colData)
    
    # 4. Filter genes by chromosome to reduce runtime
    x_genes <- SummarizedExperiment::rowData(smrExpt) %>% 
      as.data.frame() %>% 
      filter(chromosome_name == "X") %>% 
      rownames()
    
    # 5. Run DELocal to identify DE genes
    DELocal_result <- DELocal(pSmrExpt = smrExpt[x_genes,], nearest_neighbours = 5, pDesign = ~ condition, pValue_cut = 0.05)
    
    # Save the tabular results
    write.csv(DELocal_result, "DELocal_results.csv", row.names = TRUE)
    saveRDS(DELocal_result, "DELocal_results.rds")
    
    # 6. Plot the expression pattern of a gene and its neighborhood
    # Use the documented gene ID, or fallback to the top DE gene if the specific ID is not present
    pGene_id_to_plot <- "ENSMUSG00000059401"
    if (!pGene_id_to_plot %in% rownames(smrExpt)) {
      if (nrow(DELocal_result) > 0) {
        pGene_id_to_plot <- rownames(DELocal_result)[1]
      } else {
        pGene_id_to_plot <- rownames(smrExpt)[1]
      }
    }
    
    plot_list <- DELocal::plotNeighbourhood(pSmrExpt = smrExpt, pGene_id = pGene_id_to_plot, pNearest_neighbours = 5, pDesign = ~ condition)
    neighborhood_plot <- plot_list\$plot
    
    # Save the generated plot
    ggsave("neighborhood_plot.pdf", plot = neighborhood_plot, width = 8, height = 6)

    writeLines(c(
        '"BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD":',
        paste0('    DELocal: ', as.character(packageVersion('DELocal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delocal_fixed_neighborhood.csv versions.yml
    """
}

workflow BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tooth_RNASeq_counts.txt, gene_location.txt ] ]

    main:
    BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD(ch_input)

    emit:
    tables   = BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD.out.tables
    plots    = BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD.out.plots
    objects  = BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD.out.objects
    versions = BIOC_DELOCAL_DELOCAL_FIXED_NEIGHBORHOOD.out.versions
}
