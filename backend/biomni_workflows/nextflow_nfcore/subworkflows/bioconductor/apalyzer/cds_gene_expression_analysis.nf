#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: APAlyzer — cds_gene_expression_analysis
// Calculate gene expression changes using RNA-seq reads mapped to coding regions (CDS) to compare with APA dynamics.
// Input: flsall, mm9.chr19.refGene.R.DB
// Container: quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0
// R packages: APAlyzer, GenomicFeatures, org.Mm.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: APAlyzer, GenomicFeatures, org.Mm.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the TxDb and OrgDb annotations
//  * 2. [Input & Preparation] Build coding region references using REFCDS
//  * 3. [Core Analysis] Calculate gene expression using GENEXP_CDS

nextflow.enable.dsl = 2

process BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS {
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
    .bm_deps <- c("APAlyzer", "GenomicFeatures", "org.Mm.eg.db")
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
    suppressMessages(library("APAlyzer"))
    suppressMessages(library("GenomicFeatures"))
    suppressMessages(library("org.Mm.eg.db"))
    
    # 1. Prepare flsall from BAM files in the working directory
    bam_files <- list.files(path = ".", pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(bam_files) == 0) {
      stop("Error: No BAM files found in the working directory.")
    }
    flsall <- bam_files
    names(flsall) <- gsub("\\\\.bam\$", "", basename(bam_files))
    
    # 2. Load the TxDb database file from the working directory
    extpath = "mm9.chr19.refGene.R.DB"
    if (!file.exists(extpath)) {
      stop("Error: TxDb database file 'mm9.chr19.refGene.R.DB' not found in the working directory.")
    }
    txdb=loadDb(extpath, packageName='GenomicFeatures')
    
    # 3. Build coding region references
    IDDB = org.Mm.eg.db
    CDSdbraw=REFCDS(txdb,IDDB)
    
    # 4. Calculate gene expression using GENEXP_CDS
    DFGENEraw=GENEXP_CDS(CDSdbraw, flsall, Strandtype="forward")
    
    # 5. Save outputs
    write.csv(DFGENEraw, file = "CDS_gene_expression.csv", row.names = FALSE)
    saveRDS(DFGENEraw, file = "CDS_gene_expression.rds")

    writeLines(c(
        '"BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS":',
        paste0('    APAlyzer: ', as.character(packageVersion('APAlyzer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cds_gene_expression_analysis.csv versions.yml
    """
}

workflow BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flsall, mm9.chr19.refGene.R.DB ] ]

    main:
    BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_APALYZER_CDS_GENE_EXPRESSION_ANALYSIS.out.versions
}
