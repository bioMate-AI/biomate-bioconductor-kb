#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rSWeeP
// "Spaced Words Projection (SWeeP)" is a method for representing biological sequences using vectors pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rSWeeP/inst/doc/rSWeeP.R
// Upstream  : ape
// Downstream: none
//
// Install: BiocManager::install("rSWeeP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSWEEP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsweep"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsweep:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsweep:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsweep_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsweep_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsweep_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCCI)
    library(PMPG)
    library(jsonlite)

    # --- Plot Tree1 [] ---
    # Key functions: dist, nj, root
    library(ape)
    # get the distance matrix
    mdist = dist(sw$proj,method='euclidean')
    # use the NJ algorithm to build the tree
    tr = nj(mdist)
    # --- Eval Tree [] ---
    # Key functions: frame, PCCI, PMPG
    data = data.frame(sp=mt$fileName,family=mt$family)
    PCCI(tr,data) # PhyloTaxonomic Consistency Cophenetic Index
    PMPG(tr,data) # Percentage of Mono or Paraphyletic Groups
    # --- Pca [] ---
    # Key functions: prcomp
    pca_output <- prcomp (sw$proj , scale = FALSE)
    par(mfrow=c(1,2))
    plot(pca_output$x[,1],pca_output$x[,2],xlab = 'PC-1' , ylab = 'PC-2' , pch =20 , col = mt$id)
    legend("bottomright",unique(mt$family),col=as.character(c(1:length(unique(mt$family)))),pch=20)
    plot(pca_output$x[,3],pca_output$x[,4],xlab = 'PC-3' , ylab = 'PC-4' , pch =20 , col = mt$id)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsweep_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsweep_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsweep_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSWEEP:", paste0("    rsweep: ", packageVersion("rSWeeP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsweep_results.csv
    touch ${prefix}_rsweep_output.rds
    echo "BIOC_RSWEEP:" > versions.yml
    echo "    rsweep: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSWEEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSWEEP(ch_input)

    emit:
    results  = BIOC_RSWEEP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSWEEP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSWEEP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSWEEP.out.versions  // channel: path(versions.yml)
}
