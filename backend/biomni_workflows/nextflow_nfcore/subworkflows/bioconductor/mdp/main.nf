#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mdp
// The Molecular Degree of Perturbation webtool quantifies the heterogeneity of samples. It takes a dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mdp/inst/doc/my-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mdp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MDP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mdp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mdp:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mdp:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mdp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mdp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mdp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mdp)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: mdp
    ---------------------------------------------------------------------
    library(mdp)
    data(example_data) # expression data has gene names in the rows
    data(example_pheno) # pheno data needs a Sample and Class column
    mdp.results <- mdp(data=example_data, pdata=example_pheno, control_lab = "baseline")
    # --- Head [] ---
    # Key functions: sample_plot
    ---------------------------------------------------------------------
    sample_scores_list <- mdp.results$sample_scores
    # select sample scores calculated using the perturbed genes
    sample_scores <- sample_scores_list[["perturbedgenes"]]
    head(sample_scores)
    # --- Compute Zscore [] ---
    # Key functions: compute_zscore
    ---------------------------------------------------------------------
    control_samples <- example_pheno[example_pheno$Class == "baseline","Sample"]
    zscore <- compute_zscore(data = example_data,control_samples = control_samples,measure = "mean",std = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mdp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mdp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mdp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MDP:", paste0("    mdp: ", packageVersion("mdp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mdp_results.csv
    touch ${prefix}_mdp_output.rds
    echo "BIOC_MDP:" > versions.yml
    echo "    mdp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MDP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MDP(ch_input)

    emit:
    results  = BIOC_MDP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MDP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MDP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MDP.out.versions  // channel: path(versions.yml)
}
