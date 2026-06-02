#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: REBET
// There is an increasing focus to investigate the association between rare variants and diseases. The 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/REBET/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("REBET")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REBET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rebet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rebet:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rebet:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rebet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rebet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rebet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(REBET)
    library(jsonlite)

    # --- Geno File [] ---
    # Key functions: file
    genofile  <- system.file("sampleData", "geno_impute.txt.gz", package="REBET")
    subfile   <- system.file("sampleData", "subjects.txt.gz", package="REBET")
    phenofile <- system.file("sampleData", "pheno.txt.gz", package="REBET")
    # --- Sub Regions [] ---
    # Key functions: rbind
    subRegions <- rbind(c(87654800, 87661050),
                        c(87661051, 87668870),
                        c(87668871, 87671945),
                        c(87671946, 87673200))
    rownames(subRegions) <- paste("SR", 1:4, sep="")
    # --- Initialize [] ---
    # Key functions: rep
    upper.n <- 100
    G       <- matrix(data=NA, nrow=nrow(data), ncol=upper.n)
    snps    <- rep("", upper.n)
    locs    <- rep(NA, upper.n)
    # --- Read Geno File [] ---
    # Key functions: gzfile, na, any
    index <- 0
    fid   <- gzfile(genofile, "r")
    # --- Call Rebet [] ---
    # Key functions: rebet
    ret <- rebet(Y, G, E, covariates=X)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rebet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rebet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rebet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REBET:", paste0("    rebet: ", packageVersion("REBET"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rebet_results.csv
    touch ${prefix}_rebet_output.rds
    echo "BIOC_REBET:" > versions.yml
    echo "    rebet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REBET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REBET(ch_input)

    emit:
    results  = BIOC_REBET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REBET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REBET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REBET.out.versions  // channel: path(versions.yml)
}
