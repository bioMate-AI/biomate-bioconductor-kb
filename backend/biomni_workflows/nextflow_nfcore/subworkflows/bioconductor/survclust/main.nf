#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: survClust
// survClust is an outcome weighted integrative clustering algorithm used to classify multi-omic sample
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/survClust/inst/doc/survClust_vignette.R
// Upstream  : BiocParallel, survival
// Downstream: none
//
// Install: BiocManager::install("survClust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SURVCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-survclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-survclust:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-survclust:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_survclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_survclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_survclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(survClust)
    library(jsonlite)

    # --- Apply [] ---
    # Key functions: test, adjust
    ---------------------------------------------------------------------
    mut_k4_test <- apply(uvm_dat[[1]],2,function(x) fisher.test(x,k4)$p.value)
    head(sort(p.adjust(mut_k4_test)))
    # --- Function [] ---
    # Key functions: cv_survclust
    ---------------------------------------------------------------------
    #function to do cross validation
    sim_cvrounds<-function(kk){
        this.fold<-3
        fit<-list()
    # --- Apply [] ---
    # Key functions: test, adjust
    ---------------------------------------------------------------------
    mut_k4_test <- apply(uvm_mut_dat[[1]],2,function(x) fisher.test(x,k4)$p.value)
    head(sort(p.adjust(mut_k4_test)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_survclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_survclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_survclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SURVCLUST:", paste0("    survclust: ", packageVersion("survClust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survclust_results.csv
    touch ${prefix}_survclust_output.rds
    echo "BIOC_SURVCLUST:" > versions.yml
    echo "    survclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SURVCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SURVCLUST(ch_input)

    emit:
    results  = BIOC_SURVCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SURVCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SURVCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SURVCLUST.out.versions  // channel: path(versions.yml)
}
