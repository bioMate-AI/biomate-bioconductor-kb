#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geva — detailed_geva_pipeline
// Perform a detailed, step-by-step Gene Expression Variation Analysis (GEVA) from input files to final gene classification, allowing fine-tuning of each intermedi
// Input: cond_A_2h.txt, cond_B_2h.txt, cond_C_2h.txt, cond_A_4h.txt, cond_B_4h.txt, cond_C_4h.txt
// Container: quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEVA_DETAILED_GEVA_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("geva")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required Bioconductor package
    library(geva)
    
    # 1. Read input files
    filenms <- c("cond_A_2h.txt", "cond_B_2h.txt", "cond_C_2h.txt",
                 "cond_A_4h.txt", "cond_B_4h.txt", "cond_C_4h.txt")
    ginput <- geva.read.tables(filenms)
    
    # 2. Correct numeric tables
    ginput <- geva.input.correct(ginput)
    
    # 3. Filter out insignificant rows
    ginput <- geva.input.filter(ginput, p.value.cutoff = 0.05)
    
    # 4. Rename row names and resolve duplicates
    ginput <- geva.input.rename.rows(ginput,
                                     attr.column = "Symbol")
    
    # 5. Summarize logFC and variation
    gsummary <- geva.summarize(ginput)
    
    # Save GEVASummary plot
    pdf("gsummary_plot.pdf", width = 9, height = 6)
    plot(gsummary)
    dev.off()
    
    # 6. Calculate SV-space quantiles
    gquants <- geva.quantiles(gsummary)
    
    # Save GEVAQuantiles plot
    pdf("gquants_plot.pdf", width = 9, height = 6)
    plot(gquants)
    dev.off()
    
    # 7. Perform cluster analysis
    gcluster <- geva.cluster(gsummary,
                             cluster.method="hierarchical",
                             resolution=0.3)
    
    # Save GEVACluster plot
    pdf("gcluster_plot.pdf", width = 9, height = 6)
    plot(gcluster)
    dev.off()
    
    # 8. Combine intermediate results
    ggroupedsummary <- gsummary
    groupsets(ggroupedsummary) <- gquants
    groupsets(ggroupedsummary) <- gcluster
    
    # Save GEVAGroupedSummary plot
    pdf("ggroupedsummary_plot.pdf", width = 9, height = 6)
    plot(ggroupedsummary)
    dev.off()
    
    # 9. Finalize classifications
    gresults <- geva.finalize(ggroupedsummary)
    
    # Save GEVAResults plot
    pdf("gresults_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()
    
    # Extract and save the final classifications table
    res_table <- results.table(gresults)
    write.csv(res_table, "geva_results_table.csv", row.names = TRUE)
    
    # Print the last 10 rows of the results table to console
    print(tail(res_table, 10))
    
    # 10. Extract top relevant genes
    dtgens <- top.genes(gresults, add.cols = "Symbol")
    write.csv(dtgens, "geva_top_genes.csv", row.names = TRUE)
    
    # Save the final results object as an RDS file
    saveRDS(gresults, "geva_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GEVA_DETAILED_GEVA_PIPELINE":
        geva: \$(Rscript -e 'cat(as.character(packageVersion("geva")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detailed_geva_pipeline.csv versions.yml
    """
}

workflow BIOC_GEVA_DETAILED_GEVA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cond_A_2h.txt, cond_B_2h.txt, cond_C_2h.txt, cond_A_4h.txt, cond_B_4h.txt, cond_C_4h.txt ] ]

    main:
    BIOC_GEVA_DETAILED_GEVA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.tables
    plots    = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.plots
    objects  = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.objects
    versions = BIOC_GEVA_DETAILED_GEVA_PIPELINE.out.versions
}
