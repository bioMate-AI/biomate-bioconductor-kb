#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GGPA
// Genome-wide association studies (GWAS) is a widely used tool for identification of genetic variants 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GGPA/inst/doc/GGPA-example.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GGPA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGPA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggpa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggpa:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggpa:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggpa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggpa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggpa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GGPA)
    library(jsonlite)

    # --- Ggpaexample Prelim [] ---
    # Key functions: data
    data(simulation)
    dim(simulation$pmat)
    head(simulation$pmat)
    # --- Pgraph Show [] ---
    # Key functions: diag, ggnet2
    ## adjmat <- simulation$true_G
    ## diag(adjmat) <- 0
    ## ggnet2( adjmat, label=TRUE, size=15 )
    # --- Fig Pgraph [] ---
    # Key functions: diag
    adjmat <- simulation$true_G
    diag(adjmat) <- 0
    plot( adjmat, size=15 )
    # --- Ggpa Show [] ---
    # Key functions: GGPA
    ## set.seed(12345)
    ## fit <- GGPA( simulation$pmat )
    # --- Ggpa Run [] ---
    # Key functions: GGPA
    set.seed(12345)
    fit <- GGPA( simulation$pmat, nBurnin=200, nMain=200 )
    # --- Gpa Assoc Ann [] ---
    # Key functions: assoc
    assoc.marg <- assoc( fit, FDR=0.10, fdrControl="global" )
    dim(assoc.marg)
    apply( assoc.marg, 2, table )
    # --- Gpa Fdr Ann [] ---
    # Key functions: fdr
    fdr.marg <- fdr(fit)
    dim(fdr.marg)
    head(fdr.marg)
    # --- Gpa Assoc Pattern Ann [] ---
    # Key functions: assoc
    assoc.joint <- assoc( fit, FDR=0.10, fdrControl="global", i=1, j=2 )
    length(assoc.joint)
    head(assoc.joint)
    table(assoc.joint)
    # --- Ggpa Pgraph Show [] ---
    # Key functions: GGPA
    ## fit <- GGPA( pmat, pgraph )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggpa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggpa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggpa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGPA:", paste0("    ggpa: ", packageVersion("GGPA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggpa_results.csv
    touch ${prefix}_ggpa_output.rds
    echo "BIOC_GGPA:" > versions.yml
    echo "    ggpa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGPA(ch_input)

    emit:
    results  = BIOC_GGPA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGPA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGPA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGPA.out.versions  // channel: path(versions.yml)
}
