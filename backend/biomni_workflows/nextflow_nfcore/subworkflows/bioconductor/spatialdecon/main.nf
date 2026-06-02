#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialDecon
// Using spatial or bulk gene expression data, estimates abundance of mixed cell types within each obse
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialDecon/inst/doc/SpatialDecon_vignette.R
// Upstream  : Seurat, SeuratObject
// Downstream: none
//
// Install: BiocManager::install("SpatialDecon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALDECON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialdecon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialdecon:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialdecon:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialdecon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialdecon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialdecon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpatialDecon)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, mini_geomx_dataset, column, sweep
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    data("mini_geomx_dataset")
    norm = mini_geomx_dataset$normalized
    raw = mini_geomx_dataset$raw
    annot = mini_geomx_dataset$annot
    dim(raw)
    head(annot)
    raw[seq_len(5), seq_len(5)]

    # better segment names:
    colnames(norm) = colnames(raw) = rownames(annot) = 
    # use the NegProbe to estimate per-observation background
    per.observation.mean.neg = norm["NegProbe", ]
    # and define a background matrix in which each column (observation) is the
    # appropriate value of per-observation background:
    bg = sweep(norm * 0, 2, per.observation.mean.neg, "+")
    dim(bg)

    # --- Derivebg [] ---
    # Key functions: derive_GeoMx_background, rep, signif, heatmap, sweep, safeTME, safeTME.matches, download_profile_matrix
    bg2 = derive_GeoMx_background(norm = norm,
                                 probepool = rep(1, nrow(norm)),
                                 negnames = "NegProbe")
    data("safeTME")
    data("safeTME.matches")

    signif(safeTME[seq_len(3), seq_len(3)], 2)

    heatmap(sweep(safeTME, 1, apply(safeTME, 1, max), "/"),
            labRow = NA, margins = c(10, 5))
    mousespleen <- download_profile_matrix(species = "Mouse",
                                           age_group = "Adult", 
                                           matrixname = "Spleen_MCA")
    dim(mousespleen)

    mousespleen[1:4,1:4]

    head(cellGroups)

    metadata

    # --- Single Cell Data [] ---
    # Key functions: mini_singleCell_dataset, create_profile_matrix, heatmap, sweep, custom_mini_colon, CreateSeuratObject, Idents, GetAssayData
    data("mini_singleCell_dataset")

    mini_singleCell_dataset$mtx@Dim # genes x cells

    as.matrix(mini_singleCell_dataset$mtx)[1:4,1:4]

    head(mini_singleCell_dataset$annots)

    table(mini_singleCell_dataset$annots$LabeledCellType)
    # --- Runiss [] ---
    # Key functions: spatialdecon, str, heatmap
    res = spatialdecon(norm = norm,
                       bg = bg,
                       X = safeTME,
                       align_genes = TRUE)
    str(res)
    heatmap(res$beta, cexCol = 0.5, cexRow = 0.7, margins = c(10,7))
    str(safeTME.matches)

    # --- Runisstils [] ---
    # Key functions: spatialdecon, str, heatmap, sweep, par, for, rgb, abline
    # vector identifying pure tumor segments:
    annot$istumor = (annot$AOI.name == "Tumor")

    # run spatialdecon with all the bells and whistles:
    # --- Barplot [] ---
    # Key functions: layout, TIL_barplot, cellcols, prcomp, pmax, par, florets, frame
    # For reference, show the TILs color data object used by the plotting functions 
    # when safeTME has been used:
    data("cellcols")
    cellcols

    # show just the TME segments, since that's where the immune cells are:
    layout(mat = (matrix(c(1, 2), 1)), widths = c(7, 3))
    TIL_barplot(restils$cell.counts$cell.counts, draw_legend = TRUE, 
                cex.names = 0.5)
    # or the proportions of cells:
    # PCA of the normalized data:
    pc = prcomp(t(log2(pmax(norm, 1))))$x[, c(1, 2)]

    # run florets function:
    par(mar = c(5,5,1,1))
    layout(mat = (matrix(c(1, 2), 1)), widths = c(6, 2))
    florets(x = pc[, 1], y = pc[, 2],
            b = restils$beta, cex = 2,
            xlab = "PC1", ylab = "PC2")
    par(mar = c(0,0,0,0))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialdecon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialdecon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialdecon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALDECON:", paste0("    spatialdecon: ", packageVersion("SpatialDecon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialdecon_results.csv
    touch ${prefix}_spatialdecon_output.rds
    echo "BIOC_SPATIALDECON:" > versions.yml
    echo "    spatialdecon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALDECON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALDECON(ch_input)

    emit:
    results  = BIOC_SPATIALDECON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALDECON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALDECON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALDECON.out.versions  // channel: path(versions.yml)
}
