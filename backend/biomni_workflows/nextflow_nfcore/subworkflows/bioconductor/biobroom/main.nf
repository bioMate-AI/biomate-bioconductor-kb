#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biobroom
// This package contains methods for converting standard objects constructed by bioinformatics packages
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biobroom/inst/doc/biobroom_vignette.R
// Upstream  : Biobase, DESeq2, MSnbase, airway, dplyr
// Downstream: none
//
// Install: BiocManager::install("biobroom")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOBROOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biobroom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biobroom:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biobroom:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biobroom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biobroom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biobroom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(DGEList)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: qvalue
    ---------------------------------------------------------------------
    library(qvalue)
    data(hedenfalk)
    qobj <- qvalue(hedenfalk$p)
    names(qobj)
    # --- Head [] ---
    # Key functions: tidy, augment, glance
    ---------------------------------------------------------------------
    library(biobroom)
    # use tidy/augment/glance to restructure the qvalue object
    head(tidy(qobj))
    head(augment(qobj))
    # --- Frame [] ---
    # Key functions: frame, augment
    ---------------------------------------------------------------------
    # create sample names
    df <- data.frame(gene = 1:length(hedenfalk$p))
    head(augment(qobj, data = df))
    # --- Ggplot [] ---
    # Key functions: ggplot, augment, aes, geom_point, ggtitle, theme_bw
    ---------------------------------------------------------------------
    library(ggplot2)
    # use augmented data to compare p-values to q-values
    ggplot(augment(qobj), aes(p.value, q.value)) + geom_point() +
      ggtitle("Simulated P-values versus Computed Q-values") + theme_bw()
    # --- Augment [] ---
    # Key functions: augment, filter
    ---------------------------------------------------------------------
    library(dplyr)
    # Find significant genes under 0.05 threshold
    sig.genes <- augment(qobj) %>% filter(q.value < 0.05)
    head(sig.genes)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(DESeq2)
    library(airway)
    data(airway)
    airway_se <- airway
    # --- Deseqdataset [] ---
    # Key functions: DESeqDataSet, tidy
    ---------------------------------------------------------------------
    airway_dds <- DESeqDataSet(airway_se, design = ~cell + dex)
    head(tidy(airway_dds))
    # --- Deseq [] ---
    # Key functions: DESeq, results, tidy
    ---------------------------------------------------------------------
    # differential expression analysis
    deseq <- DESeq(airway_dds)
    results <- results(deseq)
    # tidy results
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point, ggtitle, theme_bw
    ---------------------------------------------------------------------
    ggplot(tidy_results, aes(x=estimate, y=log(p.value),
                             color=log(baseMean))) + geom_point(alpha=0.5) +
      ggtitle("Volcano Plot For Airway Data via DESeq2") + theme_bw()
    # --- Data [] ---
    # Key functions: exprs, phenoData, DGEList, calcNormFactors, estimateCommonDisp, estimateTagwiseDisp
    ---------------------------------------------------------------------
    library(edgeR)
    data(hammer)
    hammer.counts <- Biobase::exprs(hammer)[, 1:4]
    hammer.treatment <- Biobase::phenoData(hammer)$protocol[1:4]
    # --- Head [] ---
    # Key functions: tidy
    ---------------------------------------------------------------------
    head(tidy(et))
    # --- Glance [] ---
    # Key functions: glance
    ---------------------------------------------------------------------
    glance(et, alpha = 0.05)
    # --- Ggplot [] ---
    # Key functions: ggplot, tidy, aes, geom_point, ggtitle, theme_bw
    ---------------------------------------------------------------------
    ggplot(tidy(et), aes(x=estimate, y=log(p.value), color=logCPM)) +
      geom_point(alpha=0.5) + ggtitle("Volcano Plot for Hammer Data via EdgeR") +
      theme_bw()
    # --- Matrix [] ---
    # Key functions: rnorm, frame
    ---------------------------------------------------------------------
    # create random data and design
    dat <- matrix(rnorm(1000), ncol=4)
    dat[, 1:2] <- dat[, 1:2] + .5  # add an effect
    rownames(dat) <- paste0("g", 1:nrow(dat))
    # --- Lmfit [] ---
    # Key functions: lmFit, eBayes, tidy
    ---------------------------------------------------------------------
    lfit <- lmFit(dat, model.matrix(~ treatment + confounding, des))
    eb <- eBayes(lfit)
    head(tidy(lfit))
    head(tidy(eb))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biobroom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biobroom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biobroom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOBROOM:", paste0("    biobroom: ", packageVersion("biobroom"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biobroom_results.csv
    touch ${prefix}_biobroom_output.rds
    echo "BIOC_BIOBROOM:" > versions.yml
    echo "    biobroom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOBROOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOBROOM(ch_input)

    emit:
    results  = BIOC_BIOBROOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOBROOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOBROOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOBROOM.out.versions  // channel: path(versions.yml)
}
