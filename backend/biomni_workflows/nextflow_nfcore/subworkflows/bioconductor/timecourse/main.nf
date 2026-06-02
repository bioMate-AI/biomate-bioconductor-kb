#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: timecourse
// Functions for data analysis and graphical displays for developmental microarray time course data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/timecourse/inst/doc/timecourse.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("timecourse")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIMECOURSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-timecourse"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-timecourse:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-timecourse:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_timecourse_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_timecourse_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_timecourse_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(timecourse)
    library(MANOVA)
    library(jsonlite)

    # --- Two-sample Paired and 2D Analysis [] ---
    # Key functions: mb.long
    trt <- rep(c("wt", "mt"), each=15)
    assay <- rep(rep(c("rep1", "rep2", "rep3"), each=5), 2)
    size <- matrix(3, nrow=1000, ncol=2)
    M2 <- matrix(rnorm(1000 * 30, mean=14), ncol=30)
    MB.paired <- mb.long(M2, method="paired", times=5, reps=size,
                         condition.grp=trt, rep.grp=assay)
    MB.2D <- mb.long(M2, method="2", times=5, reps=size,
                     condition.grp=trt, rep.grp=assay)


    # --- Multi-sample Longitudinal Analysis [] ---
    # Key functions: mb.MANOVA
    assay <- rep(c("1", "2", "3", "4", "5", "6", "7", "8", "9"), each=5)
    trt <- c(rep(c("wildtype", "mutant1"), each=15),
             rep("mutant1", 5), rep("mutant2", 10))
    size <- matrix(c(4, 2, 3), byrow=TRUE, nrow=500, ncol=3)
    M <- matrix(rnorm(500 * 45, mean=14), ncol=45)
    MB.multi <- mb.MANOVA(M, times=5, D=3, size=size, rep.grp=assay,
                          condition.grp=trt)


    # --- Visualisation of Profiles [] ---
    # Key functions: mb.long, plotProfile
    data(fruitfly)
    gnames <- rownames(fruitfly)
    assay <- rep(c("A", "B", "C"), each=12)
    time.grp <- rep(c(1:12), 3)
    size <- rep(3, 2000)
    out2 <- mb.long(fruitfly, times=12, reps=size, rep.grp=assay,
                    time.grp=time.grp)
    plotProfile(out2, type="b", gnames=gnames, legloc=c(2,15),
                pch=c("A","B","C"), xlab="Hour")
    plotProfile(out2, type="b", gnames=gnames, pch=c("A","B","C"),
                xlab="Hour", ranking=100)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_timecourse_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_timecourse_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_timecourse_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIMECOURSE:", paste0("    timecourse: ", packageVersion("timecourse"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_timecourse_results.csv
    touch ${prefix}_timecourse_output.rds
    echo "BIOC_TIMECOURSE:" > versions.yml
    echo "    timecourse: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIMECOURSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIMECOURSE(ch_input)

    emit:
    results  = BIOC_TIMECOURSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIMECOURSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIMECOURSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIMECOURSE.out.versions  // channel: path(versions.yml)
}
