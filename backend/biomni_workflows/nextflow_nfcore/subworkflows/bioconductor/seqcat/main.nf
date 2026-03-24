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

    # --- Create an SNV profile [] ---
    # Key functions: create_profile
    library("seqCAT")
    vcf <- system.file("extdata", "example.vcf.gz", package = "seqCAT")
    hct116 <- create_profile(vcf, "HCT116")
    # --- Create a filtered SNV profile [] ---
    # Key functions: create_profile
    rko <- create_profile(vcf, "RKO", min_depth = 15, filter_gd = FALSE)
    # --- Filter an SNV profile [] ---
    # Key functions: filter_variants, filter_duplicates
    rko_filtered <- filter_variants(rko, min_depth = 20)
    rko_deduplicated <- filter_duplicates(rko, filter_pd = TRUE)
    # --- Create multiple profiles [] ---
    # Key functions: create_profiles
    vcf_dir <- system.file("extdata", package = "seqCAT")
    profiles <- create_profiles(vcf_dir, pattern = "sample1")
    # --- List COSMIC [] ---
    # Key functions: list_cosmic
    file <- system.file("extdata", "subset_CosmicCLP_MutantExport.tsv.gz",
    cell_lines <- list_cosmic(file)
    head(cell_lines)
    # --- Read COSMIC [] ---
    # Key functions: read_cosmic
    cosmic <- read_cosmic(file, "HCT116")
    head(cosmic)
    # --- Write profile to disk [] ---
    # Key functions: write_profile
    write_profile(hct116, "hct116.profile.txt")
    # --- Write profile to disk (BED) [] ---
    # Key functions: write_profile
    write_profile(hct116, "hct116.profile.bed")
    # --- Write multiple profiles to disk (GTF) [] ---
    # Key functions: write_profiles
    write_profiles(profiles, format = "GTF", directory = "./")
    # --- Read profile from disk [] ---
    # Key functions: read_profile
    hct116 <- read_profile("hct116.profile.txt")
    # --- Read multiple profiles (GTF) [] ---
    # Key functions: read_profiles
    profile_list <- read_profiles(profile_dir = "./", pattern = ".gtf")
    head(profile_list[[1]])
    # --- Compare profiles [] ---
    # Key functions: compare_profiles
    hct116_rko <- compare_profiles(hct116, rko)
    head(hct116_rko)
    # --- Compare profiles (union) [] ---
    # Key functions: compare_profiles
    hct116_rko_union <- compare_profiles(hct116, rko, mode = "union")
    head(hct116_rko_union)
    # --- Compare with COSMIC [] ---
    # Key functions: compare_profiles
    hct116_cosmic <- compare_profiles(hct116, cosmic)
    head(hct116_cosmic)
    # --- Calculate similarities [] ---
    # Key functions: calculate_similarity
    similarity <- calculate_similarity(hct116_rko)

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
