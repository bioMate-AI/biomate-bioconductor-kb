#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SIM
// Finds associations between two human genomic datasets.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SIM/inst/doc/SIM.R
// Upstream  : RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("SIM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sim:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sim:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SIM)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(expr.data)
    data(acgh.data)
    data(samples)
    # --- Ncol [] ---
    # Key functions: cbind
    acgh.data.only <- acgh.data[, 5:ncol(acgh.data)]
    expr.data.only <- expr.data[, 5:ncol(expr.data)]
    acgh.data.s <- acgh.data.only[, order(colnames(acgh.data.only))]
    expr.data.s <- expr.data.only[, order(colnames(expr.data.only))]
    sum(colnames(expr.data.s) == colnames(acgh.data.s))
    # --- Data [] ---
    # Key functions: data

    # --- Analysis [] ---
    # Key functions: analysis
    integrated.analysis(samples = samples,
                        input.regions = "8q",
                        zscores = TRUE,
                        method = "full",
                        run.name = "chr8q")
    # --- Genome [] ---
    # Key functions: genome
    sim.plot.pvals.on.genome(input.regions = "8q",
                             adjust.method = "BY",
                             run.name = "chr8q")
    # --- Pvals [] ---
    # Key functions: pvals
    tabulate.pvals(input.regions = "8q",
                   adjust.method = "BY",
                   bins = c(0.001, 0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.2, 1),
                   significance.idx=8,
                   run.name = "chr8q")
    # --- Region [] ---
    # Key functions: region
    sim.plot.pvals.on.region(input.regions = "8q", adjust.method = "BY", run.name = "chr8q")
    # --- Heatmap [] ---
    # Key functions: heatmap, pal, rainbow
    library(RColorBrewer)
    # --- Features [] ---
    # Key functions: features
    table.dep <- tabulate.top.dep.features(input.regions = "8q",
                                           adjust.method = "BY",
                                           run.name = "chr8q")
    head(table.dep[["8q"]])
    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIM:", paste0("    sim: ", packageVersion("SIM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sim_results.csv
    touch ${prefix}_sim_output.rds
    echo "BIOC_SIM:" > versions.yml
    echo "    sim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIM(ch_input)

    emit:
    results  = BIOC_SIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIM.out.versions  // channel: path(versions.yml)
}
