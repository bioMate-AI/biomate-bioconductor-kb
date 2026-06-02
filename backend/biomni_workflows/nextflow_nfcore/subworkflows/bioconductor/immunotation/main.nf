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

    # --- Get Valid Organisms [] ---
    # Key functions: get_valid_organisms
    ---------------------------------------------------------------------
    get_valid_organisms()
    # --- Retrieve Chain Lookup Table [] ---
    # Key functions: retrieve_chain_lookup_table, datatable
    ---------------------------------------------------------------------
    df <- retrieve_chain_lookup_table(organism = "human")
    DT::datatable(head(df, n=30))
    # --- Datatable [] ---
    # Key functions: datatable
    ---------------------------------------------------------------------
    DT::datatable(head(human_protein_complex_table, n=30))
    # --- Map Serotypes [] ---
    # Key functions: get_serotypes
    ---------------------------------------------------------------------
    get_serotypes(allele_list1, mhc_type = "MHC-I")
    # --- Format NetMHCpan Input [] ---
    # Key functions: get_mhcpan_input
    ---------------------------------------------------------------------
    get_mhcpan_input(allele_list1, mhc_class = "MHC-I")
    # --- Retrieve G Groups [] ---
    # Key functions: get_G_group
    ---------------------------------------------------------------------
    get_G_group(allele_list2)
    # --- Retrieve P Groups [] ---
    # Key functions: get_P_group
    ---------------------------------------------------------------------
    get_P_group(allele_list1)
    # --- Decode Multiple Allele Codes [] ---
    # Key functions: decode_MAC
    ---------------------------------------------------------------------
    MAC1 <- "A*01:AYMG"
    decode_MAC(MAC1)
    # --- Query Allele Frequencies [] ---
    # Key functions: query_allele_frequencies, datatable
    ---------------------------------------------------------------------
    sel1 <- query_allele_frequencies(hla_selection = "A*02:01",
                                    hla_sample_size_pattern = "bigger_than",
                                    hla_sample_size = 10000,
                                    standard="g")
    # --- Build Allele Group [] ---
    # Key functions: build_allele_group, query_allele_frequencies
    ---------------------------------------------------------------------
    hla_selection <- build_allele_group("A*01:02")
    # --- Query Allele Frequencies [] ---
    # Key functions: query_allele_frequencies, datatable
    ---------------------------------------------------------------------
    sel2 <- query_allele_frequencies(hla_locus = "B", hla_population = 1986)
    DT::datatable(sel2)
    # --- Plot Allele Frequencies [] ---
    # Key functions: plot_allele_frequency
    ---------------------------------------------------------------------
    plot_allele_frequency(sel1)
    # --- Query Population Metainformation [] ---
    # Key functions: query_population_detail, datatable
    ---------------------------------------------------------------------
    sel3 <- query_population_detail(1986)
    DT::datatable(sel3, options = list(scrollX = TRUE))

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
