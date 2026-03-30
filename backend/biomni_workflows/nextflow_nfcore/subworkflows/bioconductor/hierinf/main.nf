#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hierinf
// Tools to perform hierarchical inference for one or multiple studies / data sets based on high-dimens
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hierinf/inst/doc/vignette-hierinf.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("hierinf")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIERINF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hierinf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hierinf:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hierinf:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hierinf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hierinf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hierinf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNGkind)
    library(jsonlite)

    # --- Generator [] ---
    # Key functions: generator, RNGkind
    ---------------------------------------------------------------------
    # load the package
    library(hierinf)
    # random number generator (for parallel computing)
    RNGkind("L'Ecuyer-CMRG")
    # --- Frame [] ---
    # Key functions: frame, cluster_var
    ---------------------------------------------------------------------
    # Define the second level of the tree structure.
    block <- data.frame("colname" = paste0("SNP.", 1:1000),
                        "block" = rep(c("chrom 1", "chrom 2"), each = 500),
                        stringsAsFactors = FALSE)
    # --- Compute R2 [] ---
    # Key functions: compute_r2
    ---------------------------------------------------------------------
    compute_r2(x = sim.geno, y = sim.pheno, clvar = sim.clvar,
               res.test.hierarchy = result, family = "binomial",
               colnames.cluster = coln.cluster)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hierinf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hierinf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hierinf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIERINF:", paste0("    hierinf: ", packageVersion("hierinf"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hierinf_results.csv
    touch ${prefix}_hierinf_output.rds
    echo "BIOC_HIERINF:" > versions.yml
    echo "    hierinf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIERINF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIERINF(ch_input)

    emit:
    results  = BIOC_HIERINF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIERINF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIERINF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIERINF.out.versions  // channel: path(versions.yml)
}
