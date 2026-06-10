#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oncoscanr — ascat_standard_workflow
// Run the complete standard analysis workflow on an ASCAT output file.
// Input: ascat_file.txt
// Container: quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("jsonlite", "oncoscanR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(oncoscanR)
    library(jsonlite)
    
    # Define input file path (must be in the working directory)
    segs.filename <- "ascat_file.txt"
    
    # Verify input file existence
    if (!file.exists(segs.filename)) {
      stop(paste("Required input file missing:", segs.filename))
    }
    
    # Run the automated workflow using workflow_oncoscan.ascat
    dat <- workflow_oncoscan.ascat(segs.filename)
    
    # Convert results to JSON as documented
    json_out <- toJSON(dat, auto_unbox=TRUE, pretty=TRUE)
    
    # Print JSON to console
    cat(json_out, "\n")
    
    # Write outputs to files
    writeLines(json_out, "ascat_workflow_output.json")
    saveRDS(dat, "ascat_workflow_output.rds")
    
    # Extract and save scores as a CSV table
    if (!is.null(dat\$scores)) {
      scores_df <- data.frame(
        Metric = names(dat\$scores),
        Value = unlist(lapply(dat\$scores, as.character)),
        stringsAsFactors = FALSE
      )
      write.csv(scores_df, "ascat_scores.csv", row.names = FALSE)
    }
    
    # Extract and save arm-level alterations as a CSV table
    if (!is.null(dat\$armlevel)) {
      armlevel_list <- lapply(dat\$armlevel, function(x) paste(x, collapse = ", "))
      armlevel_df <- data.frame(
        Alteration_Type = names(armlevel_list),
        Chromosomal_Arms = unlist(armlevel_list),
        stringsAsFactors = FALSE
      )
      write.csv(armlevel_df, "ascat_armlevel_alterations.csv", row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW":
        oncoscanr: \$(Rscript -e 'cat(as.character(packageVersion("oncoscanr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ascat_standard_workflow.csv versions.yml
    """
}

workflow BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ascat_file.txt ] ]

    main:
    BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW.out.tables
    plots    = BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW.out.plots
    objects  = BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW.out.objects
    versions = BIOC_ONCOSCANR_ASCAT_STANDARD_WORKFLOW.out.versions
}
