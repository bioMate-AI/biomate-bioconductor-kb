#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqCAT
// The seqCAT package uses variant calling data (in the form of VCF files) from high throughput sequenc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqCAT/inst/doc/seqCAT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqCAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQCAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqcat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqcat:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqcat:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqcat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqcat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqcat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seqCAT)
    library(jsonlite)

    # --- Profile Creation [SNV Profile Generation] ---
    # Key functions: create_profile, create_profiles, write_profile
    vcf <- system.file("extdata", "example.vcf.gz", package = "seqCAT")
    hct116 <- create_profile(vcf, "HCT116")
    rko <- create_profile(vcf, "RKO", min_depth = 15, filter_gd = FALSE)
    vcf_dir <- system.file("extdata", package = "seqCAT")
    profiles <- create_profiles(vcf_dir, pattern = "example")
    write_profile(hct116, "hct116.profile.txt")

    # --- Profile Filtering [Variant and Duplicate Filtering] ---
    # Key functions: create_profile, filter_variants, filter_duplicates
    vcf <- system.file("extdata", "example.vcf.gz", package = "seqCAT")
    rko <- create_profile(vcf, "RKO", min_depth = 15, filter_gd = FALSE)
    rko_filtered <- filter_variants(rko, min_depth = 20)
    rko_deduplicated <- filter_duplicates(rko, filter_pd = TRUE)

    # --- Profile Comparison [Pairwise and Database Comparisons] ---
    # Key functions: create_profile, read_cosmic, compare_profiles, compare_many
    vcf <- system.file("extdata", "example.vcf.gz", package = "seqCAT")
    hct116 <- create_profile(vcf, "HCT116")
    rko <- create_profile(vcf, "RKO")
    hct116_rko <- compare_profiles(hct116, rko)
    cosmic_file <- system.file(
        "extdata", "subset_CosmicCLP_MutantExport.tsv.gz", package = "seqCAT"
    )
    cosmic <- read_cosmic(cosmic_file, "HCT116")
    hct116_cosmic <- compare_profiles(hct116, cosmic)
    many_comparisons <- compare_many(list(hct116, rko))

    # --- Similarity Analysis [Statistical Similarity Calculation] ---
    # Key functions: create_profile, compare_profiles, calculate_similarity
    vcf <- system.file("extdata", "example.vcf.gz", package = "seqCAT")
    hct116 <- create_profile(vcf, "HCT116")
    rko <- create_profile(vcf, "RKO")
    hke3 <- create_profile(vcf, "HKE3")
    hct116_rko <- compare_profiles(hct116, rko)
    hct116_hke3 <- compare_profiles(hct116, hke3)
    similarity <- calculate_similarity(hct116_rko)
    similarities <- calculate_similarity(hct116_hke3, similarity, b = 10)

    # --- Visualization [Impact and Heatmap Plotting] ---
    # Key functions: create_profile, compare_profiles, compare_many, plot_impacts, plot_heatmap
    vcf <- system.file("extdata", "example.vcf.gz", package = "seqCAT")
    hct116 <- create_profile(vcf, "HCT116")
    rko <- create_profile(vcf, "RKO")
    hct116_rko <- compare_profiles(hct116, rko)
    impacts <- plot_impacts(hct116_rko)
    many <- compare_many(list(hct116, rko))
    heatmap <- plot_heatmap(many[[1]])


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqcat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqcat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqcat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQCAT:", paste0("    seqcat: ", packageVersion("seqCAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqcat_results.csv
    touch ${prefix}_seqcat_output.rds
    echo "BIOC_SEQCAT:" > versions.yml
    echo "    seqcat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQCAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQCAT(ch_input)

    emit:
    results  = BIOC_SEQCAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQCAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQCAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQCAT.out.versions  // channel: path(versions.yml)
}
