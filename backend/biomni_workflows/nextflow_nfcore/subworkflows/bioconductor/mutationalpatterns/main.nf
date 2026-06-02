#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MutationalPatterns
// Mutational processes leave characteristic footprints in genomic DNA. This package provides a compreh
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MutationalPatterns/inst/doc/Introduction_to_MutationalPatterns.R
// Upstream  : BSgenome, NMF, biomaRt, ccfindR, gridExtra
// Downstream: none
//
// Install: BiocManager::install("MutationalPatterns")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUTATIONALPATTERNS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mutationalpatterns"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mutationalpatterns:3.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mutationalpatterns:3.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mutationalpatterns_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mutationalpatterns_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mutationalpatterns_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MutationalPatterns)
    library(GRanges)
    library(GRangesList)
    library(IRanges)
    library(jsonlite)

    # --- Mutational Profile and Spectrum Analysis [] ---
    # Key functions: mut_type_occurrences, plot_spectrum, mut_matrix
    ref_genome <- "BSgenome.Hsapiens.UCSC.hg19"
    type_occurrences <- mut_type_occurrences(snv_grl, ref_genome)
    p1 <- plot_spectrum(type_occurrences, CT = TRUE, legend = TRUE)
    mut_mat <- mut_matrix(vcf_list = snv_grl, ref_genome = ref_genome)


    # --- Indel and Doublet Base Substitution Contexts [] ---
    # Key functions: get_indel_context, count_indel_contexts, get_dbs_context, count_dbs_contexts
    ref_genome <- "BSgenome.Hsapiens.UCSC.hg19"
    indel_grl_context <- get_indel_context(indel_grl, ref_genome)
    indel_counts <- count_indel_contexts(indel_grl_context)
    dbs_grl_context <- get_dbs_context(dbs_grl)
    dbs_counts <- count_dbs_contexts(dbs_grl_context)


    # --- Signature Extraction and De Novo NMF [] ---
    # Key functions: extract_signatures, get_known_signatures, rename_nmf_signatures
    mut_mat_pseudo <- mut_mat + 0.0001
    nmf_res <- extract_signatures(
        mut_mat_pseudo, rank = 2, nrun = 10, single_core = TRUE
    )
    signatures <- get_known_signatures()
    nmf_res <- rename_nmf_signatures(nmf_res, signatures, cutoff = 0.85)


    # --- Signature Contribution and Visualization [] ---
    # Key functions: plot_contribution, plot_contribution_heatmap, cluster_signatures
    contrib_plot <- plot_contribution(
        nmf_res$contribution, nmf_res$signature, mode = "relative"
    )
    heatmap_plot <- plot_contribution_heatmap(
        nmf_res$contribution, cluster_samples = TRUE, cluster_sigs = TRUE
    )
    hclust_signatures <- cluster_signatures(
        nmf_res$signatures, method = "average"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mutationalpatterns_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mutationalpatterns_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mutationalpatterns_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUTATIONALPATTERNS:", paste0("    mutationalpatterns: ", packageVersion("MutationalPatterns"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mutationalpatterns_results.csv
    touch ${prefix}_mutationalpatterns_output.rds
    echo "BIOC_MUTATIONALPATTERNS:" > versions.yml
    echo "    mutationalpatterns: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUTATIONALPATTERNS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUTATIONALPATTERNS(ch_input)

    emit:
    results  = BIOC_MUTATIONALPATTERNS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUTATIONALPATTERNS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUTATIONALPATTERNS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUTATIONALPATTERNS.out.versions  // channel: path(versions.yml)
}
