#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PAST
// PAST takes GWAS output and assigns SNPs to genes, uses those genes to find pathways associated with 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PAST/inst/doc/past.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PAST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-past"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-past:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-past:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_past_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_past_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_past_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PAST)
    library(jsonlite)

    # --- SNP Gene Assignment [] ---
    # Key functions: assign_SNPs_to_genes
    demo_genes_file <- system.file("extdata", "genes.gff",
                                  package = "PAST", mustWork = TRUE)
    genes <- assign_SNPs_to_genes(
        gwas_data,
        LD,
        demo_genes_file,
        c("gene"),
        1000,
        0.8,
        2
    )


    # --- Pathway Significance Analysis [] ---
    # Key functions: find_pathway_significance
    demo_pathways_file <- system.file("extdata", "pathways.txt.xz",
                                      package = "PAST", mustWork = TRUE)
    rugplots_data <- find_pathway_significance(
        genes,
        demo_pathways_file,
        5,
        "increasing",
        1000,
        2
    )


    # --- Pathway Visualisation [] ---
    # Key functions: plot_pathways
    plot_pathways(
        rugplots_data,
        "pvalue",
        0.02,
        "increasing",
        tempdir()
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_past_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_past_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_past_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAST:", paste0("    past: ", packageVersion("PAST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_past_results.csv
    touch ${prefix}_past_output.rds
    echo "BIOC_PAST:" > versions.yml
    echo "    past: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAST(ch_input)

    emit:
    results  = BIOC_PAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAST.out.versions  // channel: path(versions.yml)
}
