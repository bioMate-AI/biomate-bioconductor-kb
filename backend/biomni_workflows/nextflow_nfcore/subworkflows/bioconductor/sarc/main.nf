#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SARC
// Imports a cov/coverage file (normalised read coverages from BAM files) and a cnv file (list of CNVs 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SARC/inst/doc/SARC_guide.R
// Upstream  : GenomicAlignments, ggplot2, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("SARC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SARC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sarc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sarc:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sarc:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sarc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sarc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sarc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TxDb)
    library(jsonlite)

    # --- kable_styling [] ---
    # Key functions: kable_styling, scroll_box
    data("test_cnv")
    head(test_cnv) %>%
    kable_styling("striped", full_width=FALSE) %>%
    # --- region Set [] ---
    # Key functions: regionSet, regionSplit
    SARC <- regionSet(cnv = test_cnv, test_cov)
    SARC <- regionSplit(RE = SARC, #the raggedexpression object we made
    cnv = metadata(SARC)[['CNVlist']][[1]],
    # --- region Mean [] ---
    # Key functions: regionMean
    SARC <- regionMean(RE = SARC,
    splitcov =  metadata(SARC)[[4]]) #list of cnv specific coverage
    # --- region Quantiles [] ---
    # Key functions: regionQuantiles
    SARC <- regionQuantiles(RE = SARC,
    cnv = metadata(SARC)[['CNVlist']][[2]], #new cnv file
    meancov = metadata(SARC)[[5]], #list of cnv specific coverage + means
    # --- prep Anova [] ---
    # Key functions: prepAnova, anovaOnCNV, kable_styling, scroll_box
    SARC <- prepAnova(RE = SARC,
    start = metadata(SARC)[[2]],
    end = metadata(SARC)[[3]],
    # --- set up plot [] ---
    # Key functions: TxDb, transcriptsBy, plotCovPrep, regionGrangeMake, addExonsGenes
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(Homo.sapiens) #load genome specific libraries from BioConductor
    TxDb(Homo.sapiens) <- TxDb.Hsapiens.UCSC.hg38.knownGene
    # --- plot CNVs [] ---
    # Key functions: plotCNV
    plotCNV(cnv = metadata(SARC)[['CNVlist']][[4]],
    setup = metadata(SARC)[[12]],
    # --- cnv Confidence [] ---
    # Key functions: cnvConfidence, kable_styling, scroll_box
    SARC <- cnvConfidence(RE = SARC, cnv = metadata(SARC)[['CNVlist']][[4]])
    head(metadata(SARC)[['CNVlist']][[5]]) %>%
    kable_styling("striped", full_width=FALSE) %>%
    # --- check distribution of reads [] ---
    # Key functions: setQDplot, seeDist
    SARC <- setQDplot(RE = SARC, meancov = metadata(SARC)[[5]])
    seeDist(meanList = metadata(SARC)[[13]],
    cnv = metadata(SARC)[['CNVlist']][[5]],
    # --- exon numbers and gene names [] ---
    # Key functions: pasteExonsGenes, metadata, kable_styling, scroll_box
    SARC <- pasteExonsGenes(RE = SARC,
    setup =  metadata(SARC)[[12]], #list of dataframes from the setupCNVplot function
    cnv = metadata(SARC)[['CNVlist']][[5]]) #cnv file to add an extra column to
    # --- ph Dunneton C N V [] ---
    # Key functions: phDunnetonCNV, cnvConfidence
    DNA <- phDunnetonCNV(RE = DNA,
    cnv = metadata(SARC)[['CNVlist']][[4]],
    anovacov = metadata(SARC)[[8]])
    # --- expanded plotCNV [] ---
    # Key functions: plotCNV, ggsave
    data("test_cnv2")
    library(ggplot2)
    for (i in seq_len(nrow(test_cnv2))) {
    # --- Tx Db [] ---
    # Key functions: TxDb, transcriptsBy
    require(TxDb.Mmusculus.UCSC.mm10.knownGene)
    require(Mus.musculus) # load genome specific libraries from BioConductor
    TxDb(Mus.musculus) <- TxDb.Mmusculus.UCSC.mm10.knownGene
    # --- Compute genomic coverage [] ---
    # Key functions: coverage
    require(GenomicAlignments)
    bam <- system.file("extdata", "test.bam", package="SARC")
    coverage <- coverage(bam)
    # --- cbind [] ---
    # Key functions: cbind
    load(system.file("extdata", "test_cov_raw.rda", package="SARC"))
    load(system.file("extdata", "librarySizes.rda", package="SARC"))
    normalised_counts <- t(t(test_cov[, 5:ncol(test_cov)]) / libsizes$PerMillion)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sarc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sarc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sarc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SARC:", paste0("    sarc: ", packageVersion("SARC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sarc_results.csv
    touch ${prefix}_sarc_output.rds
    echo "BIOC_SARC:" > versions.yml
    echo "    sarc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SARC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SARC(ch_input)

    emit:
    results  = BIOC_SARC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SARC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SARC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SARC.out.versions  // channel: path(versions.yml)
}
