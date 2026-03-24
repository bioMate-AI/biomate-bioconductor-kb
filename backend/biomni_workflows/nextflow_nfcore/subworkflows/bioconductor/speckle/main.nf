#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: speckle
// The speckle package contains functions for the analysis of single cell RNA-seq data. The speckle pac
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/speckle/inst/doc/speckle.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("speckle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECKLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-speckle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-speckle:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-speckle:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_speckle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_speckle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_speckle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Load Sc Data [] ---
    # Key functions: load_sc_data
    ---------------------------------------------------------------------
    sc_data <- load_sc_data()
    # --- Seq Len [] ---
    # Key functions: sample
    ---------------------------------------------------------------------
    i.10x <- seq_len(ncol(sce_10x))
    i.celseq <- seq_len(ncol(sce_celseq))
    i.dropseq <- seq_len(ncol(sce_dropseq))
    set.seed(10)
    # --- Rep [] ---
    # Key functions: counts, SingleCellExperiment
    ---------------------------------------------------------------------
    sample <- rep(c("S1","S2","S3","S4","S5","S6"),
                    c(ncol(sce_10x),ncol(sce_10x_rep2),ncol(sce_celseq),
                    ncol(sce_celseq_rep2),
                    ncol(sce_dropseq),ncol(sce_dropseq_rep2)))
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts, runPCA, runUMAP
    ---------------------------------------------------------------------
    sce_all <- scater::logNormCounts(sce_all)
    sce_all <- scater::runPCA(sce_all)
    sce_all <- scater::runUMAP(sce_all)
    # --- Propeller [] ---
    # Key functions: propeller
    ---------------------------------------------------------------------
    # Perform logit transformation
    propeller(sce_all)
    # --- Rep [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    group <- rep(c("10x","celseq","dropseq"),each=2)
    pair <- rep(c(1,2),3)
    data.frame(group,pair)
    # --- Anova [] ---
    # Key functions: anova
    ---------------------------------------------------------------------
    propeller.anova(prop.list=props, design=design, coef = c(1,2,3),
                    robust=TRUE, trend=FALSE, sort=TRUE)
    # --- Makecontrasts [] ---
    # Key functions: makeContrasts, ttest
    ---------------------------------------------------------------------
    design
    mycontr <- makeContrasts(group10x-groupdropseq, levels=design)
    propeller.ttest(props, design, contrasts = mycontr, robust=TRUE, trend=FALSE,
                    sort=TRUE)
    # --- Rep [] ---
    # Key functions: lmFit, eBayes, topTable
    ---------------------------------------------------------------------
    group
    dose <- rep(c(1,2,3), each=2)
    des.dose <- model.matrix(~dose)
    des.dose
    # --- Lmfit [] ---
    # Key functions: lmFit, eBayes, topTable
    ---------------------------------------------------------------------
    fit.prop <- lmFit(props$Proportions,des.dose)
    fit.prop <- eBayes(fit.prop, robust=TRUE)
    topTable(fit.prop)
    # --- Matrix [] ---
    # Key functions: duplicateCorrelation
    ---------------------------------------------------------------------
    des.tech <- model.matrix(~group)
    dupcor <- duplicateCorrelation(props$TransformedProps, design=des.tech,
                                    block=pair)
    dupcor
    # --- Lmfit [] ---
    # Key functions: lmFit, eBayes, decideTests, topTable
    ---------------------------------------------------------------------
    # Fitting the linear model accounting for pair as a random effect
    fit1 <- lmFit(props$TransformedProps, design=des.tech, block=pair,
                    correlation=dupcor$consensus)
    fit1 <- eBayes(fit1)
    # --- Toptable [] ---
    # Key functions: topTable
    ---------------------------------------------------------------------
    topTable(fit1, coef=2:3)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("pbmc_props")
    pbmc.props <- pbmc_props$proportions
    pbmc.sample.info <- pbmc_props$sample_info
    tot.cells <- pbmc_props$total_cells
    # --- Convertdatatolist [] ---
    # Key functions: convertDataToList
    ---------------------------------------------------------------------
    prop.list <- convertDataToList(pbmc.props,data.type="proportions",
                                   transform="logit", scale.fac=tot.cells/20)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_speckle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_speckle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_speckle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECKLE:", paste0("    speckle: ", packageVersion("speckle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_speckle_results.csv
    touch ${prefix}_speckle_output.rds
    echo "BIOC_SPECKLE:" > versions.yml
    echo "    speckle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPECKLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPECKLE(ch_input)

    emit:
    results  = BIOC_SPECKLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPECKLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPECKLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPECKLE.out.versions  // channel: path(versions.yml)
}
