#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NanoMethViz
// NanoMethViz is a toolkit for visualising methylation data from Oxford Nanopore sequencing. It can be
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NanoMethViz/inst/doc/UsersGuide.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("NanoMethViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NANOMETHVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nanomethviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nanomethviz:3.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nanomethviz:3.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nanomethviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nanomethviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nanomethviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NanoMethViz)
    library(ModBamFiles)
    library(ModBamResult)
    library(NanoMethResult)
    library(jsonlite)

    # --- Data Import and Tabix Conversion ---
    # Key functions: create_tabix_file, methy_col_names
    methy_calls <- system.file(
        package = "NanoMethViz",
        c("sample1_nanopolish.tsv.gz", "sample2_nanopolish.tsv.gz")
    )
    methy_tabix <- file.path(tempdir(), "methy_data.bgz")
    samples <- c("sample1", "sample2")
    create_tabix_file(methy_calls, methy_tabix, samples)
    methy_cols <- methy_col_names()

    # --- Object Construction ---
    # Key functions: NanoMethResult, get_exons_mm10
    methy <- system.file(package = "NanoMethViz", "methy_subset.tsv.bgz")
    exon_tibble <- get_exons_mm10()
    sample_anno <- data.frame(
        sample = c("B6Cast_Prom_1_bl6", "B6Cast_Prom_1_cast"),
        group = c("bl6", "cast"),
        stringsAsFactors = FALSE
    )
    nmr <- NanoMethResult(methy, sample_anno, exon_tibble)

    # --- Format Conversion for Differential Methylation ---
    # Key functions: load_example_nanomethresult, methy_to_bsseq, exons_to_genes, bsseq_to_edger
    nmr <- load_example_nanomethresult()
    bss <- methy_to_bsseq(nmr)
    gene_regions <- exons_to_genes(NanoMethViz::exons(nmr))
    edger_mat <- bsseq_to_edger(bss, gene_regions)

    # --- Dimensionality Reduction and QC ---
    # Key functions: load_example_nanomethresult, methy_to_bsseq, exons_to_genes, bsseq_to_log_methy_ratio, plot_mds
    nmr <- load_example_nanomethresult()
    bss <- methy_to_bsseq(nmr)
    gene_anno <- exons_to_genes(NanoMethViz::exons(nmr))
    lmr <- bsseq_to_log_methy_ratio(bss, regions = gene_anno)
    mds_plot <- plot_mds(lmr)
    pca_plot <- plot_pca(lmr)

    # --- Methylation Profile Visualisation ---
    # Key functions: load_example_nanomethresult, plot_gene
    nmr <- load_example_nanomethresult()
    bsseq_dmr <- read.table(
        system.file(package = "NanoMethViz", "dmr_subset.tsv.gz"),
        sep = "\t",
        header = TRUE,
        stringsAsFactors = FALSE
    )
    plot_gene(nmr, "Peg3", anno_regions = bsseq_dmr, heatmap = TRUE)
    plot_gene(nmr, "Peg3", anno_regions = bsseq_dmr, spaghetti = TRUE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nanomethviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nanomethviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nanomethviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NANOMETHVIZ:", paste0("    nanomethviz: ", packageVersion("NanoMethViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nanomethviz_results.csv
    touch ${prefix}_nanomethviz_output.rds
    echo "BIOC_NANOMETHVIZ:" > versions.yml
    echo "    nanomethviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NANOMETHVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NANOMETHVIZ(ch_input)

    emit:
    results  = BIOC_NANOMETHVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NANOMETHVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NANOMETHVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NANOMETHVIZ.out.versions  // channel: path(versions.yml)
}
