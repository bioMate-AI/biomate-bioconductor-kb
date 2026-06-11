#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Herper
// Many tools for data analysis are not available in R, but are present in public repositories like con
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Herper/inst/doc/QuickStart.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Herper")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_HERPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-herper"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_herper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_herper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_herper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Herper)
    library(jsonlite)

    # --- install Condatools [] ---
    # Key functions: install_CondaTools
    myMiniconda <- file.path(tempdir(),"Test")
    install_CondaTools("salmon==1.3.0", "herper", pathToMiniConda = myMiniconda)
    # --- install CondaSysReqs [] ---
    # Key functions: install_CondaSysReqs
    testPkg <- system.file("extdata/HerperTestPkg",package="Herper")
    install.packages(testPkg,type = "source",repos = NULL)
    condaDir <- file.path(tempdir(),"r-miniconda")

    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_herper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_herper_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_herper_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_HERPER:", paste0("    herper: ", as.character(packageVersion("Herper")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_herper_results.csv
    touch ${prefix}_herper_output.rds
    echo "BIOC_HERPER:" > versions.yml
    echo "    herper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HERPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HERPER(ch_input)

    emit:
    results  = BIOC_HERPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HERPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HERPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HERPER.out.versions  // channel: path(versions.yml)
}
