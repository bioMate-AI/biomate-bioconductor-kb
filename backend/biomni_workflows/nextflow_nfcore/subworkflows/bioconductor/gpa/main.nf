#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GPA
// This package provides functions for fitting GPA, a statistical framework to prioritize GWAS results 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GPA/inst/doc/GPA-example.R
// Upstream  : gpaExample
// Downstream: none
//
// Install: BiocManager::install("GPA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GPA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gpa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gpa:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gpa:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gpa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gpa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gpa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GPA)
    library(jsonlite)

    # --- Installation [] ---
    # Key functions: requireNamespace, packages
    ## if(!requireNamespace("BiocManager", quietly = TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("GPA")
    # --- Mosaicsexample Prelim [] ---
    # Key functions: data
    library(gpaExample)
    data(exampleData)
    dim(exampleData$pval)
    head(exampleData$pval)
    dim(exampleData$ann)
    # --- Gpa Noann Show [] ---
    # Key functions: GPA
    ## fit.GPA.noAnn <- GPA( exampleData$pval[ , c(3,5) ], NULL )
    # --- Gpa Noann Run [] ---
    # Key functions: GPA
    fit.GPA.noAnn <- GPA( exampleData$pval[ , c(3,5) ], NULL, maxIter=100 )
    # --- Gpa Noann Simple [] ---
    # Key functions: GPA
    ## fit.GPA.noAnn <- GPA( exampleData$pval[ , c(3,5) ] )
    # --- Gpa Ann Show [] ---
    # Key functions: GPA
    ## fit.GPA.wAnn <- GPA( exampleData$pval[ , c(3,5) ], exampleData$ann )
    # --- Gpa Ann Run [] ---
    # Key functions: GPA
    fit.GPA.wAnn <- GPA( exampleData$pval[ , c(3,5) ], exampleData$ann, maxIter=100 )
    # --- Gpa Estimates Se Ann [] ---
    # Key functions: estimates, se
    estimates( fit.GPA.wAnn )
    se( fit.GPA.wAnn )
    # --- Gpa Assoc Ann [] ---
    # Key functions: assoc
    assoc.GPA.wAnn <- assoc( fit.GPA.wAnn, FDR=0.20, fdrControl="global" )
    dim(assoc.GPA.wAnn)
    head(assoc.GPA.wAnn)
    table(assoc.GPA.wAnn[,1])
    table(assoc.GPA.wAnn[,2])
    # --- Gpa Fdr Ann [] ---
    # Key functions: fdr
    fdr.GPA.wAnn <- fdr(fit.GPA.wAnn)
    dim(fdr.GPA.wAnn)
    head(fdr.GPA.wAnn)
    # --- Gpa Assoc Pattern Ann [] ---
    # Key functions: assoc, fdr
    assoc11.GPA.wAnn <- assoc( fit.GPA.wAnn, FDR=0.20, fdrControl="global", pattern="11" )
    length(assoc11.GPA.wAnn)
    head(assoc11.GPA.wAnn)
    table(assoc11.GPA.wAnn)
    fdr11.GPA.wAnn <- fdr( fit.GPA.wAnn, pattern="11" )
    # --- Gpa Pleiotropy Null Show [] ---
    # Key functions: GPA
    ## fit.GPA.pleiotropy.H0 <- GPA( exampleData$pval[ , c(3,5) ], NULL, pleiotropyH0=TRUE )
    # --- Gpa Pleiotropy Null Run [] ---
    # Key functions: GPA
    fit.GPA.pleiotropy.H0 <- GPA( exampleData$pval[ , c(3,5) ], NULL, pleiotropyH0=TRUE, maxIter=100 )
    # --- Ptest [] ---
    # Key functions: pTest
    test.GPA.pleiotropy <- pTest( fit.GPA.noAnn, fit.GPA.pleiotropy.H0 )
    # --- Atest [] ---
    # Key functions: aTest
    test.GPA.annotation <- aTest( fit.GPA.noAnn, fit.GPA.wAnn )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gpa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gpa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gpa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GPA:", paste0("    gpa: ", packageVersion("GPA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gpa_results.csv
    touch ${prefix}_gpa_output.rds
    echo "BIOC_GPA:" > versions.yml
    echo "    gpa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GPA(ch_input)

    emit:
    results  = BIOC_GPA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GPA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GPA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GPA.out.versions  // channel: path(versions.yml)
}
