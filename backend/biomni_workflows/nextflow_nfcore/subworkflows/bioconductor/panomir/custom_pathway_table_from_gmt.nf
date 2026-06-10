#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: panomir — custom_pathway_table_from_gmt
// Create a customized pathway-gene association table from an external GMT file or GeneSetCollection.
// Input: pathways.gmt
// Container: quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("GSEABase", "PanomiR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(GSEABase)
    library(PanomiR)
    
    # Define input file path
    gmt_file <- "pathways.gmt"
    
    # Check if input file exists
    if (!file.exists(gmt_file)) {
      stop(paste("Required input file", gmt_file, "does not exist in the working directory."))
    }
    
    # 1. Read GMT file into a GeneSetCollection using GSEABase::getGmt
    yourGeneSetCollection <- getGmt(gmt_file)
    
    # 2. Convert the GeneSetCollection to a pathway-gene association table using tableFromGSC
    newPathGeneTable      <- tableFromGSC(yourGeneSetCollection)
    
    # Write the meaningful results to output files
    write.csv(newPathGeneTable, "newPathGeneTable.csv", row.names = FALSE)
    saveRDS(newPathGeneTable, "newPathGeneTable.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT":
        panomir: \$(Rscript -e 'cat(as.character(packageVersion("panomir")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_pathway_table_from_gmt.csv versions.yml
    """
}

workflow BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pathways.gmt ] ]

    main:
    BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT(ch_input)

    emit:
    tables   = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.tables
    plots    = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.plots
    objects  = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.objects
    versions = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_FROM_GMT.out.versions
}
