#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SynExtend
// Shared order between genomic sequences provide a great deal of information. Synteny objects produced
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SynExtend/inst/doc/UsingSynExtend.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SynExtend")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNEXTEND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synextend"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synextend:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synextend:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synextend_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synextend_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synextend_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DisjointSet)
    library(ExtractBy)
    library(FindSynteny)
    library(NucleotideOverlap)
    library(PairSummaries)
    library(jsonlite)

    # --- build synteny object [] ---
    # Key functions: FindSynteny
    library(SynExtend)
    DBPATH <- system.file("extdata",
    Syn <- FindSynteny(dbFile = DBPATH)
    # --- generate genecalls [] ---
    # Key functions: gffToDataFrame
    GC <- gffToDataFrame(GFF = system.file("extdata",
    GeneCalls <- get(data("Endosymbionts_GeneCalls", package = "SynExtend"))
    # --- show rtracklayer [] ---
    # Key functions: import
    X01 <- rtracklayer::import(system.file("extdata",
    class(X01)
    print(X01)
    # --- generate initial links [] ---
    # Key functions: NucleotideOverlap
    Links <- NucleotideOverlap(SyntenyObject = Syn,
    # --- Pair Summaries [] ---
    # Key functions: PairSummaries
    LinkedPairs1 <- PairSummaries(SyntenyLinks = Links,
    # --- pairsummariesoperations [] ---
    # Key functions: DisjointSet
    SingleLinkageClusters <- DisjointSet(Pairs = LinkedPairs1,
    # --- Extract By [] ---
    # Key functions: ExtractBy
    Sets <- ExtractBy(x = LinkedPairs1,
    head(Sets)
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synextend_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synextend_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synextend_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNEXTEND:", paste0("    synextend: ", packageVersion("SynExtend"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synextend_results.csv
    touch ${prefix}_synextend_output.rds
    echo "BIOC_SYNEXTEND:" > versions.yml
    echo "    synextend: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNEXTEND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNEXTEND(ch_input)

    emit:
    results  = BIOC_SYNEXTEND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNEXTEND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNEXTEND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNEXTEND.out.versions  // channel: path(versions.yml)
}
