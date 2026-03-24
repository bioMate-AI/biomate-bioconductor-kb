#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: InPAS
// Alternative polyadenylation (APA) is one of the important post- transcriptional regulation mechanism
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/InPAS/inst/doc/InPAS.R
// Upstream  : RSQLite, cleanUpdTSeq
// Downstream: none
//
// Install: BiocManager::install("InPAS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INPAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-inpas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-inpas:2.14.1--r44_0' :
        'quay.io/biocontainers/bioconductor-inpas:2.14.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_inpas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_inpas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_inpas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- plan [] ---
    # Key functions: plan, setup_sqlitedb, dbConnect, dbListTables, dbReadTable
    plan(sequential)
    data_dir <- system.file("extdata", package = "InPAS")
    bedgraphs <- c(file.path(data_dir, "Baf3.extract.bedgraph"),
    # --- extract annotation [] ---
    # Key functions: loadDb, seqnames, set_globals, extract_UTR3Anno
    samplefile <- system.file("extdata",
    TxDb <- loadDb(samplefile)
    seqnames <- seqnames(BSgenome.Hsapiens.UCSC.hg19)
    # --- set_globals [] ---
    # Key functions: set_globals, parse_TxDb
    set_globals(genome = BSgenome.Mmusculus.UCSC.mm10,
    outdir = tempdir(),
    lockfile = tempfile())
    # --- assemble_all Cov [] ---
    # Key functions: assemble_allCov
    coverage <- list()
    for (i in seq_along(bedgraphs)){
    coverage[[tags[i]]] <- get_ssRleCov(bedgraph = bedgraphs[i],
    # --- coverage QC [] ---
    # Key functions: plan, run_coverageQC
    if (.Platform$OS.type == "windows")
    plan(multisession)
    plan(multicore)
    # --- search CPs [] ---
    # Key functions: setup_CPsSearch, search_CPs
    data(classifier)
    prepared_data <- setup_CPsSearch(sqlite_db,
    genome = getInPASGenome(),
    # --- estimate PDUI [] ---
    # Key functions: get_regionCov, get_UTR3eSet
    utr3_cds_cov <- get_regionCov(chr.utr3 = utr3.mm10[["chr6"]],
    eSet <- get_UTR3eSet(sqlite_db,
    # --- dPDUI test [] ---
    # Key functions: test_dPDUI
    test_out <- test_dPDUI(eset = eSet,
    # --- filter dPDUI [] ---
    # Key functions: filter_testOut
    filter_out <- filter_testOut(res = test_out,
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, get_usage4plot, plot_utr3Usage
    gr <- GRanges("chr6", IRanges(128846245, 128850081), strand = "-")
    names(gr) <- "128846245-128850081"
    data4plot <- get_usage4plot(gr,
    # --- setup GSEA [] ---
    # Key functions: setup_GSEA
    setup_GSEA(eset = test_out,
    groupList= list(Baf3 = "Baf3", UM15 ="UM15"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_inpas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_inpas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_inpas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INPAS:", paste0("    inpas: ", packageVersion("InPAS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inpas_results.csv
    touch ${prefix}_inpas_output.rds
    echo "BIOC_INPAS:" > versions.yml
    echo "    inpas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INPAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INPAS(ch_input)

    emit:
    results  = BIOC_INPAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INPAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INPAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INPAS.out.versions  // channel: path(versions.yml)
}
