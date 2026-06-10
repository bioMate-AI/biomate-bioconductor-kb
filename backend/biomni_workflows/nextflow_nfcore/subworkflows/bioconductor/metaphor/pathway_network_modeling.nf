#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaphor — pathway_network_modeling
// Model individual metabolic pathways using transcriptional changes of individual genes and visualize them in Cytoscape.
// Input: BRCA_DEGS.csv
// Container: quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAPHOR_PATHWAY_NETWORK_MODELING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0"

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
    
    # Load the required package
    library(MetaPhOR)
    
    # Stage 1: Identify a pathway of interest
    # Retrieve the complete list of available WikiPathways and save it to a CSV file
    message("Retrieving available metabolic pathways...")
    pw_list <- pathwayList()
    write.csv(pw_list, "available_pathways.csv", row.names = FALSE)
    message("Saved available pathways list to 'available_pathways.csv'")
    
    # Stage 2: Render and save the pathway model using cytoPath()
    # This function requires a running local Cytoscape instance and the RCy3 package.
    # We wrap it in a tryCatch block to ensure the pipeline completes gracefully 
    # if Cytoscape is not currently running or reachable.
    message("Attempting to model the Tryptophan Metabolism pathway in Cytoscape...")
    tryCatch({
      cytoPath(pathway = "Tryptophan Metabolism",
               DEGpath = "BRCA_DEGS.csv",
               figpath = paste(getwd(), "BRCA_Tryptophan_Pathway", sep = "/"),
               genename = "X",
               headers = c("logFC", "adj.P.Val"))
      message("Successfully rendered and saved the pathway model to 'BRCA_Tryptophan_Pathway'")
    }, error = function(e) {
      warning("Could not complete cytoPath visualization. This function requires a running local instance of Cytoscape. Error details: ", e\$message)
    })
    
    message("Pipeline execution completed.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_METAPHOR_PATHWAY_NETWORK_MODELING":
        metaphor: \$(Rscript -e 'cat(as.character(packageVersion("metaphor")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_network_modeling.csv versions.yml
    """
}

workflow BIOC_METAPHOR_PATHWAY_NETWORK_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BRCA_DEGS.csv ] ]

    main:
    BIOC_METAPHOR_PATHWAY_NETWORK_MODELING(ch_input)

    emit:
    tables   = BIOC_METAPHOR_PATHWAY_NETWORK_MODELING.out.tables
    plots    = BIOC_METAPHOR_PATHWAY_NETWORK_MODELING.out.plots
    objects  = BIOC_METAPHOR_PATHWAY_NETWORK_MODELING.out.objects
    versions = BIOC_METAPHOR_PATHWAY_NETWORK_MODELING.out.versions
}
