#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DELocal — delocal_dynamic_neighborhood
// Identify differentially expressed genes relative to dynamic chromosomal neighborhoods such as Topologically Associating Domains (TADs).
// Input: tooth_RNASeq_counts.txt, Mouse_TAD_boundaries.csv
// Container: quay.io/biocontainers/bioconductor-delocal:1.6.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DELocal, SummarizedExperiment, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw count values and define sample conditions
//  * 2. [Input & Preparation] Load dynamic gene neighborhood boundaries (TADs) and rename columns to neighbors_start and neighbors_end
//  * 3. [Visualization & Output] Integrate counts, dynamic locations, and sample metadata into a SummarizedExperiment object
//  * 4. [Core Analysis] Run DELocal with dynamic neighborhood boundaries

nextflow.enable.dsl = 2

process BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD {
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
    library(DELocal)
    library(dplyr)
    
    # 1. Read raw count values and define sample conditions
    count_matrix <- as.matrix(read.table(
      file = "tooth_RNASeq_counts.txt", 
      header = TRUE, 
      sep = "\t", 
      row.names = 1, 
      check.names = FALSE
    ))
    
    colData <- data.frame(
      condition = gsub("\\\\..*", x = colnames(count_matrix), replacement = ""),
      row.names = colnames(count_matrix)
    )
    
    # 2. Load dynamic gene neighborhood boundaries (TADs) and rename columns
    gene_location_dynamicNeighbourhood <- read.csv("Mouse_TAD_boundaries.csv")
    rownames(gene_location_dynamicNeighbourhood) <- gene_location_dynamicNeighbourhood\$ensembl_gene_id
    colnames(gene_location_dynamicNeighbourhood)[4:5] <- c("neighbors_start", "neighbors_end")
    
    # 3. Integrate counts, dynamic locations, and sample metadata into a SummarizedExperiment object
    common_genes <- intersect(rownames(count_matrix), rownames(gene_location_dynamicNeighbourhood))
    
    smrExpt_dynamicNeighbour <- SummarizedExperiment::SummarizedExperiment(
      assays = list(counts = count_matrix[common_genes, ]),
      rowData = gene_location_dynamicNeighbourhood[common_genes, ],
      colData = colData
    )
    
    # Define x_genes (genes on chromosome X) to run the analysis on a subset as in the vignette
    x_genes <- SummarizedExperiment::rowData(smrExpt_dynamicNeighbour) %>%
      as.data.frame() %>%
      filter(chromosome_name == "X") %>%
      rownames()
    
    # 4. Run DELocal with dynamic neighborhood boundaries
    DELocal_result_tad <- DELocal(
      pSmrExpt = smrExpt_dynamicNeighbour[x_genes, ],
      nearest_neighbours = 5,
      pDesign = ~ condition,
      pValue_cut = 0.05,
      pLogFold_cut = 0
    )
    
    # 5. Write outputs to files
    write.csv(DELocal_result_tad, "DELocal_result_tad.csv", row.names = TRUE)
    saveRDS(smrExpt_dynamicNeighbour, "smrExpt_dynamicNeighbour.rds")
    saveRDS(DELocal_result_tad, "DELocal_result_tad.rds")

    writeLines(c(
        '"BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD":',
        paste0('    DELocal: ', as.character(packageVersion('DELocal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delocal_dynamic_neighborhood.csv versions.yml
    """
}

workflow BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tooth_RNASeq_counts.txt, Mouse_TAD_boundaries.csv ] ]

    main:
    BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD(ch_input)

    emit:
    tables   = BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD.out.tables
    plots    = BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD.out.plots
    objects  = BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD.out.objects
    versions = BIOC_DELOCAL_DELOCAL_DYNAMIC_NEIGHBORHOOD.out.versions
}
