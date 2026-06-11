#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phantasusLite — phantasus_gct_and_condition_inference
// Import gene expression counts and metadata, infer sample conditions/replicates from structured titles, and export/import the annotated dataset using the GCT for
// Input: counts.csv, coldata.csv
// Container: 1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, phantasusLite
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE {
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
    library(Biobase)
    library(phantasusLite)
    
    # Stage 1: Load input data
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    rownames(counts_df) <- counts_df\$gene_id
    counts_df\$gene_id <- NULL
    counts_matrix <- as.matrix(counts_df)
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Align counts and metadata
    common_samples <- intersect(colnames(counts_matrix), coldata\$sample)
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Stage 2: Prepare ExpressionSet with structured titles for condition inference
    # To demonstrate inferCondition, we construct structured titles (e.g., "Condition_Replicate")
    cond_groups <- split(coldata\$sample, coldata\$condition)
    replicate_indices <- unsplit(lapply(cond_groups, seq_along), coldata\$condition)
    coldata\$title <- paste0(coldata\$condition, "_", replicate_indices)
    
    pheno_data <- AnnotatedDataFrame(coldata)
    es <- ExpressionSet(assayData = counts_matrix, phenoData = pheno_data)
    
    # Stage 3: Infer conditions and replicates
    # This automatically parses es\$title to populate es\$condition and es\$replicate
    es <- inferCondition(es)
    
    # Stage 4: Export to GCT format
    gct_file <- "expression_matrix.gct"
    writeGct(es, gct_file)
    
    # Stage 5: Import back from GCT format to verify integrity
    es_imported <- readGct(gct_file)
    
    # Stage 6: Save outputs
    inferred_metadata <- pData(es_imported)
    write.csv(inferred_metadata, "inferred_metadata.csv", row.names = TRUE)
    
    imported_counts <- exprs(es_imported)
    write.csv(imported_counts, "imported_counts.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE":',
        paste0('    phantasusLite: ', as.character(packageVersion('phantasusLite')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phantasus_gct_and_condition_inference.csv versions.yml
    """
}

workflow BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE(ch_input)

    emit:
    tables   = BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE.out.tables
    plots    = BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE.out.plots
    objects  = BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE.out.objects
    versions = BIOC_PHANTASUSLITE_PHANTASUS_GCT_AND_CONDITION_INFERENCE.out.versions
}
