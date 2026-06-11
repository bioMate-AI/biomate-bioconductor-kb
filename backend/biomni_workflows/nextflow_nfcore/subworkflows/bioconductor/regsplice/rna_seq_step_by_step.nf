#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regsplice — rna_seq_step_by_step
// Run the regsplice analysis pipeline step-by-step on RNA-seq count data for maximum flexibility and control over filtering, normalization, and model fitting.
// Input: counts, gene_IDs, n_exons, condition
// Container: quay.io/biocontainers/bioconductor-regsplice:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: regsplice
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create RegspliceData object
//  * 2. [Core Analysis] Filter zero-count exon bins
//  * 3. [Core Analysis] Filter low-count exons
//  * 4. [Core Analysis] Calculate normalization factors
//  * 5. [Core Analysis] Apply voom transformation and weights
//  * 6. [Core Analysis] Initialize RegspliceResults object
//  * 7. [Core Analysis] Fit regularized, null, and full models
//  * 8. [Core Analysis] Calculate likelihood ratio tests
//  * 9. [Visualization & Output] Generate summary table of results

nextflow.enable.dsl = 2

process BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP {
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
    
    # Load required library
    library(regsplice)
    
    # ==========================================
    # 1. Read User Inputs from Working Directory
    # ==========================================
    
    # counts: matrix or data frame of RNA-seq read counts
    # Expected to be a tab-separated file with genes/exons as rows and samples as columns
    counts <- read.table("counts.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE, check.names = FALSE)
    
    # gene_IDs: vector of gene IDs
    gene_IDs <- readLines("gene_IDs.txt")
    
    # n_exons: vector of number of exon bins per gene
    n_exons <- as.integer(readLines("n_exons.txt"))
    
    # condition: vector of experimental conditions
    condition <- readLines("condition.txt")
    
    # ==========================================
    # 2. Run regsplice Step-by-Step Pipeline
    # ==========================================
    
    # Step 2.1: Create RegspliceData object
    rs_data <- RegspliceData(counts, gene_IDs, n_exons, condition)
    
    # Step 2.2: Filter zero-count exon bins
    rs_data <- filterZeros(rs_data)
    
    # Step 2.3: Filter low-count exons
    rs_data <- filterLowCounts(rs_data)
    
    # Step 2.4: Calculate normalization factors
    rs_data <- runNormalization(rs_data)
    
    # Step 2.5: Apply voom transformation and weights
    rs_data <- runVoom(rs_data)
    
    # Export column metadata (including normalization factors and library sizes)
    metadata <- colData(rs_data)
    write.csv(as.data.frame(metadata), "col_data_summary.csv", row.names = TRUE)
    
    # Step 2.6: Initialize RegspliceResults object
    rs_results <- initializeResults(rs_data)
    
    # Step 2.7: Fit regularized, null, and full models
    seed <- 123
    rs_results <- suppressWarnings(fitRegMultiple(rs_results, rs_data, seed = seed))
    rs_results <- fitNullMultiple(rs_results, rs_data, seed = seed)
    rs_results <- fitFullMultiple(rs_results, rs_data, seed = seed)
    
    # Step 2.8: Calculate likelihood ratio tests
    rs_results <- LRTests(rs_results)
    
    # Step 2.9: Generate summary table of results
    # Retrieve all results by setting n = Inf and threshold = 1 (default behavior of summaryTable with n = Inf)
    results_table <- summaryTable(rs_results, n = Inf)
    
    # ==========================================
    # 3. Write Output Files
    # ==========================================
    
    # Save the summary table of results as a CSV file
    write.csv(results_table, "regsplice_results.csv", row.names = FALSE)
    
    # Save the complete results object as an RDS file for downstream analysis
    saveRDS(rs_results, "regsplice_results.rds")

    writeLines(c(
        '"BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP":',
        paste0('    regsplice: ', as.character(packageVersion('regsplice')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_step_by_step.csv versions.yml
    """
}

workflow BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, gene_IDs, n_exons, condition ] ]

    main:
    BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP(ch_input)

    emit:
    tables   = BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP.out.tables
    plots    = BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP.out.plots
    objects  = BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP.out.objects
    versions = BIOC_REGSPLICE_RNA_SEQ_STEP_BY_STEP.out.versions
}
