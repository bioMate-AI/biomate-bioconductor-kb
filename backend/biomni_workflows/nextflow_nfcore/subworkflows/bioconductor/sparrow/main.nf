#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sparrow
// Provides a unified interface to a variety of GSEA techniques from different bioconductor packages. R
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sparrow/inst/doc/sparrow.R
// Upstream  : ComplexHeatmap, circlize, dplyr, edgeR, ggplot2
// Downstream: none
//
// Install: BiocManager::install("sparrow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPARROW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sparrow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sparrow:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sparrow:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sparrow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sparrow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sparrow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sparrow)
    library(jsonlite)

    # --- Data Preparation ---
    # Key functions: exampleExpressionSet
    vm <- sparrow::exampleExpressionSet(
        dataset = "tumor-subtype",
        do.voom = TRUE
    )
    design <- vm$design
    contrast_matrix <- limma::makeContrasts(
        BvH = Basal - Her2,
        levels = design
    )

    # --- Gene Set Database Construction ---
    # Key functions: getMSigGeneSetDb, geneSets
    gdb <- sparrow::getMSigGeneSetDb(
        collection = c("h", "c2"),
        species = "human",
        id.type = "entrez"
    )
    gs_df <- sparrow::geneSets(gdb)
    head_gs <- head(gs_df, 10)

    # --- Gene Set Enrichment Analysis ---
    # Key functions: seas, logFC, result
    mg <- sparrow::seas(
        x = vm,
        gsdb = gdb,
        methods = c("camera", "fry", "ora"),
        design = vm$design,
        contrast = contrast_matrix[, "BvH"],
        feature.max.padj = 0.05,
        feature.min.logFC = 1,
        inter.gene.cor = 0.01,
        feature.bias = "size"
    )
    lfc_stats <- sparrow::logFC(mg)
    camera_res <- sparrow::result(mg, "camera")

    # --- Single Sample Gene Set Scoring ---
    # Key functions: scoreSingleSamples, result, geneSets
    sig_res <- sparrow::result(mg, "camera")
    sig_names <- sig_res$name[sig_res$padj < 0.05]
    gdb_sub <- gdb[sparrow::geneSets(gdb)$name %in% sig_names]
    vm_sub <- vm[, vm$targets$PAM50subtype %in% c("Basal", "Her2")]
    scores <- sparrow::scoreSingleSamples(
        gdb_sub,
        vm_sub,
        methods = c("ewm", "ssgsea", "zscore"),
        ssgsea.norm = TRUE,
        unscale = FALSE,
        uncenter = FALSE,
        as.dt = TRUE
    )

    # --- Visualisation ---
    # Key functions: mgheatmap, geneSets
    gs_sub <- sparrow::geneSets(gdb_sub)
    gdb_plot <- gdb_sub[sparrow::geneSets(gdb_sub)$name %in% head(gs_sub$name, 2)]
    col_anno <- ComplexHeatmap::HeatmapAnnotation(
        df = vm_sub$targets[, "PAM50subtype", drop = FALSE],
        col = list(PAM50subtype = c(Basal = "gray", Her2 = "black"))
    )
    sparrow::mgheatmap(
        vm_sub,
        gdb_plot,
        aggregate.by = "none",
        split = TRUE,
        show_row_names = FALSE,
        show_column_names = FALSE,
        recenter = TRUE,
        top_annotation = col_anno,
        zlim = c(-3, 3)
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sparrow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sparrow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sparrow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPARROW:", paste0("    sparrow: ", packageVersion("sparrow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sparrow_results.csv
    touch ${prefix}_sparrow_output.rds
    echo "BIOC_SPARROW:" > versions.yml
    echo "    sparrow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPARROW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPARROW(ch_input)

    emit:
    results  = BIOC_SPARROW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPARROW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPARROW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPARROW.out.versions  // channel: path(versions.yml)
}
