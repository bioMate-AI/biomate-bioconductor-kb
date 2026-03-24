#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SPEM
// This package can optimize the parameter in S-system models given time series data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SPEM/inst/doc/SPEM-package.R
// Upstream  : Biobase, Rsolnp
// Downstream: none
//
// Install: BiocManager::install("SPEM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spem:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spem:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SPEM)
    library(jsonlite)

    # --- Setpara [] ---
    # Key functions: rnorm
    toy_expression_data<-matrix(data=abs(rnorm(12)),nrow=3,ncol=4,
    	dimnames=list(paste("G",c(1:3),sep=''),
    	paste("tp",c(0,2,4,6),sep="_")))
    # --- Setpara [] ---
    # Key functions: frame
    toy_timepoints_data<-data.frame(index=c(1:4),
    	label=paste("tp",c(0,2,4,6),sep='_'),
    	time=c(0,2,4,6),row.names=paste("tp",c(0,2,4,6),sep='_'))
    # --- Setpara [] ---
    # Key functions: s_diff, runif
    Slope<- s_diff(sos)
    S<-Slope[1,]
    sparsity<- 0.2
    lbH<- -3
    ubH<- 3

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPEM:", paste0("    spem: ", packageVersion("SPEM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spem_results.csv
    touch ${prefix}_spem_output.rds
    echo "BIOC_SPEM:" > versions.yml
    echo "    spem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPEM(ch_input)

    emit:
    results  = BIOC_SPEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPEM.out.versions  // channel: path(versions.yml)
}
