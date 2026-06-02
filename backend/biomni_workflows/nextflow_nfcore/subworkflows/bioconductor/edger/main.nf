#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: edgeR
// Differential expression analysis of RNA-seq expression profiles with biological replication. Impleme
//
// Source : https://bioconductor.org/packages/3.20/workflows/vignettes/RNAseq123/inst/doc/limmaWorkflow.html
// Upstream  : none
// Downstream: ASpli, IntEREst, methylMnM, miloR, octad
//
// Install: BiocManager::install("edgeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-edger"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-edger:4.4.2--r44_0' :
        'quay.io/biocontainers/bioconductor-edger:4.4.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_edger_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_edger_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_edger_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(edgeR)
    library(jsonlite)

    # --- Normalization and MDS Plotting [] ---
    # Key functions: calcNormFactors, cpm, plotMDS
    x <- calcNormFactors(x, method = "TMM")
    lcpm <- cpm(x, log = TRUE)
    plotMDS(
        lcpm,
        labels = x$samples$group,
        col = as.numeric(x$samples$group)
    )


    # --- Differential Expression Analysis [] ---
    # Key functions: voom, lmFit, contrasts.fit, eBayes, decideTests
    design <- model.matrix(~0 + group + lane, data = x$samples)
    colnames(design) <- gsub("group", "", colnames(design))
    contr.matrix <- makeContrasts(
        BasalvsLP = Basal - LP,
        BasalvsML = Basal - ML,
        levels = colnames(design)
    )
    v <- voom(x, design, plot = FALSE)
    vfit <- lmFit(v, design)
    vfit <- contrasts.fit(vfit, contrasts = contr.matrix)
    efit <- eBayes(vfit)
    dt <- decideTests(efit)


    # --- Visualization and Gene Set Testing [] ---
    # Key functions: plotMD, camera, barcodeplot
    plotMD(efit, column = 1, status = dt[, 1])
    idx <- ids2indices(Mm.c2, id = rownames(v))
    cam.BasalvsLP <- camera(
        v,
        idx,
        design,
        contrast = contr.matrix[, 1]
    )
    barcodeplot(
        efit$t[, 1],
        index = idx$LIM_MAMMARY_LUMINAL_MATURE_UP
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_edger_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_edger_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_edger_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EDGER:", paste0("    edger: ", packageVersion("edgeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edger_results.csv
    touch ${prefix}_edger_output.rds
    echo "BIOC_EDGER:" > versions.yml
    echo "    edger: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EDGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EDGER(ch_input)

    emit:
    results  = BIOC_EDGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EDGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EDGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EDGER.out.versions  // channel: path(versions.yml)
}
