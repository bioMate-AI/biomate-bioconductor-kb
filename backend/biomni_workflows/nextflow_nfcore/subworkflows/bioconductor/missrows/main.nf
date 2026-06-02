#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: missRows
// The missRows package implements the MI-MFA method to deal with missing individuals ('biological unit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/missRows/inst/doc/missRows.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("missRows")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MISSROWS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-missrows"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-missrows:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-missrows:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_missrows_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_missrows_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_missrows_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(missRows)
    library(jsonlite)


    # --- Load Data [] ---
    # Key functions: MIDTList, trans, prote
    data(NCI60)

    ## --------------------------------------------------------------------------
    names(NCI60)

    ## --------------------------------------------------------------------------
    table(NCI60$dataTables$cell.line$type)

    ## --------------------------------------------------------------------------
    NCI60$mae
    tableList <- NCI60$dataTables[1:2]
    cell.line <- NCI60$dataTables$cell.line

    midt <- MIDTList(tableList, colData=cell.line, 
                        assayNames=c("trans", "prote"))

    # --- Sep Midtlist [] ---
    # Key functions: MIDTList, trans, prote
    table1 <- NCI60$dataTables$trans
    table2 <- NCI60$dataTables$prote
    cell.line <- NCI60$dataTables$cell.line

    midt <- MIDTList(table1, table2, colData=cell.line,
                        assayNames=c("trans", "prote"))
    midt <- MIDTList("trans" = table1, "prote" = table2,
                    colData=cell.line)

    # --- Mae Midtlist [] ---
    # Key functions: MIDTList, MIMFA, colData
    midt <- MIDTList(NCI60$mae)

    ## --------------------------------------------------------------------------
    midt
    set.seed(123)
    midt <- MIMFA(midt, ncomp=50, M=30, estimeNC=TRUE)

    ## --------------------------------------------------------------------------
    midt

    ## --------------------------------------------------------------------------
    names(midt)

    ## --------------------------------------------------------------------------

    # --- Mth Conf [] ---
    # Key functions: configurations, missPattern, grey70
    conf <- configurations(midt, M=5)
    dim(conf)
    patt <- missPattern(midt, colMissing="grey70")

    # --- Missing Pattern Mat [] ---
    # Key functions: plotInd, white, ellipse, convex.hull
    patt
    plotInd(midt, colMissing="white")

    ## ----plotInd-ellipses, fig.width=6, fig.height=5, out.width="0.55\\textwidth"----
    plotInd(midt, confAreas="ellipse", confLevel=0.95)

    ## ----plotInd-convexhull, fig.width=6, fig.height=5, out.width="0.55\\textwidth"----
    plotInd(midt, confAreas="convex.hull")

    # --- Plot Var [] ---
    # Key functions: plotVar, tuneM
    plotVar(midt, radIn=0.5)

    ## ----plotVar-cutoff, fig.width=6, fig.height=5, out.width="0.55\\textwidth"----
    plotVar(midt, radIn=0.55, varNames=TRUE, cutoff=0.55)
    set.seed(1)
    tune <- tuneM(midt, ncomp=2, Mmax=100, inc=10, N=20, showPlot=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_missrows_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_missrows_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_missrows_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MISSROWS:", paste0("    missrows: ", packageVersion("missRows"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_missrows_results.csv
    touch ${prefix}_missrows_output.rds
    echo "BIOC_MISSROWS:" > versions.yml
    echo "    missrows: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MISSROWS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MISSROWS(ch_input)

    emit:
    results  = BIOC_MISSROWS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MISSROWS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MISSROWS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MISSROWS.out.versions  // channel: path(versions.yml)
}
