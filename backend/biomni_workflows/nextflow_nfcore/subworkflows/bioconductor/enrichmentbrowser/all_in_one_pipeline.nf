#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: enrichmentbrowser — all_in_one_pipeline
// Run the complete standardized enrichment analysis pipeline using the all-in-one wrapper function.
// Input: exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt, hsa.grn
// Container: quay.io/biocontainers/bioconductor-enrichmentbrowser:2.40.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-enrichmentbrowser:2.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("EnrichmentBrowser")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(EnrichmentBrowser)
    
    # Define input file paths
    exprs.file <- "exprs.tab"
    cdat.file <- "colData.tab"
    rdat.file <- "rowData.tab"
    gmt.file <- "hsa_kegg_gs.gmt"
    grn.file <- "hsa.grn"
    
    # Set default output directory to current working directory
    configEBrowser(key = "OUTDIR.DEFAULT", value = getwd())
    
    # Load gene sets from GMT file
    hsa.gs <- getGenesets(gmt.file)
    
    # Load gene regulatory network
    hsa.grn <- as.matrix(read.delim(grn.file, header = TRUE, stringsAsFactors = FALSE))
    
    # Execute the complete standardized enrichment analysis pipeline
    res <- ebrowser(
      meth = c("ora", "ggea"),
      exprs = exprs.file,
      cdat = cdat.file,
      rdat = rdat.file,
      org = "hsa",
      gs = hsa.gs,
      grn = hsa.grn,
      comb = TRUE,
      nr.show = 5
    )
    
    # Save the complete results object
    saveRDS(res, "ebrowser_results.rds")
    
    # Export rankings to CSV files
    if (is.list(res)) {
      for (method in names(res)) {
        tryCatch({
          ranking <- gsRanking(res[[method]], signif.only = FALSE)
          write.csv(as.data.frame(ranking), file = paste0(method, "_ranking.csv"), row.names = FALSE)
        }, error = function(e) {
          message("Could not write ranking for ", method, ": ", e\$message)
        })
      }
    } else {
      tryCatch({
        ranking <- gsRanking(res, signif.only = FALSE)
        write.csv(as.data.frame(ranking), file = "ebrowser_ranking.csv", row.names = FALSE)
      }, error = function(e) {
        message("Could not write ranking: ", e\$message)
      })
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE":
        enrichmentbrowser: \$(Rscript -e 'cat(as.character(packageVersion("enrichmentbrowser")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_in_one_pipeline.csv versions.yml
    """
}

workflow BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs.tab, colData.tab, rowData.tab, hsa_kegg_gs.gmt, hsa.grn ] ]

    main:
    BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE.out.tables
    plots    = BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE.out.plots
    objects  = BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE.out.objects
    versions = BIOC_ENRICHMENTBROWSER_ALL_IN_ONE_PIPELINE.out.versions
}
