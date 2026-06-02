#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: altcdfenvs
// Convenience data structures and functions to handle cdfenvs
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/altcdfenvs/inst/doc/altcdfenvs.R
// Upstream  : RColorBrewer, Rgraphviz, hgu133acdf
// Downstream: none
//
// Install: BiocManager::install("altcdfenvs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALTCDFENVS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-altcdfenvs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-altcdfenvs:2.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-altcdfenvs:2.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_altcdfenvs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_altcdfenvs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_altcdfenvs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(altcdfenvs)
    library(jsonlite)

    # --- Entry [] ---
    # Key functions: entry, null, close
    fasta.seq <- read.FASTA.entry(con)
    while(! is.null(fasta.seq$header)) {
      print(fasta.seq)
      fasta.seq <- read.FASTA.entry(con)
    }
    # --- Tohypergraph [] ---
    # Key functions: toHypergraph
    hg <- toHypergraph(m)
    # --- Tographnel [] ---
    # Key functions: toGraphNEL
    gn <- toGraphNEL(hg)
    # --- Env [] ---
    # Key functions: env, emptyenv
    targetNodes <- new.env(hash=TRUE, parent=emptyenv())
    for (i in seq(along=targets)) {
      targetNodes[[names(targets)[i]]] <- i
    }
    # --- Buildcdfenv [] ---
    # Key functions: biostrings
    alt.cdf <-
      buildCdfEnv.biostrings(m, nrow.chip = 712, ncol.chip = 712)
    # --- Getseq [] ---
    # Key functions: getSequence, null
    getSeq <- function(name) {
      seq <- getSequence(id=name, type="hgnc_symbol",
                         seqType="cdna", mart = mart)
      targets <- seq$cdna
      if (is.null(targets))
    # --- Matchaffyprobes [] ---
    # Key functions: matchAffyProbes
    m <- matchAffyProbes(hgu133aprobe, targets, "HG-U133A")
    # --- Slamf [] ---
    # Key functions: toHypergraph, toGraphNEL, pal, numNodes
    hg <- toHypergraph(m)
    gn <- toGraphNEL(hg)
    library(RColorBrewer)
    col <- brewer.pal(length(geneSymbols)+1, "Set1")
    tColors <- rep(col[length(col)], length=numNodes(gn))
    # --- Totable [] ---
    # Key functions: toTable
    library("hgu133a.db")
    affyTab <- toTable(hgu133aSYMBOL)
    slamf_i <- grep("^SLAMF", affyTab$symbol)
    pset_id <- affyTab$probe_id[slamf_i]
    library("hgu133acdf")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_altcdfenvs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_altcdfenvs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_altcdfenvs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALTCDFENVS:", paste0("    altcdfenvs: ", packageVersion("altcdfenvs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_altcdfenvs_results.csv
    touch ${prefix}_altcdfenvs_output.rds
    echo "BIOC_ALTCDFENVS:" > versions.yml
    echo "    altcdfenvs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALTCDFENVS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALTCDFENVS(ch_input)

    emit:
    results  = BIOC_ALTCDFENVS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALTCDFENVS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALTCDFENVS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALTCDFENVS.out.versions  // channel: path(versions.yml)
}
