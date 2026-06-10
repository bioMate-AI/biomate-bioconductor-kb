#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: apalyzer — gene_expression_analysis
// Assess gene expression changes using RNA-seq reads mapped to coding sequences (CDS).
// Input: txdb, IDDB, flsall
// Container: quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0"

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
    .bm_deps <- c("APAlyzer", "AnnotationDbi", "GenomicFeatures")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(APAlyzer)
    library(GenomicFeatures)
    library(AnnotationDbi)
    
    # Read user inputs from the working directory
    if (file.exists("txdb.rds")) {
      txdb <- readRDS("txdb.rds")
    } else if (file.exists("txdb.sqlite")) {
      txdb <- loadDb("txdb.sqlite")
    } else {
      stop("Error: txdb input file not found (expected txdb.rds or txdb.sqlite in the working directory).")
    }
    
    if (file.exists("IDDB.rds")) {
      IDDB <- readRDS("IDDB.rds")
    } else {
      stop("Error: IDDB input file not found (expected IDDB.rds in the working directory).")
    }
    
    if (file.exists("flsall.rds")) {
      flsall <- readRDS("flsall.rds")
    } else {
      stop("Error: flsall input file not found (expected flsall.rds in the working directory).")
    }
    
    # Stage 1: Build coding region references using REFCDS
    message("Building coding region references...")
    CDSdbraw=REFCDS(txdb,IDDB)
    
    # Stage 2: Calculate gene expression using GENEXP_CDS
    message("Calculating gene expression using coding regions...")
    DFGENEraw=GENEXP_CDS(CDSdbraw, flsall, Strandtype="forward")
    
    # Write named output files
    message("Writing output files...")
    saveRDS(CDSdbraw, file = "CDSdbraw.rds")
    saveRDS(DFGENEraw, file = "DFGENEraw.rds")
    write.csv(DFGENEraw, file = "DFGENEraw.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS":
        apalyzer: \$(Rscript -e 'cat(as.character(packageVersion("apalyzer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_expression_analysis.csv versions.yml
    """
}

workflow BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ txdb, IDDB, flsall ] ]

    main:
    BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_APALYZER_GENE_EXPRESSION_ANALYSIS.out.versions
}
