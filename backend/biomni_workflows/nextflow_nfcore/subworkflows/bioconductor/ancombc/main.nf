#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ANCOMBC
// ANCOMBC is a package containing differential abundance (DA) and correlation analyses for microbiome 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ANCOMBC/inst/doc/ANCOM.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ANCOMBC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANCOMBC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ancombc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ancombc:2.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ancombc:2.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ancombc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ancombc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ancombc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ANCOMBC)
    library(jsonlite)


    # --- Load [] ---
    # Key functions: subset_samples, meta, recode, microbiome, obese
    # library(ANCOMBC)

    ## -----------------------------------------------------------------------------
    data(atlas1006, package = "microbiome")

    # Subset to baseline
    pseq = phyloseq::subset_samples(atlas1006, time == 0)

    # Re-code the bmi group
    meta_data = microbiome::meta(pseq)
    meta_data$bmi = recode(meta_data$bmi_group,
                           obese = "obese",
                           severeobese = "obese",
                           morbidobese = "obese")


    # --- Eval=false [] ---
    # Key functions: abundances, aggregate_taxa, meta, ancom, holm, bmi, microbiome
    # abundance_data = microbiome::abundances(pseq)
    # aggregate_data = microbiome::abundances(microbiome::aggregate_taxa(pseq, "Family"))
    # meta_data = microbiome::meta(pseq)
    # 
    # set.seed(123)
    # out = ancom(data = abundance_data, aggregate_data = aggregate_data,
    #             meta_data = meta_data, p_adj_method = "holm", prv_cut = 0.10,
    #             lib_cut = 1000, main_var = "bmi", adj_formula = "age + region",
    #             rand_formula = NULL, lme_control = NULL, struc_zero = TRUE,
    #             neg_lb = TRUE, alpha = 0.05, n_cl = 2, verbose = TRUE)
    # 
    # res = out$res

    ## -----------------------------------------------------------------------------
    data(dietswap, package = "microbiome")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ancombc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ancombc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ancombc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANCOMBC:", paste0("    ancombc: ", packageVersion("ANCOMBC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ancombc_results.csv
    touch ${prefix}_ancombc_output.rds
    echo "BIOC_ANCOMBC:" > versions.yml
    echo "    ancombc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANCOMBC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANCOMBC(ch_input)

    emit:
    results  = BIOC_ANCOMBC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANCOMBC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANCOMBC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANCOMBC.out.versions  // channel: path(versions.yml)
}
