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
    .bm_deps <- c("Biobase", "phantasusLite")
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
    library(Biobase)
    library(phantasusLite)
    
    # --- Load input data ---
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
    
    # --- Prepare ExpressionSet with structured titles for ---
    # To demonstrate inferCondition, we construct structured titles (e.g., "Condition_Replicate")
    cond_groups <- split(coldata\$sample, coldata\$condition)
    replicate_indices <- unsplit(lapply(cond_groups, seq_along), coldata\$condition)
    coldata\$title <- paste0(coldata\$condition, "_", replicate_indices)
    
    pheno_data <- AnnotatedDataFrame(coldata)
    es <- ExpressionSet(assayData = counts_matrix, phenoData = pheno_data)
    
    # --- Infer conditions and replicates ---
    # This automatically parses es\$title to populate es\$condition and es\$replicate
    es <- inferCondition(es)
    
    # --- Export to GCT format ---
    gct_file <- "expression_matrix.gct"
    writeGct(es, gct_file)
    
    # --- Import back from GCT format to verify integrity ---
    es_imported <- readGct(gct_file)
    
    # --- Save outputs ---
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
