#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Heatplus
// Display a rectangular heatmap (intensity plot) of a data matrix. By default, both samples (columns) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Heatplus/inst/doc/annHeatmap.R
// Upstream  : Biobase, limma, mva
// Downstream: phenoTest, tRanslatome, heatmapFlex
//
// Install: BiocManager::install("Heatplus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HEATPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-heatplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-heatplus:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-heatplus:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_heatplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_heatplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_heatplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Heatplus)
    library(jsonlite)

    # --- Annotated Heatmap Generation [] ---
    # Key functions: annHeatmap
    ann1 <- annHeatmap(exprs(exdat), ann = pData(exdat))
    ann2 <- annHeatmap(
        exprs(exdat2),
        ann = pData(exdat2),
        cluster = list(cuth = 5000)
    )
    ann3 <- annHeatmap(
        exprs(exdat2),
        ann = pData(exdat2),
        cluster = list(cuth = 7500, label = c("Control-like", "Case-like"))
    )


    # --- Advanced Annotated Heatmap [] ---
    # Key functions: annHeatmap2
    ann4 <- annHeatmap2(
        exprs(exdat2),
        ann = list(Col = list(data = pData(exdat2)), Row = list(data = annFeatures))
    )
    ann4a <- annHeatmap2(
        exprs(exdat2),
        ann = list(Col = list(data = pData(exdat2)), Row = list(data = annFeatures)),
        labels = list(Row = list(nrow = 7), Col = list(nrow = 2))
    )


    # --- Annotation Conversion [] ---
    # Key functions: convAnnData
    ann1_conv <- convAnnData(pData(exdat2), inclRef = FALSE)[, 3:1]
    colnames(ann1_conv) <- c("Score", "isControl", "isMale")
    ann2_conv <- convAnnData(annFeatures, inclRef = FALSE)[, 3:1]
    colnames(ann2_conv) <- c("isTranslationalElongation", "isCorrelated", "SE")
    ann4c <- annHeatmap2(
        exprs(exdat2),
        ann = list(asIs = TRUE, Col = list(data = ann1_conv), Row = list(data = ann2_conv)),
        labels = list(Row = list(nrow = 7), Col = list(nrow = 2))
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_heatplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_heatplus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_heatplus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HEATPLUS:", paste0("    heatplus: ", packageVersion("Heatplus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heatplus_results.csv
    touch ${prefix}_heatplus_output.rds
    echo "BIOC_HEATPLUS:" > versions.yml
    echo "    heatplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HEATPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HEATPLUS(ch_input)

    emit:
    results  = BIOC_HEATPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HEATPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HEATPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HEATPLUS.out.versions  // channel: path(versions.yml)
}
