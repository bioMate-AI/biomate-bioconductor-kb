#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ProteoDisco
// ProteoDisco is an R package to facilitate proteogenomics studies. It houses functions to create cust
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ProteoDisco/inst/doc/Overview_ProteoDisco.R
// Upstream  : knitr, plyr, dplyr, ggplot2, reshape2
// Downstream: none
//
// Install: BiocManager::install("ProteoDisco")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEODISCO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proteodisco"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proteodisco:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proteodisco:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proteodisco_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proteodisco_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proteodisco_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AAStringSetList)
    library(DNAString)
    library(DataFrame)
    library(jsonlite)

    # --- label = 'Export FASTA' [] ---
    # Key functions: exportProteoDiscography
    ProteoDisco::exportProteoDiscography(
    # --- label = 'Logging options' [] ---
    # Key functions: clearLoggers, registerLogger
    ParallelLogger::clearLoggers()
    ParallelLogger::registerLogger(ParallelLogger::createLogger(threshold = 'TRACE', appenders =list(ParallelLogger::createConsoleAppender(layout = ParallelLogger::layoutTimestamp))))
    ParallelLogger::clearLoggers()
    # --- label = 'TxDb from FASTA and GTF' [] ---
    # Key functions: makeTxDbFromGFF, readDNAStringSet, generateProteoDiscography
    utils::download.file(URL.annotations, basename(URL.annotations))
    utils::download.file(URL.genome, basename(URL.genome))
    TxDb <- GenomicFeatures::makeTxDbFromGFF(
    # --- label = 'Inspect example ProteoDiscrography (GRCh37)' [] ---
    # Key functions: melt, ggplot, geom_bar, scale_y_continuous
    library(ggplot2)
    summary(ProteoDiscography.hg19, verbose = FALSE)
    z <- summary(ProteoDiscography.hg19, verbose = FALSE)
    # --- label = 'Add manual transcript sequences' [] ---
    # Key functions: DNAString, DataFrame
    testSeq1 <- Biostrings::DNAString('ATGACCGCGTCCTCCTCCAGCGACTATGGACAGACTTCCAAGATGAGCCCACGCGTCCCTCAGCAGGATTGGCTGTCTCAACCCCCAGCCAGGGTCACCATCAAAATGGAATGTAACCCTAGCCAGGTGAATGGCTCAAGGAACTCTCCTGATGAATGCAGTGTGGCCAAAGGCGGGAAGATGGTGGGCAGCCCAGACACCGTTGGGATGAACTACGGCAGCTACATGGAGGAGAAGCACATGCCACCCCCAAACATGACCACGAACGAGCGCAGAGTTATCGTGCCAGCAGATCCTACGCTATGGAGTACAGACCATGTGCGGCAGTGGCTGGAGTGGGCGGTGAAAGAATATGGCCTTCCAGACGTCAACATCTTGTTATTCCAGAACATCGATGGGAAGGAACTGTGCAAGATGACCAAGGACGACTTCCAGAGGCTCACCCCCAGCTACAACGCCGACATCCTTCTCTCACATCTCCACTACCTCAGAGAGACTCCTCTTCCACATTTGACTTCAGATGATGTTGATAAAGCCTTACAAAACTCTCCACGGTTAATGCATGCTAGAAACACAGGGGGTGCAGCTTTTATTTTCCCAAATACTTCAGTATATCCTGAAGCTACGCAAAGAATTACAACTAGGCCAGTCTCTTACAGATAA')
    testSeq2 <- Biostrings::DNAString('ATGATGAGTCTCCGGGGCTCTATGGGTTTCTGAATGTCATCGTCCACTCAGCCACTGGATTTAAGCAGAGTTCAAAAGCCCTTCAGCGGCCAGTAGCATCTGACTTTGAGCCTCAGGGTCTGAGTGAAGCCGCTCGTTGGAACTCCAAGGAAAACCTTCTCGCTGGACCCAGTGAAAATGACCCCAACCTTTTCGTTGCACTGTATGATTTTGTGGCCAGTGGAGATAACACTCTAAGCATAACTAAAGGTGAAAAGCTCCGGGTCTTAGGCTATAATCACAATGGGGAATGGTTTGAAGCCCAAACCAAAAATGGCCAAGGCTGGGTCCCAAGCAACTACATCACGCCAGTCAACAGTCTGGAGAAACACTCCTGGTACCATGGGCCTGTGTCCCGCAATGCCGCTGAGTATCTGCTGAGCAGCGGGATCAAT')
    manualSeq <- S4Vectors::DataFrame(
    # --- label = 'View imported ProteoDiscography records' [] ---
    # Key functions: getDiscography
    getDiscography(ProteoDiscography.hg19)
    # --- label = 'Inspection post [] ---
    # Key functions: mutantTranscripts
    summary(ProteoDiscography.hg19)
    This will retrieve a list of all the generated (and imported) transcript sequences per input type and the respective amino-acid sequence.
    x <- ProteoDisco::mutantTranscripts(ProteoDiscography.hg19)
    # --- label = 'Subsetting' [] ---
    # Key functions: mutantTranscripts
    x <- ProteoDisco::mutantTranscripts(ProteoDiscography.hg19)
    ProteoDiscography.hg19.subset <- ProteoDisco::setMutantTranscripts(ProteoDiscography.hg19, x[1:10,], slotType = 'genomicVariants')
    y <- ProteoDisco::mutantTranscripts(ProteoDiscography.hg19.subset)
    # --- label = 'Import splice [] ---
    # Key functions: read_tsv
    files.Splicing <- c(
    system.file('extdata', 'spliceJunctions_pyQUILTS_chr22.bed', package = 'ProteoDisco')
    ProteoDiscography.hg19 <- ProteoDisco::importSpliceJunctions(
    # --- label = 'Check proteotypic fragments.' [] ---
    # Key functions: AAStringSetList, unlist, mutantTranscripts
    peptides.SwissProt <- base::textConnection(RCurl::getURL('https://www.uniprot.org/uniprot/?query=*&format=fasta&limit=100&fil=organism:%22Homo%20sapiens%20(Human)%20[9606]%22%20AND%20reviewed:yes')) %>%
    seqinr::read.fasta(., seqtype = 'AA', seqonly = FALSE, as.string = TRUE) %>%
    Biostrings::AAStringSetList() %>%
    # --- label = 'Converting gene symbols' [] ---
    # Key functions: mutantTranscripts
    require(org.Hs.eg.db)
    x <- ProteoDisco::mutantTranscripts(ProteoDiscography.hg19)
    geneSymbols <- unique(AnnotationDbi::select(
    # --- label = 'Export mutant proteins to FASTA' [] ---
    # Key functions: exportProteoDiscography
    ProteoDisco::exportProteoDiscography(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proteodisco_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proteodisco_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proteodisco_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTEODISCO:", paste0("    proteodisco: ", packageVersion("ProteoDisco"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteodisco_results.csv
    touch ${prefix}_proteodisco_output.rds
    echo "BIOC_PROTEODISCO:" > versions.yml
    echo "    proteodisco: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTEODISCO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTEODISCO(ch_input)

    emit:
    results  = BIOC_PROTEODISCO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTEODISCO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTEODISCO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTEODISCO.out.versions  // channel: path(versions.yml)
}
