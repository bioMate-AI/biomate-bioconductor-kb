#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSA2dist
// MSA2dist calculates pairwise distances between all sequences of a DNAStringSet or a AAStringSet usin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSA2dist/inst/doc/MSA2dist.R
// Upstream  : Biostrings, ape, dplyr, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("MSA2dist")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSA2DIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msa2dist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msa2dist:1.10.1--r44_0' :
        'quay.io/biocontainers/bioconductor-msa2dist:1.10.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msa2dist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msa2dist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msa2dist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAString)
    library(DNAStringSet)
    library(jsonlite)

    # --- Compute distance matrix [] ---
    # Key functions: bionj, dist
    ---------------------------------------------------------------------
    ## create and plot bionj tree
    aa.dist.bionj <- ape::bionj(as.dist(aa.dist$distSTRING))
    plot(aa.dist.bionj)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: select, gather, ggplot, aes, geom_line, factor, geom_point
    ---------------------------------------------------------------------
    print(hiv.xy |> dplyr::select(Codon,SynMean,NonSynMean,IndelMean) |>
        tidyr::gather(variable, values, -Codon) |>
        ggplot2::ggplot(aes(x=Codon, y=values)) +
        ggplot2::geom_line(aes(colour=factor(variable))) +
    # --- DNAString analysis [] ---
    # Key functions: data, DNAString, DNAStringSet, dnastring2aln, aln2dnastring, dnastring2dnabin, dnabin2dnastring, cds2aa
    ---------------------------------------------------------------------
    ## use frame 2 and shorten to circumvent multiple of three error
    cds1 <- Biostrings::DNAString("-ATGCAACATTGC-")
    cds2 <- Biostrings::DNAString("-ATG---CATTGC-")
    cds1.cds2.aln <- c(Biostrings::DNAStringSet(cds1),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msa2dist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msa2dist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msa2dist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSA2DIST:", paste0("    msa2dist: ", packageVersion("MSA2dist"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msa2dist_results.csv
    touch ${prefix}_msa2dist_output.rds
    echo "BIOC_MSA2DIST:" > versions.yml
    echo "    msa2dist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSA2DIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSA2DIST(ch_input)

    emit:
    results  = BIOC_MSA2DIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSA2DIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSA2DIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSA2DIST.out.versions  // channel: path(versions.yml)
}
