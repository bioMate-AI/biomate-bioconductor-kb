#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — sequencing_discrete_enrichment
// Convert genomic coordinates (BED format) to coordinate-free YAME format and test for enrichment against a knowledgebase.
// Input: input_cpgs.bed, cpg_nocontig.cr
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("knowYourCG")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(knowYourCG)
    
    # Define input files from the working directory
    bed_file <- "input_cpgs.bed"
    ref_cr <- "cpg_nocontig.cr"
    out_file <- "input_cpgs.cg"
    
    # 1. Convert BED file to YAME-compressed binary vector using bedToCg()
    # Wrapping in tryCatch to handle potential missing system dependencies (yame/bedtools)
    tryCatch({
      bedToCg(bed_file, ref_cr, out_file)
    }, error = function(e) {
      message("Error running bedToCg: ", e\$message)
    })
    
    # Prepare the knowledgebase by downloading from Zenodo
    temp_dir <- tempdir()
    knowledgebase <- file.path(temp_dir, "ChromHMM.20220414.cm")
    knowledgebase_url <- "https://zenodo.org/records/18175656/files/ChromHMM.20220414.cm"
    download.file(knowledgebase_url, destfile = knowledgebase, quiet = TRUE)
    
    # Set the query to the generated YAME file
    query <- out_file
    
    # 2. Run enrichment testing using testEnrichment()
    res <- NULL
    tryCatch({
      res = testEnrichment(query, knowledgebase)
    }, error = function(e) {
      message("Error running testEnrichment: ", e\$message)
    })
    
    # 3. Plot results using KYCG_plotDot() and save outputs
    if (!is.null(res)) {
      # Save tabular results
      write.csv(res, "enrichment_results.csv", row.names = FALSE)
      saveRDS(res, "enrichment_results.rds")
      
      # Generate and save the dot plot
      pdf("enrichment_dotplot.pdf", width = 8, height = 6)
      tryCatch({
        KYCG_plotDot(res, short_label = TRUE)
      }, error = function(e) {
        message("Error plotting results: ", e\$message)
      })
      dev.off()
    } else {
      message("Pipeline completed, but no enrichment results were generated to plot or save.")
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT":
        knowyourcg: \$(Rscript -e 'cat(as.character(packageVersion("knowyourcg")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequencing_discrete_enrichment.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_cpgs.bed, cpg_nocontig.cr ] ]

    main:
    BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.tables
    plots    = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.plots
    objects  = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.objects
    versions = BIOC_KNOWYOURCG_SEQUENCING_DISCRETE_ENRICHMENT.out.versions
}
