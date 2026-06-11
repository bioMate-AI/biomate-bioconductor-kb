#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosdef — vector_enrichment
// Run functional enrichment analysis using simple vectors of differentially expressed and background gene identifiers.
// Input: res_macrophage_IFNg_vs_naive
// Container: quay.io/biocontainers/bioconductor-mosdef:1.6.0--r45hdfd78af_0
// R packages: DESeq2, mosdef, org.Hs.eg.db, topGO
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, mosdef, org.Hs.eg.db, topGO
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert DESeqResults to a data frame
//  * 2. [Core Analysis] Extract vectors of differentially expressed genes and background genes
//  * 3. [Core Analysis] Run enrichment analysis using the vector-based API

nextflow.enable.dsl = 2

process BIOC_MOSDEF_VECTOR_ENRICHMENT {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DESeq2", "mosdef", "org.Hs.eg.db", "topGO")
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
    library(mosdef)
    library(DESeq2)
    library(org.Hs.eg.db)
    library(topGO)
    
    # Read user input
    input_file <- "res_macrophage_IFNg_vs_naive"
    if (!file.exists(input_file) && file.exists(paste0(input_file, ".rds"))) {
      input_file <- paste0(input_file, ".rds")
    }
    
    if (!file.exists(input_file)) {
      stop("Required input file 'res_macrophage_IFNg_vs_naive' (or .rds) not found in the working directory.")
    }
    
    res_macrophage_IFNg_vs_naive <- readRDS(input_file)
    
    # 1. Convert DESeqResults to a data frame and subset
    res_subset <- deresult_to_df(res_macrophage_IFNg_vs_naive)[1:100, ] 
    
    # 2. Extract vectors of differentially expressed genes and background genes
    myde <- res_subset\$id
    myassayed <- rownames(res_macrophage_IFNg_vs_naive)
    
    # 3. Run enrichment analysis using the vector-based API
    res_enrich_macrophage_topGO_vec <- run_topGO(
      de_genes = myde,
      bg_genes = myassayed,
      mapping = "org.Hs.eg.db",
      gene_id = "ensembl"
    )
    
    # Write outputs
    write.csv(res_enrich_macrophage_topGO_vec, "res_enrich_macrophage_topGO_vec.csv", row.names = FALSE)
    saveRDS(res_enrich_macrophage_topGO_vec, "res_enrich_macrophage_topGO_vec.rds")

    writeLines(c(
        '"BIOC_MOSDEF_VECTOR_ENRICHMENT":',
        paste0('    mosdef: ', as.character(packageVersion('mosdef')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vector_enrichment.csv versions.yml
    """
}

workflow BIOC_MOSDEF_VECTOR_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ res_macrophage_IFNg_vs_naive ] ]

    main:
    BIOC_MOSDEF_VECTOR_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MOSDEF_VECTOR_ENRICHMENT.out.tables
    plots    = BIOC_MOSDEF_VECTOR_ENRICHMENT.out.plots
    objects  = BIOC_MOSDEF_VECTOR_ENRICHMENT.out.objects
    versions = BIOC_MOSDEF_VECTOR_ENRICHMENT.out.versions
}
