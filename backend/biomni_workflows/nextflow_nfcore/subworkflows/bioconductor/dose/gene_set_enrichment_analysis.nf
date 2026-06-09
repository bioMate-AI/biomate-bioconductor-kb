#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DOSE — gene_set_enrichment_analysis
// Perform gene set enrichment analysis using disease ontology.
// Input: ranked_gene_list.txt
// Container: quay.io/biocontainers/bioconductor-dose:4.4.0--r45hdfd78af_0
// Requires: DOSE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the DOSE package
//  * 2. [Core Analysis] Run gene set enrichment analysis using gseDO, gseDGN, or gseNCG

nextflow.enable.dsl = 2

process BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # 1. Load the DOSE package
    library(DOSE)
    
    # 2. Read the user input file
    # The file 'ranked_gene_list.txt' is expected to contain Entrez gene IDs and their fold changes.
    # We read it, construct a named numeric vector, and sort it in decreasing order.
    input_file <- "ranked_gene_list.txt"
    
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the table. We handle potential headers by checking the first row.
    gene_data <- read.table(input_file, header = FALSE, stringsAsFactors = FALSE)
    
    # If the first row contains column names (non-numeric in the second column), re-read with header=TRUE
    if (!is.numeric(gene_data[1, 2]) && nrow(gene_data) > 1) {
      gene_data <- read.table(input_file, header = TRUE, stringsAsFactors = FALSE)
    }
    
    # Construct the named numeric vector
    gene_list <- as.numeric(gene_data[, 2])
    names(gene_list) <- as.character(gene_data[, 1])
    
    # Remove any NA values that might have been introduced
    valid_indices <- !is.na(gene_list) & !is.na(names(gene_list)) & names(gene_list) != ""
    gene_list <- gene_list[valid_indices]
    
    # GSEA requires the gene list to be sorted in decreasing order
    gene_list <- sort(gene_list, decreasing = TRUE)
    
    # 3. Run gene set enrichment analysis using gseDO
    # We use gseDO as the primary disease ontology GSEA function.
    gse_res <- gseDO(
      geneList = gene_list,
      pvalueCutoff = 0.05,
      pAdjustMethod = "BH"
    )
    
    # 4. Write named output files for the meaningful results
    # Save the complete GSEA result object as an RDS file
    saveRDS(gse_res, file = "gse_do_results.rds")
    
    # Save the result summary table as a CSV file
    gse_res_df <- as.data.frame(gse_res)
    write.csv(gse_res_df, file = "gse_do_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS":',
        paste0('    DOSE: ', as.character(packageVersion('DOSE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ranked_gene_list.txt ] ]

    main:
    BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_DOSE_GENE_SET_ENRICHMENT_ANALYSIS.out.versions
}
