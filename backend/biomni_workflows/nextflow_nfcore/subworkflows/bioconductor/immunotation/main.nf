#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: immunotation
// MHC (major histocompatibility complex) molecules are cell surface complexes that present antigens to
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/immunotation/inst/doc/immunotation_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("immunotation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IMMUNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-immunotation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-immunotation:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-immunotation:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_immunotation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_immunotation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_immunotation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(immunotation)
    library(jsonlite)

    # --- Reference Data Retrieval [Organism and Chain Lookup] ---
    # Key functions: get_valid_organisms, retrieve_chain_lookup_table
    valid_orgs <- get_valid_organisms()
    human_chains <- retrieve_chain_lookup_table(organism = "human")
    head(human_chains, n = 30)

    # --- Allele Nomenclature and Tool Formatting [MHC Conversion] ---
    # Key functions: get_serotypes, get_mhcpan_input, get_G_group, get_P_group, encode_MAC
    alleles_mhc1 <- c("A*01:01:01", "A*02:01:01", "B*39:01:01")
    alleles_mhc2 <- c("DPA1*01:03:01", "DPB1*14:01:01")
    serotypes_mhc1 <- get_serotypes(alleles_mhc1, mhc_type = "MHC-I")
    mhcpan_mhc2 <- get_mhcpan_input(alleles_mhc2, mhc_class = "MHC-II")
    g_groups <- get_G_group(alleles_mhc2)
    p_groups <- get_P_group(alleles_mhc1)
    mac_encoded <- encode_MAC(alleles_mhc1)

    # --- Frequency Querying [Allele and Haplotype Frequencies] ---
    # Key functions: query_allele_frequencies, build_allele_group, query_haplotype_frequencies
    hla_group <- build_allele_group("A*01:02")
    freq_data <- query_allele_frequencies(
        hla_selection = hla_group,
        hla_sample_size_pattern = "bigger_than",
        hla_sample_size = 200,
        standard = "g"
    )
    haplo_alleles <- c("A*02:01", "B*", "C*")
    haplo_freq <- query_haplotype_frequencies(
        hla_selection = haplo_alleles,
        hla_region = "Europe"
    )

    # --- Population Analysis and Visualization [Demographics and Plotting] ---
    # Key functions: query_population_detail, plot_allele_frequency
    pop_detail <- query_population_detail(1986)
    freq_subset <- query_allele_frequencies(
        hla_selection = "A*02:01",
        hla_sample_size_pattern = "bigger_than",
        hla_sample_size = 10000,
        standard = "g"
    )
    pop_ids <- as.numeric(freq_subset$population_id)
    multi_pop_detail <- query_population_detail(pop_ids)
    plot_allele_frequency(freq_subset)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_immunotation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_immunotation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_immunotation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IMMUNOTATION:", paste0("    immunotation: ", packageVersion("immunotation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_immunotation_results.csv
    touch ${prefix}_immunotation_output.rds
    echo "BIOC_IMMUNOTATION:" > versions.yml
    echo "    immunotation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IMMUNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IMMUNOTATION(ch_input)

    emit:
    results  = BIOC_IMMUNOTATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IMMUNOTATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IMMUNOTATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IMMUNOTATION.out.versions  // channel: path(versions.yml)
}
