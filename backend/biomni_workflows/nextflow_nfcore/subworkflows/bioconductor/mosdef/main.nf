#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mosdef
// This package provides functionality to run a number of tasks in the differential expression analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mosdef/inst/doc/mosdef_userguide.R
// Upstream  : AnnotationDbi, DESeq2, ggplot2, macrophage, topGO
// Downstream: none
//
// Install: BiocManager::install("mosdef")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSDEF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosdef"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosdef:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosdef:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosdef_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosdef_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosdef_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mosdef)
    library(DESeq)
    library(DESeqDataSet)
    library(FoldChange)
    library(jsonlite)

    # --- Functional Enrichment [] ---
    # Key functions: run_topGO, run_goseq
    res_enrich_topGO <- run_topGO(
        de_container = dds_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        ontology = "BP",
        mapping = "org.Hs.eg.db",
        FDR_threshold = 0.05,
        gene_id = "symbol",
        de_type = "up_and_down",
        add_gene_to_terms = TRUE,
        topGO_method2 = "elim",
        min_counts = 20,
        top_de = 700,
        verbose = FALSE
    )
    res_enrich_goseq <- run_goseq(
        de_container = dds_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        mapping = "org.Hs.eg.db",
        testCats = "GO:BP"
    )


    # --- Differential Expression Visualization [] ---
    # Key functions: gene_plot, de_volcano, plot_ma
    g_plot <- gene_plot(
        de_container = dds_macrophage,
        gene = "ENSG00000125347",
        intgroup = "condition"
    )
    volc_plot <- de_volcano(
        res_de = res_macrophage_IFNg_vs_naive,
        mapping = "org.Hs.eg.db",
        logfc_cutoff = 1,
        FDR = 0.05,
        labeled_genes = 25
    )
    ma_plot <- plot_ma(
        res_de = res_macrophage_IFNg_vs_naive,
        FDR = 0.05,
        hlines = 1
    )


    # --- GO-Term Volcano Visualization [] ---
    # Key functions: go_volcano
    volc_go <- go_volcano(
        res_de = res_macrophage_IFNg_vs_naive,
        res_enrich = res_enrich_topGO,
        term_index = 1,
        logfc_cutoff = 1,
        FDR = 0.05,
        mapping = "org.Hs.eg.db",
        n_overlaps = 50,
        col_to_use = "symbol",
        enrich_col = "genes",
        down_col = "black",
        up_col = "black",
        highlight_col = "tomato"
    )


    # --- Interactive Table Generation [] ---
    # Key functions: deresult_to_df, buttonifier, de_table_painter
    res_subset <- deresult_to_df(
        res_de = res_macrophage_IFNg_vs_naive,
        FDR = 0.05
    )[1:100, ]
    res_buttons <- buttonifier(
        df = res_subset,
        col_to_use = "symbol",
        create_buttons_to = c("GC", "NCBI", "HPA"),
        ens_col = "id",
        ens_species = "Homo_sapiens",
        output_format = "DF"
    )
    painted_table <- de_table_painter(
        res_df = res_buttons,
        rounding_digits = 3,
        signif_digits = 5
    )


    # --- Database Link Integration [] ---
    # Key functions: create_link_ENSEMBL, create_link_GeneCards, create_link_PubMed, create_link_NCBI, create_link_GO
    res_subset <- deresult_to_df(
        res_de = res_macrophage_IFNg_vs_naive,
        FDR = 0.05
    )[1:100, ]
    res_subset$ensembl_link <- create_link_ENSEMBL(
        unlinked_vector = row.names(res_subset),
        species = "Homo_sapiens"
    )
    res_subset$symbol_GC <- create_link_GeneCards(res_subset$symbol)
    res_subset$symbol_PubMed <- create_link_PubMed(res_subset$symbol)
    res_subset$symbol_NCBI <- create_link_NCBI(res_subset$symbol)
    res_enrich_topGO$GO.ID <- create_link_GO(
        unlinked_vector = res_enrich_topGO$GO.ID
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosdef_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosdef_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosdef_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSDEF:", paste0("    mosdef: ", packageVersion("mosdef"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosdef_results.csv
    touch ${prefix}_mosdef_output.rds
    echo "BIOC_MOSDEF:" > versions.yml
    echo "    mosdef: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSDEF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSDEF(ch_input)

    emit:
    results  = BIOC_MOSDEF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSDEF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSDEF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSDEF.out.versions  // channel: path(versions.yml)
}
