#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BAGS
// R package providing functions to perform geneset significance analysis over simple cross-sectional d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BAGS/inst/doc/BAGS.R
// Upstream  : Biobase, breastCancerVDX
// Downstream: none
//
// Install: BiocManager::install("BAGS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bags"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bags:2.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bags:2.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bags_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bags_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bags_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataGeneSets)
    library(Gibbs2)
    library(MCMCDataSet)
    library(jsonlite)

    # --- Install Pkg [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("BAGS")
    # --- Data [] ---
    # Key functions: exprs, fData, pData, all
    library(BAGS)
    library(breastCancerVDX)
    library(Biobase)
    data(vdx)
    gene.expr=exprs(vdx)   # Gene expression of the package
    # --- Data [] ---
    # Key functions: DataGeneSets, MCMCDataSet
    data(AnnotationMFGO,package="BAGS")
    data.gene.grps=DataGeneSets(AnnotationMFGO,gene.nams,5)
    phntp.list=list(er.pos,er.neg)
    data.mcmc=MCMCDataSet(gene.expr,data.gene.grps$DataGeneSetsIds,phntp.list)
    # --- Dim [] ---
    # Key functions: unlist, Gibbs2
    noRow=dim(data.mcmc$y.mu)[1]
    noCol=unlist(lapply(phntp.list,length))
    iter=10000
    GrpSzs=data.gene.grps$Size
    YMu=data.mcmc$y.mu

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bags_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bags_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bags_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAGS:", paste0("    bags: ", packageVersion("BAGS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bags_results.csv
    touch ${prefix}_bags_output.rds
    echo "BIOC_BAGS:" > versions.yml
    echo "    bags: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAGS(ch_input)

    emit:
    results  = BIOC_BAGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAGS.out.versions  // channel: path(versions.yml)
}
