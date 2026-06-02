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
    library(MSA2dist)
    library(DNAString)
    library(DNAStringSet)
    library(jsonlite)

    # --- Sequence Conversion and Translation [Sequence Processing] ---
    # Key functions: dnabin2dnastring, cds2aa, aastring2aln, aln2aastring
    # Convert DNA bin to DNA string set and translate to amino acids
    dna_seqs <- ape::woodmouse |> dnabin2dnastring()
    aa_seqs <- dna_seqs |> cds2aa(shorten = TRUE)
    # Convert AA string set to alignment format
    aa_aln <- aa_seqs |> aastring2aln()
    # Convert back to AA string set
    aa_seqs_restored <- aa_aln |> aln2aastring()

    # --- Amino Acid Distance Calculation [Distance Estimation] ---
    # Key functions: cds2aa, aastring2dist, granthamMatrix
    # Translate HIV CDS sequences to amino acids
    hiv_aa <- msa2dist::hiv |> cds2aa()
    # Calculate pairwise AA distances using Grantham's matrix
    aa_dist_grantham <- hiv_aa |> aastring2dist(score = granthamMatrix())
    # Extract distance matrix and sites used
    dist_matrix <- aa_dist_grantham$distSTRING
    sites_used <- aa_dist_grantham$sitesUsed
    # Calculate pairwise AA distances using custom AAMatrix
    aa_dist_custom <- hiv_aa |> aastring2dist(score = msa2dist::AAMatrix)

    # --- DNA Distance Calculation [Distance Estimation] ---
    # Key functions: dnastring2dist
    # Calculate pairwise DNA distances using K80 model
    dna_dist_k80 <- msa2dist::hiv |> dnastring2dist(model = "K80")
    # Calculate pairwise DNA distances using IUPAC model with multi-threading
    dna_dist_iupac <- msa2dist::hiv |>
        dnastring2dist(model = "IUPAC", threads = 2)
    # Extract distance matrices
    k80_matrix <- dna_dist_k80$distSTRING
    iupac_matrix <- dna_dist_iupac$distSTRING

    # --- Codon-based Ka/Ks Calculation [Evolutionary Analysis] ---
    # Key functions: dnastring2kaks, indices2kaks
    # Calculate Ka/Ks using the MYN model
    kaks_myn <- msa2dist::hiv |> dnastring2kaks(model = "MYN")
    # Calculate Ka/Ks using the YN model with multi-threading
    kaks_yn <- msa2dist::hiv |> dnastring2kaks(model = "YN", threads = 2)
    # Calculate Ka/Ks for specific pairwise indices
    pair_indices <- list(c(2, 3), c(5, 7, 9))
    kaks_indices <- msa2dist::hiv |>
        indices2kaks(pair_indices, model = "MYN")


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
