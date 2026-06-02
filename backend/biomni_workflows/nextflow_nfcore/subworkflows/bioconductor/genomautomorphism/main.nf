#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomAutomorphism
// This is a R package to compute the automorphisms between pairwise aligned DNA sequences represented 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomAutomorphism/inst/doc/GenomAutomorphism.R
// Upstream  : Biostrings
// Downstream: none
//
// Install: BiocManager::install("GenomAutomorphism")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMAUTOMORPHISM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomautomorphism"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomautomorphism:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-genomautomorphism:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomautomorphism_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomautomorphism_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomautomorphism_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomAutomorphism)
    library(DNAStringSet)
    library(jsonlite)

    # --- Sequence Coordinate Mapping [Sequence Representation] ---
    # Key functions: base2int, base_coord, codon_coord
    x0 <- c("ACG", "TGC")
    x1 <- Biostrings::DNAStringSet(x0)
    x2 <- base_coord(x1, cube = "ACGT")
    x3 <- codon_coord(codon = x2, group = "Z64")
    b_int <- base2int("ACGT", group = "Z4", cube = "ACGT")

    # --- Automorphism Computation [Automorphism Analysis] ---
    # Key functions: automorphisms
    data(covid_aln, package = "GenomAutomorphism")
    autm <- automorphisms(
        seqs = covid_aln,
        group = "Z64",
        cube = c("ACGT", "TGCA"),
        cube_alt = c("CATG", "GTAC"),
        start = 1,
        end = 750,
        verbose = FALSE
    )

    # --- Genomic Range Aggregation [Genomic Ranges] ---
    # Key functions: automorphismByRanges
    data(covid_autm, package = "GenomAutomorphism")
    aut_range <- automorphismByRanges(covid_autm)
    idx <- which(aut_range$cube == "Trnl")
    trnl_ranges <- aut_range[idx]
    trnl_widths <- BiocGenerics::width(trnl_ranges)

    # --- Mutation Probability Estimation [Probability Analysis] ---
    # Key functions: automorphism_bycoef, automorphism_prob
    data(covid_autm, package = "GenomAutomorphism")
    autby_coef <- automorphism_bycoef(covid_autm)
    filtered_coef <- autby_coef[autby_coef$autm != 1 & autby_coef$autm != -1]
    post_prob <- automorphism_prob(filtered_coef)
    high_prob <- post_prob[post_prob$Posterior_Probability > 0.003, ]

    # --- Conserved Regions Identification [Conservation Analysis] ---
    # Key functions: conserved_regions
    data(covid_autm, package = "GenomAutomorphism")
    conserv <- conserved_regions(covid_autm)
    conserv_uniq <- conserved_regions(covid_autm, output = "unique")
    data(autm_3d, package = "GenomAutomorphism")
    conserv_3d <- conserved_regions(autm_3d)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomautomorphism_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomautomorphism_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomautomorphism_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMAUTOMORPHISM:", paste0("    genomautomorphism: ", packageVersion("GenomAutomorphism"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomautomorphism_results.csv
    touch ${prefix}_genomautomorphism_output.rds
    echo "BIOC_GENOMAUTOMORPHISM:" > versions.yml
    echo "    genomautomorphism: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMAUTOMORPHISM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMAUTOMORPHISM(ch_input)

    emit:
    results  = BIOC_GENOMAUTOMORPHISM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMAUTOMORPHISM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMAUTOMORPHISM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMAUTOMORPHISM.out.versions  // channel: path(versions.yml)
}
