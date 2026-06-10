#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: opencyto — interactive_gating_prototyping
// Interactively prototype and test individual gating methods on a GatingSet without writing a complete CSV template.
// Input: gs
// Container: quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0"

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
    .bm_deps <- c("flowWorkspace", "openCyto")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(openCyto)
    library(flowWorkspace)
    
    # 1. Load the pre-loaded, compensated, and transformed GatingSet object
    # In flowWorkspace, GatingSets are stored and loaded as directories.
    gs <- load_gs("gs")
    
    # 2. Add a new population using gs_add_gating_method by specifying gating parameters directly
    gs_add_gating_method(gs, alias = "non-activated cd4",
                             pop = "--",
                             parent = "cd4",
                             dims = "CD38,HLA",
                             gating_method = "mindensity")
    
    # Save the GatingSet with the newly added gate
    save_gs(gs, path = "gs_with_prototype", overwrite = TRUE)
    
    # 3. Visualize the updated gating tree to inspect the results
    pdf("plot_after_add.pdf")
    plot(gs[[1]])
    dev.off()
    
    # 4. Remove the last added population using gs_remove_gating_method
    gs_remove_gating_method(gs)
    
    # 5. Visualize the gating tree again to confirm removal
    pdf("plot_after_remove.pdf")
    plot(gs[[1]])
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING":
        opencyto: \$(Rscript -e 'cat(as.character(packageVersion("opencyto")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_gating_prototyping.csv versions.yml
    """
}

workflow BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gs ] ]

    main:
    BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING(ch_input)

    emit:
    tables   = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.tables
    plots    = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.plots
    objects  = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.objects
    versions = BIOC_OPENCYTO_INTERACTIVE_GATING_PROTOTYPING.out.versions
}
