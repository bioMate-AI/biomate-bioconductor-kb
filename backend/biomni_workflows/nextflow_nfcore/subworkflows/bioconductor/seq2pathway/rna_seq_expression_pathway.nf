#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seq2pathway — rna_seq_expression_pathway
// Perform pathway enrichment analysis directly on a gene expression matrix (RNA-seq or microarray) without genomic region mapping.
// Input: dat_RNA, MsigDB_C5
// Container: quay.io/biocontainers/bioconductor-seq2pathway:1.34.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: seq2pathway
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run pathway enrichment analysis directly using gene2pathway_test on the expression matrix

nextflow.enable.dsl = 2

process BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("seq2pathway", "GSA")
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
    library(seq2pathway)
    library(GSA)
    
    # Verify existence of the required input files in the working directory
    if (!file.exists("dat_RNA.rds")) {
      stop("Error: Required input file 'dat_RNA.rds' is missing from the working directory.")
    }
    if (!file.exists("MsigDB_C5.rds")) {
      stop("Error: Required input file 'MsigDB_C5.rds' is missing from the working directory.")
    }
    
    # Read the user input files
    dat_RNA <- readRDS("dat_RNA.rds")
    MsigDB_C5 <- readRDS("MsigDB_C5.rds")
    
    # Execute the pathway enrichment analysis using the exact documented function call
    dat_gene2path_RNA <- gene2pathway_test(dat=dat_RNA, DataBase=MsigDB_C5,
                 EmpiricalTest=FALSE, alpha=5, logCheck=FALSE, method="FAIME", na.rm=TRUE)
    
    # Save the complete result object as an RDS file
    saveRDS(dat_gene2path_RNA, file = "dat_gene2path_RNA.rds")
    
    # Robustly export meaningful results to CSV tables
    # The output is typically a list containing 'gene2pathway_result.2' (FAIME) and 'gene2pathway_result.FET' (Fisher's Exact Test)
    if (!is.null(dat_gene2path_RNA\$gene2pathway_result.2)) {
      faime_res <- dat_gene2path_RNA\$gene2pathway_result.2
      if (is.data.frame(faime_res)) {
        write.csv(faime_res, "gene2pathway_FAIME_results.csv", row.names = TRUE)
      } else if (is.list(faime_res)) {
        for (name in names(faime_res)) {
          write.csv(faime_res[[name]], paste0("gene2pathway_FAIME_results_", name, ".csv"), row.names = TRUE)
        }
      }
    }
    
    if (!is.null(dat_gene2path_RNA\$gene2pathway_result.FET)) {
      fet_res <- dat_gene2path_RNA\$gene2pathway_result.FET
      if (is.data.frame(fet_res)) {
        write.csv(fet_res, "gene2pathway_FET_results.csv", row.names = TRUE)
      } else if (is.list(fet_res)) {
        for (name in names(fet_res)) {
          write.csv(fet_res[[name]], paste0("gene2pathway_FET_results_", name, ".csv"), row.names = TRUE)
        }
      }
    }
    
    cat("Pipeline completed successfully. Results saved to working directory.\n")

    writeLines(c(
        '"BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY":',
        paste0('    seq2pathway: ', as.character(packageVersion('seq2pathway')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_expression_pathway.csv versions.yml
    """
}

workflow BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat_RNA, MsigDB_C5 ] ]

    main:
    BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY(ch_input)

    emit:
    tables   = BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY.out.tables
    plots    = BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY.out.plots
    objects  = BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY.out.objects
    versions = BIOC_SEQ2PATHWAY_RNA_SEQ_EXPRESSION_PATHWAY.out.versions
}
