#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: escape
// A bridging R package to facilitate gene set enrichment analysis (GSEA) in the context of single-cell
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/escape/inst/doc/vignette.R
// Upstream  : BiocStyle, RColorBrewer, Seurat, SeuratObject, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("escape")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ESCAPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-escape"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-escape:2.2.3--r44_0' :
        'quay.io/biocontainers/bioconductor-escape:2.2.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_escape_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_escape_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_escape_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FindAllMarkers)
    library(jsonlite)

    # --- Getgenesets [] ---
    # Key functions: getGeneSets
    ---------------------------------------------------------------------
    GS.hallmark <- getGeneSets(library = "H")
    # --- Performnormalization [] ---
    # Key functions: performNormalization
    ---------------------------------------------------------------------
    pbmc_small <- performNormalization(sc.data = pbmc_small,
                                       assay = "escape.ssGSEA",
                                       gene.sets = GS.hallmark)
    # --- Heatmapenrichment [] ---
    # Key functions: heatmapEnrichment
    ---------------------------------------------------------------------
    heatmapEnrichment(pbmc_small,
                      group.by = "ident",
                      gene.set.use = "all",
                      assay = "escape.ssGSEA")
    # --- Pals [] ---
    # Key functions: pals
    ---------------------------------------------------------------------
    hcl.pals()
    # --- Heatmapenrichment [] ---
    # Key functions: heatmapEnrichment
    ---------------------------------------------------------------------
    heatmapEnrichment(pbmc_small,
                      assay = "escape.ssGSEA",
                      palette = "Spectral")
    # --- Heatmapenrichment [] ---
    # Key functions: heatmapEnrichment, scale_fill_gradientn, pal
    ---------------------------------------------------------------------
    heatmapEnrichment(sce.pbmc,
                      group.by = "ident",
                      assay = "escape.UCell") +
      scale_fill_gradientn(colors = rev(brewer.pal(11, "RdYlBu")))
    # --- Geyserenrichment [] ---
    # Key functions: geyserEnrichment
    ---------------------------------------------------------------------
    geyserEnrichment(pbmc_small,
                     assay = "escape.ssGSEA",
                     gene.set = "HALLMARK-INTERFERON-GAMMA-RESPONSE")
    # --- Ridgeenrichment [] ---
    # Key functions: ridgeEnrichment
    ---------------------------------------------------------------------
    ridgeEnrichment(sce.pbmc,
                    assay = "escape.UCell",
                    gene.set = "HALLMARK-IL2-STAT5-SIGNALING")
    # --- Splitenrichment [] ---
    # Key functions: splitEnrichment
    ---------------------------------------------------------------------
    splitEnrichment(pbmc_small,
                    assay = "escape.ssGSEA",
                    gene.set = "HALLMARK-IL2-STAT5-SIGNALING",
                    split.by = "groups")
    # --- Scatterenrichment [] ---
    # Key functions: scatterEnrichment
    ---------------------------------------------------------------------
    scatterEnrichment(pbmc_small,
                      assay = "escape.ssGSEA",
                      x.axis = "HALLMARK-INTERFERON-GAMMA-RESPONSE",
                      y.axis = "HALLMARK-IL6-JAK-STAT3-SIGNALING")
    # --- Performpca [] ---
    # Key functions: performPCA
    ---------------------------------------------------------------------
    pbmc_small <- performPCA(pbmc_small,
                             assay = "escape.ssGSEA",
                             n.dim = 1:10)
    # --- Pcaenrichment [] ---
    # Key functions: pcaEnrichment
    ---------------------------------------------------------------------
    pcaEnrichment(pbmc_small,
                  dimRed = "escape.PCA",
                  x.axis = "PC1",
                  y.axis = "PC2")
    # --- Performnormalization [] ---
    # Key functions: performNormalization, FindAllMarkers
    ---------------------------------------------------------------------
    pbmc_small <- performNormalization(pbmc_small,
                                       assay = "escape.ssGSEA",
                                       gene.sets = GS.hallmark,
                                       make.positive = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_escape_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_escape_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_escape_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ESCAPE:", paste0("    escape: ", packageVersion("escape"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_escape_results.csv
    touch ${prefix}_escape_output.rds
    echo "BIOC_ESCAPE:" > versions.yml
    echo "    escape: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ESCAPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ESCAPE(ch_input)

    emit:
    results  = BIOC_ESCAPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ESCAPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ESCAPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ESCAPE.out.versions  // channel: path(versions.yml)
}
