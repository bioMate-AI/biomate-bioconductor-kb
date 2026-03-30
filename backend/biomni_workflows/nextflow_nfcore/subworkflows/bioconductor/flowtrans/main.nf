#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowTrans
// Profile maximum likelihood estimation of parameters for flow cytometry data transformations.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowTrans/inst/doc/flowTrans.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowTrans")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWTRANS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowtrans"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowtrans:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowtrans:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowtrans_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowtrans_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowtrans_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowTrans)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: flowTrans
    library(flowTrans)
    data(GvHD)
    transformed<-lapply(as(GvHD[1:4],"list"),function(x)flowTrans(dat=x,fun="mclMultivArcSinh",dims=c("FSC-H","SSC-H"),n2f=FALSE,parameters.only=FALSE));
    # --- Parameters [] ---
    # Key functions: call, extractParams
    parameters<-do.call(rbind,lapply(transformed,function(x)extractParams(x)[[1]]))
    parameters;
    # --- Plot [] ---
    # Key functions: contour
    par(mfrow = c(2, 2))
    plot(GvHD[[2]], c("FSC-H", "SSC-H"), main = "Untransformed sample")
    contour(GvHD[[2]], c("FSC-H","SSC-H"),add=TRUE);
    plot(transformed[[2]]$result, c("FSC-H", "SSC-H"), main = "Transformed sample")
    contour(transformed[[2]]$result,c("FSC-H","SSC-H"),add=TRUE);
    # --- Multivtrans [] ---
    # Key functions: flowTrans
    transformed2<-flowTrans(dat=GvHD[[2]],fun="mclMultivArcSinh",dims=c("FSC-H","SSC-H"),n2f=FALSE,parameters.only=TRUE)
    transformed2

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowtrans_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowtrans_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowtrans_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWTRANS:", paste0("    flowtrans: ", packageVersion("flowTrans"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowtrans_results.csv
    touch ${prefix}_flowtrans_output.rds
    echo "BIOC_FLOWTRANS:" > versions.yml
    echo "    flowtrans: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWTRANS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWTRANS(ch_input)

    emit:
    results  = BIOC_FLOWTRANS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWTRANS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWTRANS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWTRANS.out.versions  // channel: path(versions.yml)
}
