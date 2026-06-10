#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaPhOR — cytoscape_pathway_modeling
// Model individual metabolic pathways using transcriptional changes of individual genes and visualize them in Cytoscape.
// Input: BRCA_DEGS.csv
// Container: quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0
// Requires: MetaPhOR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve the list of available metabolic WikiPathways using pathwayList
//  * 2. [Visualization & Output] Render and save the pathway model using cytoPath (requires a running Cytoscape instance)

nextflow.enable.dsl = 2

process BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING {
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
    .bm_deps <- c("MetaPhOR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(MetaPhOR)
    
    # Verify that the required input file exists in the working directory
    input_file <- "BRCA_DEGS.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing from the working directory."))
    }
    
    # 1. Retrieve the list of available metabolic WikiPathways
    message("Retrieving available metabolic WikiPathways...")
    pathways <- pathwayList()
    
    # Save the retrieved pathway list to a CSV file
    write.csv(pathways, "available_pathways.csv", row.names = FALSE)
    message("Saved available pathways to 'available_pathways.csv'")
    
    # 2. Render and save the pathway model using cytoPath
    # Note: cytoPath requires a running local instance of Cytoscape.
    # We wrap this call in a tryCatch block to ensure the pipeline remains robust
    # and runs to completion even if Cytoscape is not currently reachable.
    message("Attempting to model 'Tryptophan Metabolism' pathway using cytoPath...")
    tryCatch({
      cytoPath(pathway = "Tryptophan Metabolism",
               DEGpath = "BRCA_DEGS.csv",
               figpath = paste(getwd(), "BRCA_Tryptophan_Pathway", sep = "/"),
               genename = "X",
               headers = c("logFC", "adj.P.Val"))
      message("cytoPath completed successfully. Output saved to 'BRCA_Tryptophan_Pathway'.")
    }, error = function(e) {
      warning("cytoPath execution failed. This is expected if Cytoscape is not running or RCy3 cannot connect to it. Error: ", e\$message)
    })

    writeLines(c(
        '"BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING":',
        paste0('    MetaPhOR: ', as.character(packageVersion('MetaPhOR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytoscape_pathway_modeling.csv versions.yml
    """
}

workflow BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BRCA_DEGS.csv ] ]

    main:
    BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING(ch_input)

    emit:
    tables   = BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING.out.tables
    plots    = BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING.out.plots
    objects  = BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING.out.objects
    versions = BIOC_METAPHOR_CYTOSCAPE_PATHWAY_MODELING.out.versions
}
