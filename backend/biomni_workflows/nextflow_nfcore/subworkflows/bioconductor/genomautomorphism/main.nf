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
    library(DNAStringSet)
    library(jsonlite)

    # --- base2int [] ---
    # Key functions: base2int
    base2int("ACGT", group = "Z4", cube = "ACGT")
    # --- codon_coord [] ---
    # Key functions: codon_coord
    codons <- codon_coord(
    # --- D N A String Set [] ---
    # Key functions: DNAStringSet
    x0 <- c("ACG", "TGC")
    x1 <- DNAStringSet(x0)
    # --- base_coord [] ---
    # Key functions: base_coord
    x2 <- base_coord(x1, cube = "ACGT")
    x2. <- base_coord(x1, cube = "TGCA")
    # --- codon_coord [] ---
    # Key functions: codon_coord
    x3 <- codon_coord(codon = x2, group = "Z64")
    x3. <- codon_coord(codon = x2., group = "Z64")
    # --- automorphisms [] ---
    # Key functions: automorphisms
    autm <- automorphisms(
    cube = c("ACGT", "TGCA"),
    cube_alt = c("CATG", "GTAC"),
    # --- automorphism By Ranges [] ---
    # Key functions: automorphismByRanges
    aut_range <- automorphismByRanges(autm)
    # --- aut 1 [] ---
    # Key functions: automorphisms
    covid_autm <- automorphisms(
    cube = c("ACGT", "TGCA"),
    cube_alt = c("CATG", "GTAC"),
    # --- range 2 [] ---
    # Key functions: automorphismByRanges
    aut_range <- automorphismByRanges(covid_autm)
    # --- width [] ---
    # Key functions: width
    data.frame(aut_range[idx])
    width(aut_range[ idx ])
    # --- automorphism_bycoef [] ---
    # Key functions: automorphism_bycoef
    autby_coef <- automorphism_bycoef(covid_autm)
    # --- barplot 2 [] ---
    # Key functions: automorphism_prob
    post_prob <- automorphism_prob(autby_coef)
    names(counts) <- post_prob$Codon
    par(family = "serif", cex.axis = 2, font = 2, las = 1,
    # --- conserved regions [] ---
    # Key functions: conserved_regions
    conserv <- conserved_regions(covid_autm)
    # --- conserved_regions [] ---
    # Key functions: conserved_regions
    conserv_unique <- conserved_regions(covid_autm, output = "unique")
    # --- aut 2 [] ---
    # Key functions: automorphisms
    autm_z125 <- automorphisms(
    cube = c("ACGT", "TGCA"),
    cube_alt = c("CATG", "GTAC"),

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
