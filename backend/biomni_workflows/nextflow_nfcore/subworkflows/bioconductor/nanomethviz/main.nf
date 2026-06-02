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
    library(ModBamFiles)
    library(ModBamResult)
    library(NanoMethResult)
    library(jsonlite)

    # --- Import Exon Annotations [] ---
    # Key functions: get_exons_mm10
    ---------------------------------------------------------------------
    # helper function extracts exons from TxDb package
    exon_tibble <- get_exons_mm10()
    head(exon_tibble)
    # --- Construct NanoMethResult Object [] ---
    # Key functions: NanoMethResult
    ---------------------------------------------------------------------
    nmr <- NanoMethResult(methy, sample_anno, exon_tibble)
    # --- Plot Gene Methylation [] ---
    # Key functions: plot_gene
    ---------------------------------------------------------------------
    plot_gene(nmr, "Peg3")
    # --- Export Data [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    # loading saved results from previous bsseq analysis
    bsseq_dmr <- read.table(
        system.file(package = "NanoMethViz", "dmr_subset.tsv.gz"),
        sep = "\t",
    # --- Plot Gene Methylation [] ---
    # Key functions: plot_gene
    ---------------------------------------------------------------------
    plot_gene(nmr, "Peg3", anno_regions = bsseq_dmr)
    # --- Import ModBAM Data [] ---
    # Key functions: ModBamResult, ModBamFiles, frame, plot_gene
    ---------------------------------------------------------------------
    # construct with a ModBamFiles object as the methylation data
    mbr <- ModBamResult(
        methy = ModBamFiles(
            samples = "sample1",
    # --- Convert Exons to Genes [] ---
    # Key functions: exons_to_genes, exons, bsseq_to_edger
    ---------------------------------------------------------------------
    gene_regions <- exons_to_genes(NanoMethViz::exons(nmr))
    edger_mat <- bsseq_to_edger(bss, gene_regions)
    edger_mat
    # --- Import Methylation Data [] ---
    # Key functions: import
    ---------------------------------------------------------------------
    anno <- rtracklayer::import(system.file(package = "NanoMethViz", "c_elegans.gtf.gz"))
    head(anno)
    # --- Frame [] ---
    # Key functions: frame, rename, select
    ---------------------------------------------------------------------
    anno <- anno %>%
        as.data.frame() %>%
        dplyr::rename(
            chr = "seqnames",
    # --- Process Exon Annotations [] ---
    # Key functions: exons, exons_to_genes, mutate, plot_gene
    ---------------------------------------------------------------------
    new_exons <- NanoMethViz::exons(nmr) %>%
        exons_to_genes() %>%
        mutate(transcript_id = gene_id)
    NanoMethViz::exons(nmr) <- new_exons
    # --- Convert Exons to Genes [] ---
    # Key functions: exons_to_genes, exons, bsseq_to_log_methy_ratio
    ---------------------------------------------------------------------
    # create gene annotation from exon annotation
    gene_anno <- exons_to_genes(NanoMethViz::exons(nmr))
    # create log-methylation-ratio matrix
    lmr <- bsseq_to_log_methy_ratio(bss, regions = gene_anno)
    # --- Perform Dimensionality Reduction [] ---
    # Key functions: plot_mds, ggtitle, plot_pca
    ---------------------------------------------------------------------
    plot_mds(lmr) +
        ggtitle("MDS Plot")
    plot_pca(lmr) +
        ggtitle("PCA Plot")
    # --- Gsub [] ---
    # Key functions: _, plot_mds, ggtitle, scale_colour_brewer
    ---------------------------------------------------------------------
    new_labels <- gsub("B6Cast_Prom_", "", colnames(lmr))
    new_labels <- gsub("(\\d)_(.*)", "\\2 \\1", new_labels)
    groups <- gsub(" \\d", "", new_labels)
    plot_mds(lmr, labels = new_labels, groups = groups) +
    # --- Perform Dimensionality Reduction [] ---
    # Key functions: plot_mds, ggtitle, scale_colour_brewer
    ---------------------------------------------------------------------
    plot_mds(lmr, labels = NULL, groups = groups) +
        ggtitle("MDS Plot") +
        scale_colour_brewer(palette = "Set1")

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
