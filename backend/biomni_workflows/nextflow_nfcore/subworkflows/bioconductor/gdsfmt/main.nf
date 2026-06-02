#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gdsfmt
// Provides a high-level R interface to CoreArray Genomic Data Structure (GDS) data files. GDS is porta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gdsfmt/inst/doc/gdsfmt.R
// Upstream  : none
// Downstream: bigmelon, GDSArray, RAIDS, SAIGEgds, SCArray
//
// Install: BiocManager::install("gdsfmt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDSFMT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdsfmt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gdsfmt:1.42.1--r44_0' :
        'quay.io/biocontainers/bioconductor-gdsfmt:1.42.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdsfmt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdsfmt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdsfmt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gdsfmt)
    library(jsonlite)

    # --- Gds [] ---
    # Key functions: gds
    ---------------------------------------------------------------------
    library(gdsfmt)
    gfile <- createfn.gds("test.gds")
    # --- Gdsn [] ---
    # Key functions: gdsn, factor, sample, frame
    ---------------------------------------------------------------------
    add.gdsn(gfile, "int", val=1:10000)
    add.gdsn(gfile, "double", val=seq(1, 1000, 0.4))
    add.gdsn(gfile, "character", val=c("int", "double", "logical", "factor"))
    add.gdsn(gfile, "logical", val=rep(c(TRUE, FALSE, NA), 50), visible=FALSE)
    # --- Gdsn [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    folder <- addfolder.gdsn(gfile, "folder")
    add.gdsn(folder, "int", val=1:1000)
    add.gdsn(folder, "double", val=seq(1, 100, 0.4), visible=FALSE)
    # --- Gds [] ---
    # Key functions: gds
    ---------------------------------------------------------------------
    # close the GDS file
    closefn.gds(gfile)
    # --- Gdsn [] ---
    # Key functions: gdsn, show
    ---------------------------------------------------------------------
    n <- add.gdsn(gfile, "I1", val=matrix(1:15, nrow=3))
    show(n)
    # --- Gdsn [] ---
    # Key functions: gdsn, int, show
    ---------------------------------------------------------------------
    (n2 <- add.gdsn(gfile, "I2", storage="int", valdim=c(100, 2000)))
    for (i in 1:2000)
    # --- Gds [] ---
    # Key functions: gds
    ---------------------------------------------------------------------
    # close the GDS file
    closefn.gds(gfile)
    # --- Gds [] ---
    # Key functions: gds, gdsn
    ---------------------------------------------------------------------
    gfile <- createfn.gds("test.gds")
    add.gdsn(gfile, "I1", val=matrix(1:20, nrow=4))
    add.gdsn(gfile, "I2", val=1:100)
    closefn.gds(gfile)
    # --- Gdsn [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    # read a subset
    read.gdsn(n, start=c(2, 2), count=c(2, 3))
    read.gdsn(n, start=c(2, 2), count=c(2, 3), .value=c(6,15), .substitute=NA)
    # --- Gdsn [] ---
    # Key functions: gdsn, gds
    ---------------------------------------------------------------------
    apply.gdsn(n, margin=1, FUN=print, as.is="none")
    apply.gdsn(n, margin=2, FUN=print, as.is="none")
    # close the GDS file
    closefn.gds(gfile)
    # --- Gds [] ---
    # Key functions: gds, gdsn
    ---------------------------------------------------------------------
    gfile <- createfn.gds("test.gds")
    n1 <- add.gdsn(gfile, "I1", val=1:100)
    n2 <- add.gdsn(gfile, "I2", val=matrix(1:20, nrow=4))
    gfile
    # --- Gdsn [] ---
    # Key functions: gdsn, gds
    ---------------------------------------------------------------------
    n.t <- add.gdsn(gfile, "transpose", storage="int", valdim=c(5,0))
    # apply the function over rows of matrix
    apply.gdsn(n2, margin=1, FUN=c, as.is="gdsnode", target.node=n.t)
    # matrix transpose
    # --- Gds [] ---
    # Key functions: gds
    ---------------------------------------------------------------------
    # close the GDS file
    closefn.gds(gfile)
    # --- Gds [] ---
    # Key functions: gds, sample, gdsn
    ---------------------------------------------------------------------
    # create a GDS file
    f <- createfn.gds("test.gds")
    set.seed(1000)
    m <- matrix(sample(c(0:2), 56, replace=T), nrow=4)
    # --- Gds [] ---
    # Key functions: gds, gdsn, rnorm
    ---------------------------------------------------------------------
    # create a GDS file
    f <- createfn.gds("test.gds")
    n <- add.gdsn(f, "raw", rnorm(1115), compress="ZIP", closezip=TRUE)
    digest.gdsn(n, action="add")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gdsfmt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gdsfmt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gdsfmt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDSFMT:", paste0("    gdsfmt: ", packageVersion("gdsfmt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdsfmt_results.csv
    touch ${prefix}_gdsfmt_output.rds
    echo "BIOC_GDSFMT:" > versions.yml
    echo "    gdsfmt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDSFMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDSFMT(ch_input)

    emit:
    results  = BIOC_GDSFMT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDSFMT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDSFMT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDSFMT.out.versions  // channel: path(versions.yml)
}
