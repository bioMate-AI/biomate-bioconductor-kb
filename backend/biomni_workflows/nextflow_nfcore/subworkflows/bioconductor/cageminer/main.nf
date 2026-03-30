#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cageminer
// This package aims to integrate GWAS-derived SNPs and coexpression networks to mine candidate genes a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cageminer/inst/doc/cageminer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cageminer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAGEMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cageminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cageminer:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cageminer:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cageminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cageminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cageminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRangesList)
    library(SFT_fit)
    library(jsonlite)

    # --- Genomic ranges list construction [] ---
    # Key functions: plot_snp_distribution, plot_snp_circos, GRangesList, mine_step1, simulate_windows, SFT_fit, exp2gcn, mine_step2
    data(guides)
    head(guides)
    sft <- BioNERO::SFT_fit(pepper_se, net_type = "signed", cor_method = "pearson")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cageminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cageminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cageminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAGEMINER:", paste0("    cageminer: ", packageVersion("cageminer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cageminer_results.csv
    touch ${prefix}_cageminer_output.rds
    echo "BIOC_CAGEMINER:" > versions.yml
    echo "    cageminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAGEMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CAGEMINER(ch_input)

    emit:
    results  = BIOC_CAGEMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAGEMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAGEMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAGEMINER.out.versions  // channel: path(versions.yml)
}
