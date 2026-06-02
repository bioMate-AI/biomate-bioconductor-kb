#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: immunoClust
// immunoClust is a model based clustering approach for Flow Cytometry samples. The cell-events of sing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/immunoClust/inst/doc/immunoClust.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("immunoClust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IMMUNOCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-immunoclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-immunoclust:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-immunoclust:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_immunoclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_immunoclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_immunoclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(immunoClust)
    library(jsonlite)


    # --- Stage1data [] ---
    # Key functions: cell.process
    data(dat.fcs)
    dat.fcs
    pars=c("FSC-A","SSC-A","FITC-A","PE-A","APC-A","APC-Cy7-A","Pacific Blue-A")
    res.fcs <- cell.process(dat.fcs, parameters=pars)

    # --- Stage1summary [] ---
    # Key functions: summary, cell.process
    summary(res.fcs)
    res2 <- cell.process(dat.fcs, bias=0.25)
    summary(res2)

    # --- Stage1trans [] ---
    # Key functions: trans.ApplyToData, splom
    dat.transformed <- trans.ApplyToData(res.fcs, dat.fcs)
    splom(res.fcs, dat.transformed, N=1000)

    # --- Stage1plot [] ---
    # Key functions: meta.process
    plot(res.fcs, data=dat.transformed, subset=c(1,2))
    data(dat.exp)
    meta<-meta.process(dat.exp, meta.bias=0.3)

    # --- Stage2plot1 [] ---
    # Key functions: clusters, addLevel, move, unclassified, leucocytes
    plot(meta, c(), plot.subset=c(1,2))
    cls <- clusters(meta,c())
    inc <- mu(meta,cls,1) > 20000 & mu(meta,cls,1) < 150000
    addLevel(meta,c(1),"leucocytes") <- cls[inc]

    cls <- clusters(meta,c(1))
    sort(mu(meta,cls,2))
    inc <- (mu(meta,cls,2)) < 40000
    addLevel(meta,c(1,1), "ly") <- cls[inc]
    addLevel(meta,c(1,2), "mo") <- c()
    inc <- (mu(meta,cls,2)) > 100000

    # --- Stage2plot2 [] ---
    # Key functions: clusters, addLevel, unclassified
    plot(meta, c(1))
    cls <- clusters(meta,c(1,1))
    sort(mu(meta,cls,7))   ## CD3 expression
    sort(mu(meta,cls,6))   ## CD4 expression
    inc <- mu(meta,cls,7) > 5 & mu(meta,cls,6) > 4
    addLevel(meta,c(1,1,1), "CD3+CD4+") <- cls[inc]
    inc <- mu(meta,cls,7) > 5 & mu(meta,cls,6) < 4
    addLevel(meta,c(1,1,2), "CD3+CD4-") <- cls[inc]
    cls <- unclassified(meta,c(1,1))
    inc <- (mu(meta,cls,4)) > 3
    addLevel(meta,c(1,1,3), "CD19+") <- cls[inc]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_immunoclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_immunoclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_immunoclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IMMUNOCLUST:", paste0("    immunoclust: ", packageVersion("immunoClust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_immunoclust_results.csv
    touch ${prefix}_immunoclust_output.rds
    echo "BIOC_IMMUNOCLUST:" > versions.yml
    echo "    immunoclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IMMUNOCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IMMUNOCLUST(ch_input)

    emit:
    results  = BIOC_IMMUNOCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IMMUNOCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IMMUNOCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IMMUNOCLUST.out.versions  // channel: path(versions.yml)
}
