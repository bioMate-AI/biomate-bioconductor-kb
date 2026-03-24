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
    library(MANOVA)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(fruitfly)
    dim(fruitfly)
    colnames(fruitfly)
    gnames <- rownames(fruitfly)
    # --- Rep [] ---
    # Key functions: rep
    assay <- rep(c("A", "B", "C"), each=12)
    time.grp <- rep(c(1:12), 3)
    size <- rep(3, 2000)
    # --- Long [] ---
    # Key functions: long
    out1 <- mb.long(fruitfly, times=12, reps=size)
    out2 <- mb.long(fruitfly, times=12, reps=size, rep.grp=assay, time.grp=time.grp)
    # --- Matrix [] ---
    # Key functions: mvrnorm, crossprod
    SS <- matrix(c( 1e-02, -8e-04, -0.003,  7e-03,  2e-03,
                   -8e-04,  2e-02,  0.002, -4e-04, -1e-03,
                   -3e-03,  2e-03,  0.030, -5e-03, -9e-03,
                    7e-03, -4e-04, -0.005,  2e-02,  8e-04,
                    2e-03, -1e-03, -0.009,  8e-04,  7e-02), ncol=5)
    # --- Rep [] ---
    # Key functions: long
    trt <- rep(c("wt","mt"),each=15)
    assay <- rep(rep(c("rep1","rep2","rep3"),each=5),2)
    size <- matrix(3, nrow=1000, ncol=2)
    MB.paired <- mb.long(M2, method="paired", times=5, reps=size, condition.grp=trt, rep.grp=assay)
    genenames <- as.character(1:1000)
    # --- Long [] ---
    # Key functions: long
    MB.2D <- mb.long(M2, method="2", times=5, reps=size, condition.grp=trt, rep.grp=assay)
    # --- Function [] ---
    # Key functions: runif, mvrnorm
    sim.data <- function(x, indx=1)
    {
       mu <- rep(runif(1,8,x[1]),5)
       if(indx==1)
         res <- c(as.numeric(t(mvrnorm(n=3, mu=mu+rnorm(5,sd=5), Sigma=sim.Sigma()))),
    # --- Rep [] ---
    # Key functions: MANOVA
    assay <- rep(c("1.2.04","2.4.04","3.5.04","5.21.04","7.17.04","9.10.04","12.1.04","1.2.05","4.1.05"),each=5)
    trt <- c(rep(c("wildtype","mutant1"),each=15),rep("mutant1",5), rep("mutant2", 10))
    # Caution: since "mutant1" < "mutant2" < "wildtype", the sample sizes should be in the order of 4,2,3,
    # but NOT 3,4,2.
    size <- matrix(c(4,2,3), byrow=TRUE, nrow=500, ncol=3)
    # --- Rep [] ---
    # Key functions: long
    fruitfly[6, 13:24] <- NA  # The 6th gene has 1 missing replicate
    size <- rep(3, 2000)
    size[6] <- 2
    MB.missing <- mb.long(fruitfly, times=12, reps=size, HotellingT2.only=FALSE)
    # --- Plotprofile [] ---
    # Key functions: plotProfile
    ## plots the no. 1 gene
    plotProfile(out2, type="b", gnames=gnames, legloc=c(2,15), pch=c("A","B","C"), xlab="Hour")

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
