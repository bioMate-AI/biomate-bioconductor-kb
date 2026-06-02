#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regutools
// RegulonDB has collected, harmonized and centralized data from hundreds of experiments for nearly two
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regutools/inst/doc/regutools.R
// Upstream  : BiocStyle, Biostrings, RefManageR, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("regutools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGUTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regutools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regutools:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regutools:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regutools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regutools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regutools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(regutools)
    library(GRanges)
    library(IRanges)
    library(PrintBibliography)
    library(jsonlite)

    # --- Gene and Dataset Querying [] ---
    # Key functions: list_datasets, list_attributes, get_dataset
    datasets <- list_datasets(e_coli_regulondb)
    gene_attrs <- list_attributes(e_coli_regulondb, "GENE")
    gene_data <- get_dataset(
        regulondb = e_coli_regulondb,
        dataset = "GENE",
        attributes = c("posleft", "posright", "strand", "name"),
        filters = list("name" = c("araC", "crp", "lacI"))
    )


    # --- Genomic Range and Sequence Conversion [] ---
    # Key functions: convert_to_granges, convert_to_biostrings, get_dataset
    gene_granges <- convert_to_granges(gene_data)
    seq_data <- get_dataset(
        regulondb = e_coli_regulondb,
        dataset = "GENE",
        attributes = c("posleft", "posright", "strand", "name", "dna_sequence"),
        filters = list("name" = c("araC", "crp", "lacI"))
    )
    dna_strings <- convert_to_biostrings(seq_data, seq_type = "DNA")


    # --- Regulatory Network Analysis [] ---
    # Key functions: get_gene_regulators, get_regulatory_network, get_regulatory_summary
    regulators <- get_gene_regulators(
        e_coli_regulondb, 
        genes = c("araC", "fis", "crp")
    )
    reg_network <- get_regulatory_network(e_coli_regulondb)
    reg_summary <- get_regulatory_summary(
        e_coli_regulondb,
        gene_regulators = c("araC", "modB")
    )


    # --- Transcription Factor Binding Sites and Visualization [] ---
    # Key functions: get_binding_sites, get_dna_objects, plot_dna_objects
    tf_binding <- get_binding_sites(
        e_coli_regulondb,
        transcription_factor = "AraC",
        output_format = "Biostrings"
    )
    grange_region <- GenomicRanges::GRanges(
        "chr",
        IRanges::IRanges(5000, 10000)
    )
    dna_objects <- get_dna_objects(e_coli_regulondb, grange_region)
    plot_dna_objects(
        e_coli_regulondb,
        grange_region,
        elements = c("gene", "promoter")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regutools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regutools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regutools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGUTOOLS:", paste0("    regutools: ", packageVersion("regutools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regutools_results.csv
    touch ${prefix}_regutools_output.rds
    echo "BIOC_REGUTOOLS:" > versions.yml
    echo "    regutools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGUTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGUTOOLS(ch_input)

    emit:
    results  = BIOC_REGUTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGUTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGUTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGUTOOLS.out.versions  // channel: path(versions.yml)
}
