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
    library(GRanges)
    library(GRangesList)
    library(IRanges)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: GRanges, seqlevelsStyle, useEnsembl, getBM, reduce, IRanges, GRangesList, import

    # --- Quality control and filtering [] ---
    # Key functions: seqnames, plot_rainfall
    chromosomes <- seqnames(get(ref_genome))[1:22]
    # --- Read vcfs as granges analysis [] ---
    # Key functions: read_vcfs_as_granges, get_mut_type, mutations_from_vcf, mut_type, mut_context, type_context, mut_type_occurrences, plot_spectrum

    # --- Variant calling and annotation [] ---
    # Key functions: mut_matrix, extract_signatures, fit_to_signatures, rename_nmf_signatures, plot_contribution_heatmap, lengthen_mut_matrix
    mut_mat_region <- mut_matrix(grl_region, ref_genome)
    nmf_res_region <- extract_signatures(mut_mat_region, rank = 2, nrun = 10, single_core = TRUE)
    # --- Feature annotation [] ---
    # Key functions: genes
    genes_hg19 <- genes(TxDb.Hsapiens.UCSC.hg19.knownGene)

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
