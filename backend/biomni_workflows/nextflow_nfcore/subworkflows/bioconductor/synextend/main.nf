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
    library(SynExtend)
    library(DisjointSet)
    library(ExtractBy)
    library(FindSynteny)
    library(NucleotideOverlap)
    library(PairSummaries)
    library(jsonlite)

    # --- Synteny Detection [synplots01] ---
    # Key functions: FindSynteny, pairs
    db_path <- system.file(
        "extdata",
        "Endosymbionts_v02.sqlite",
        package = "SynExtend"
    )
    syn_obj <- FindSynteny(dbFile = db_path)
    pairs(syn_obj)

    # --- Gene Call Processing [generate_genecalls] ---
    # Key functions: gffToDataFrame
    gff_file <- system.file(
        "extdata",
        "GCF_021065005.1_ASM2106500v1_genomic.gff.gz",
        package = "SynExtend"
    )
    gene_calls_df <- gffToDataFrame(GFF = gff_file, Verbose = TRUE)

    # --- Nucleotide Overlap Detection [generate_initial_links] ---
    # Key functions: NucleotideOverlap, FindSynteny
    db_path <- system.file(
        "extdata",
        "Endosymbionts_v02.sqlite",
        package = "SynExtend"
    )
    syn_obj <- FindSynteny(dbFile = db_path)
    data("Endosymbionts_GeneCalls", package = "SynExtend")
    links <- NucleotideOverlap(
        SyntenyObject = syn_obj,
        GeneCalls = Endosymbionts_GeneCalls,
        Verbose = TRUE
    )

    # --- Pair Summarization [describe_links] ---
    # Key functions: PairSummaries, NucleotideOverlap, FindSynteny
    db_path <- system.file(
        "extdata",
        "Endosymbionts_v02.sqlite",
        package = "SynExtend"
    )
    syn_obj <- FindSynteny(dbFile = db_path)
    data("Endosymbionts_GeneCalls", package = "SynExtend")
    links <- NucleotideOverlap(
        SyntenyObject = syn_obj,
        GeneCalls = Endosymbionts_GeneCalls,
        Verbose = FALSE
    )
    linked_pairs <- PairSummaries(
        SyntenyLinks = links,
        DBPATH = db_path,
        PIDs = FALSE,
        Verbose = TRUE
    )

    # --- Clustering and Extraction [pairsummariesoperations] ---
    # Key functions: DisjointSet, ExtractBy, PairSummaries
    db_path <- system.file(
        "extdata",
        "Endosymbionts_v02.sqlite",
        package = "SynExtend"
    )
    syn_obj <- FindSynteny(dbFile = db_path)
    data("Endosymbionts_GeneCalls", package = "SynExtend")
    links <- NucleotideOverlap(
        SyntenyObject = syn_obj,
        GeneCalls = Endosymbionts_GeneCalls,
        Verbose = FALSE
    )
    linked_pairs <- PairSummaries(
        SyntenyLinks = links,
        DBPATH = db_path,
        PIDs = FALSE,
        Verbose = FALSE
    )
    clusters <- DisjointSet(Pairs = linked_pairs, Verbose = TRUE)
    extracted_sets <- ExtractBy(
        x = linked_pairs,
        y = db_path,
        z = clusters[1:10],
        Verbose = TRUE
    )


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
