#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: retrofit
// RETROFIT is a Bayesian non-negative matrix factorization framework to decompose cell type mixtures i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/retrofit/inst/doc/ColonVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("retrofit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RETROFIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-retrofit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-retrofit:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-retrofit:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_retrofit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_retrofit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_retrofit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(retrofit)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data("vignetteColonData")
    X = vignetteColonData$a3_x
    # --- Decompose [] ---
    # Key functions: decompose
    result = retrofit::decompose(X, L=L, iterations=iterations, verbose=TRUE)
    H   = result$h
    W   = result$w
    Th  = result$th
    # --- Annotate With Sc [] ---
    # Key functions: annotateWithCorrelations
    K = ncol(sc_ref) # number of cell types
    result    = annotateWithCorrelations(sc_ref, K, W, H)
    H_sc      = result$h
    W_sc      = result$w
    H_sc_prop = result$h_prop
    # --- Visualize Correlation Matrix Between The Sc Reference And W [] ---
    # Key functions: corrplot, colorRampPalette
    W_norm <- W
    for(i in 1:nrow(W)){
        W_norm[i,]=W[i,]/sum(W[i,])
    }
    # --- Annotate With Marker [] ---
    # Key functions: annotateWithMarkers
    K = length(marker_ref) # number of cell types
    result      = retrofit::annotateWithMarkers(marker_ref, K, W, H)
    H_mark      = result$h
    W_mark      = result$w
    H_mark_prop = result$h_prop
    # --- Visualize Correlation Matrix Marker [] ---
    # Key functions: corrplot, colorRampPalette
    corrplot::corrplot(gene_sums,
                       is.corr=FALSE,
                       mar=c(0,0,1,0),
                       col=colorRampPalette(c("white", "deepskyblue", "blue4"))(100),
                       main="Marker-based Mapping Matrix")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_retrofit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_retrofit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_retrofit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RETROFIT:", paste0("    retrofit: ", packageVersion("retrofit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_retrofit_results.csv
    touch ${prefix}_retrofit_output.rds
    echo "BIOC_RETROFIT:" > versions.yml
    echo "    retrofit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RETROFIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RETROFIT(ch_input)

    emit:
    results  = BIOC_RETROFIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RETROFIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RETROFIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RETROFIT.out.versions  // channel: path(versions.yml)
}
