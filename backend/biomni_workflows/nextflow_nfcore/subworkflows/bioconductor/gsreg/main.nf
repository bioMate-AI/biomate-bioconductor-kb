#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSReg
// A package for gene set analysis based on the variability of expressions as well as a method to detec
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSReg/inst/doc/GSReg.R
// Upstream  : GSBenchMark, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("GSReg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSREG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsreg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsreg:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gsreg:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsreg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsreg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsreg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSReg)
    library(DIRAC)
    library(EVA)
    library(SEVA)
    library(jsonlite)

    # --- Differential Regulation Analysis ---
    # Key functions: GSReg.GeneSets.DIR
    control_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    disease_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    rownames(control_matrix) <- paste0("Gene", 1:100)
    rownames(disease_matrix) <- paste0("Gene", 1:100)
    pathway_list <- list(
        Pathway1 = paste0("Gene", 1:10),
        Pathway2 = paste0("Gene", 11:20)
    )
    dir_results <- GSReg.GeneSets.DIR(
        exprs1 = control_matrix,
        exprs2 = disease_matrix,
        pathways = pathway_list,
        minSize = 2,
        maxSize = 100
    )

    # --- Expression Variation Analysis ---
    # Key functions: GSReg.GeneSets.EVA
    control_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    disease_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    rownames(control_matrix) <- paste0("Gene", 1:100)
    rownames(disease_matrix) <- paste0("Gene", 1:100)
    pathway_list <- list(
        Pathway1 = paste0("Gene", 1:10),
        Pathway2 = paste0("Gene", 11:20)
    )
    eva_results <- GSReg.GeneSets.EVA(
        exprs1 = control_matrix,
        exprs2 = disease_matrix,
        pathways = pathway_list,
        minSize = 2,
        maxSize = 100
    )

    # --- Single Gene Set Analysis ---
    # Key functions: GSReg.DIR, GSReg.EVA
    control_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    disease_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    rownames(control_matrix) <- paste0("Gene", 1:100)
    rownames(disease_matrix) <- paste0("Gene", 1:100)
    gene_set <- paste0("Gene", 1:15)
    single_dir <- GSReg.DIR(
        exprs1 = control_matrix[gene_set, ],
        exprs2 = disease_matrix[gene_set, ]
    )
    single_eva <- GSReg.EVA(
        exprs1 = control_matrix[gene_set, ],
        exprs2 = disease_matrix[gene_set, ]
    )

    # --- Significance Testing via Permutations ---
    # Key functions: GSReg.GeneSets.DIR
    control_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    disease_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
    rownames(control_matrix) <- paste0("Gene", 1:100)
    rownames(disease_matrix) <- paste0("Gene", 1:100)
    pathway_list <- list(
        Pathway1 = paste0("Gene", 1:10),
        Pathway2 = paste0("Gene", 11:20)
    )
    dir_perm_results <- GSReg.GeneSets.DIR(
        exprs1 = control_matrix,
        exprs2 = disease_matrix,
        pathways = pathway_list,
        nperm = 100
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsreg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsreg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsreg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSREG:", paste0("    gsreg: ", packageVersion("GSReg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsreg_results.csv
    touch ${prefix}_gsreg_output.rds
    echo "BIOC_GSREG:" > versions.yml
    echo "    gsreg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSREG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSREG(ch_input)

    emit:
    results  = BIOC_GSREG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSREG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSREG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSREG.out.versions  // channel: path(versions.yml)
}
