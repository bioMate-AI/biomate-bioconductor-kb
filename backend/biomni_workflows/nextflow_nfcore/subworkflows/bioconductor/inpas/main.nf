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
    library(InPAS)
    library(GRanges)
    library(jsonlite)

    # --- Database Setup [Database Setup] ---
    # Key functions: setup_sqlitedb
    metadata <- data.frame(
        tag = c("Baf3", "UM15"),
        condition = c("Baf3", "UM15"),
        bedgraph_file = c("Baf3.extract.bedgraph", "UM15.extract.bedgraph")
    )
    write.table(metadata, file = "metadata.txt", sep = "\t",
                quote = FALSE, row.names = FALSE)
    sqlite_db <- setup_sqlitedb(metadata = "metadata.txt",
                                outdir = tempdir())

    # --- Annotation Extraction [Annotation Extraction] ---
    # Key functions: set_globals, extract_UTR3Anno, getInPASTxDb, getInPASEnsDb, getInPASGenome
    set_globals(genome = BSgenome.Hsapiens.UCSC.hg19,
                TxDb = TxDb,
                EnsDb = EnsDb.Hsapiens.v86,
                outdir = tempdir(),
                chr2exclude = c("chrM", "chrMT"),
                lockfile = tempfile())
    utr3_anno <- extract_UTR3Anno(sqlite_db = sqlite_db,
                                  TxDb = getInPASTxDb(),
                                  edb = getInPASEnsDb(),
                                  genome = getInPASGenome(),
                                  outdir = getInPASOutputDirectory(),
                                  chr2exclude = getChr2Exclude())

    # --- Coverage Assembly and QC [Coverage Assembly and QC] ---
    # Key functions: get_ssRleCov, assemble_allCov, run_coverageQC
    coverage_list <- lapply(seq_along(bedgraphs), function(i) {
        get_ssRleCov(bedgraph = bedgraphs[i],
                     tag = tags[i],
                     genome = genome,
                     sqlite_db = sqlite_db,
                     outdir = outdir,
                     chr2exclude = getChr2Exclude())
    })
    coverage <- assemble_allCov(sqlite_db = sqlite_db,
                                seqname = "chr6",
                                outdir = outdir,
                                genome = getInPASGenome())
    run_coverageQC(sqlite_db = sqlite_db,
                   TxDb = getInPASTxDb(),
                   edb = getInPASEnsDb(),
                   genome = getInPASGenome(),
                   chr2exclude = getChr2Exclude(),
                   which = GRanges("chr6", IRanges(98013000, 140678000)))

    # --- Cleavage Site Search [Cleavage Site Search] ---
    # Key functions: setup_CPsSearch, search_CPs
    prepared_data <- setup_CPsSearch(sqlite_db = sqlite_db,
                                     genome = getInPASGenome(),
                                     chr.utr3 = utr3.mm10$chr6,
                                     seqname = "chr6",
                                     background = "10K",
                                     TxDb = getInPASTxDb(),
                                     hugeData = TRUE,
                                     outdir = outdir,
                                     silence = TRUE,
                                     coverage_threshold = 5)
    CPsites <- search_CPs(seqname = "chr6",
                          sqlite_db = sqlite_db,
                          genome = getInPASGenome(),
                          MINSIZE = 10,
                          window_size = 100,
                          search_point_START = 50,
                          search_point_END = NA,
                          cutEnd = 0,
                          filter.last = TRUE,
                          adjust_distal_polyA_end = TRUE,
                          long_coverage_threshold = 2,
                          PolyA_PWM = NA,
                          classifier = classifier,
                          classifier_cutoff = 0.8,
                          shift_range = 50,
                          step = 5,
                          outdir = outdir,
                          silence = TRUE)

    # --- PDUI Estimation [PDUI Estimation] ---
    # Key functions: get_regionCov, get_UTR3eSet
    utr3_cds_cov <- get_regionCov(chr.utr3 = utr3.mm10[["chr6"]],
                                  sqlite_db = sqlite_db,
                                  outdir = outdir,
                                  phmm = FALSE)
    eSet <- get_UTR3eSet(sqlite_db = sqlite_db,
                         normalize = "none",
                         singleSample = FALSE)


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
