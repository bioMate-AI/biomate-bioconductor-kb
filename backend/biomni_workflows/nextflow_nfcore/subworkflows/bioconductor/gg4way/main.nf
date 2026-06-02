#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gg4way
// 4way plots enable a comparison of the logFC values from two contrasts of differential gene expressio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gg4way/inst/doc/gg4way.R
// Upstream  : DESeq2, airway, edgeR, limma, purrr
// Downstream: none
//
// Install: BiocManager::install("gg4way")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GG4WAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gg4way"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gg4way:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gg4way:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_gg4way_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gg4way_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gg4way_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gg4way)
    library(DESeq)
    library(DESeqDataSet)
    library(SE2DGEList)
    library(jsonlite)

    # --- Data Preparation and Conversion [SE2DGEList] ---
    # Key functions: SE2DGEList
    dge <- se |>
        SE2DGEList()
    design <- model.matrix(~ 0 + cell + dex, data = dge$samples)
    colnames(design) <- gsub("cell", "", colnames(design))
    contr.matrix <- limma::makeContrasts(
        N61311 - N052611,
        N061011 - N052611,
        levels = c("N052611", "N061011", "N080611", "N61311", "dexuntrt")
    )
    keep <- edgeR::filterByExpr(dge, design)
    dge <- dge[keep, ]

    # --- Four-way Comparison Plotting [gg4way] ---
    # Key functions: gg4way
    efit <- dge |>
        edgeR::calcNormFactors() |>
        limma::voom(design) |>
        limma::lmFit(design) |>
        limma::contrasts.fit(contrasts = contr.matrix) |>
        limma::eBayes()
    p1 <- efit |>
        gg4way(
            x = "N61311 vs N052611",
            y = "N061011 vs N052611",
            label = c("PSG5", "ERAP2")
        )

    # --- Extracting Plot Statistics and Shared Genes [getTotals, getShared, getCor] ---
    # Key functions: getTotals, getShared, getCor
    textTable <- p1 |>
        getTotals()
    sharedGenes <- p1 |>
        getShared()
    correlationVal <- p1 |>
        getCor()

    # --- DESeq2 Integration and Plotting [gg4way] ---
    # Key functions: gg4way
    ddsSE <- DESeq2::DESeqDataSet(se, design = ~ cell + dex)
    keep <- apply(DESeq2::counts(ddsSE), 1, function(gene) all(gene != 0))
    dds <- DESeq2::DESeq(ddsSE[keep, ])
    contrast_list <- list(
        "N61311 vs N052611" = c("cell", "N61311", "N052611"),
        "N061011 vs N052611" = c("cell", "N061011", "N052611")
    )
    res_list <- lapply(contrast_list, function(x) {
        DESeq2::results(dds, contrast = x)
    })
    p2 <- res_list |>
        gg4way(x = "N61311 vs N052611", y = "N061011 vs N052611")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gg4way_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gg4way_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gg4way_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GG4WAY:", paste0("    gg4way: ", packageVersion("gg4way"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gg4way_results.csv
    touch ${prefix}_gg4way_output.rds
    echo "BIOC_GG4WAY:" > versions.yml
    echo "    gg4way: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GG4WAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_GG4WAY(ch_input)

    emit:
    results  = BIOC_GG4WAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GG4WAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GG4WAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GG4WAY.out.versions  // channel: path(versions.yml)
}
