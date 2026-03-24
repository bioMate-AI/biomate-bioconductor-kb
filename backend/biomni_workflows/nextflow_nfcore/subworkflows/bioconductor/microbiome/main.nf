#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: microbiome
// Utilities for microbiome analysis.
//
// Source : https://microbiome.github.io/tutorials/Preprocessing.html
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("microbiome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICROBIOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-microbiome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-microbiome:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-microbiome:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_microbiome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_microbiome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_microbiome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(microbiome)
    library(jsonlite)

    # --- Summarizing the contents of a phyloseq object [] ---
    # Key functions: summarize_phyloseq
    summarize_phyloseq(pseq)
    # --- Retrieving data elements from phyloseq object [] ---
    # Key functions: meta, tax_table, abundances, readcount, sample_data, psmelt, kable
    meta <- meta(pseq)
    
    taxonomy <- tax_table(pseq)
    
    # Absolute abundances
    otu.absolute <- abundances(pseq)
    
    # Relative abundances
    otu.relative <- abundances(pseq, "compositional")
    
    reads_sample <- readcount(pseq)
    # check for first 5 samples
    # --- Sample operations [] ---
    # Key functions: sample_names, sample_sums, abundances, subset_samples, subset, meta, prune_samples, baseline
    head(sample_names(pseq))
    
    s <- sample_sums(pseq)
    
    head(abundances(pseq)["Akkermansia",])
    
    pseq.subset <- subset_samples(pseq, nationality == "AFR")
    
    # Check sample names for African Females in this phyloseq object
    s <- rownames(subset(meta(pseq), nationality == "AFR" & sex == "Female"))
    
    # Pick the phyloseq subset with these sample names
    # --- Data transformations [] ---
    # Key functions: transform, data
    pseq.compositional <- microbiome::transform(pseq, "compositional")
    
    data(dietswap)
    x <- dietswap
    # Compositional data
    x2 <- microbiome::transform(x, "compositional")
    # --- Variable operations [] ---
    # Key functions: sample_variables, get_variable, alpha, sample_data
    sample_variables(pseq)
    
    head(get_variable(pseq, sample_variables(pseq)[1]))
    
    # Calculate diversity for samples
    div <- microbiome::alpha(pseq, index = "shannon")
    
    # Assign the estimated diversity to sample metadata
    sample_data(pseq)$diversity <- div
    # --- Taxa operations [] ---
    # Key functions: ntaxa, top_taxa, rank_names, taxa, subset_taxa, map_levels, prune_taxa, taxa_sums
    n <- ntaxa(pseq)
    
    topx <- top_taxa(pseq, n = 10)
    
    ranks <- rank_names(pseq)  # Taxonomic levels
    taxa  <- taxa(pseq)        # Taxa names at the analysed level
    
    pseq.bac <- subset_taxa(pseq, Phylum == "Bacteroidetes")
    
    # List of Genera in the Bacteroideted Phylum
    taxa <- map_levels(NULL, "Phylum", "Genus", pseq)$Bacteroidetes
    
    # --- Labelling ASVs with best taxonomy [] ---
    # Key functions: add_besthit, taxa_names
    ps <- add_besthit(ps)
    taxa_names(ps)[1:2]
    
    taxa_names(ps) <- gsub("[a-x]__", "",taxa_names(ps))
    taxa_names(ps)[1:2]
    # --- Merging operations [] ---
    # Key functions: aggregate_taxa, merge_taxa2, merge_phyloseq, data, combine_otu_tax
    pseq2 <- aggregate_taxa(pseq, "Phylum")
    
    pseq2 <- merge_taxa2(pseq, pattern = "^Bacteroides", name = "Bacteroides")
    
    merge_phyloseq(pseqA, pseqB)
    
    library(dplyr)
    library(microbiome)
    data("atlas1006") # example data from microbiome pkg
    otu.tax.tibble <- combine_otu_tax(atlas1006, column.id = "ASVID")
    # view first fist rows and columns
    otu.tax.tibble[1:5,1:5]
    # --- Get tibbles [] ---
    # Key functions: otu_tibble, tax_tibble, sample_tibble
    otu.tib <- otu_tibble(atlas1006, column.id = "FeatureID")
    
    tax.tib <- tax_tibble(atlas1006, column.id = "FeatureID")
    
    sample.tib <- sample_tibble(atlas1006, column.id = "SampleID")
    # --- Convert to tidy long format [] ---
    # Key functions: psmelt2
    ps.long.tib <- psmelt2(pseq)
    head(ps.long.tib)
    # --- Rarefaction [] ---
    # Key functions: rarefy_even_depth
    pseq.rarified <- rarefy_even_depth(pseq)
    # --- Taxonomy [] ---
    # Key functions: map_levels, tax_table
    m <- map_levels("Akkermansia", "Genus", "Phylum", tax_table(pseq))
    print(m)
    # --- Metadata [] ---
    # Key functions: plot_frequencies, sample_data, kable, group_bmi, group_age, data, meta
    p <- plot_frequencies(sample_data(pseq), "bmi_group", "sex")
    print(p)
    
    # Retrieving the actual data values:
    # kable(head(p@data), digits = 2)
    
    group_bmi(c(22, 28, 31), "standard")
    
    group_age(c(17, 41, 102), "decades")
    
    # Example data
    data(dietswap)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_microbiome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_microbiome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_microbiome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MICROBIOME:", paste0("    microbiome: ", packageVersion("microbiome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_results.csv
    touch ${prefix}_microbiome_output.rds
    echo "BIOC_MICROBIOME:" > versions.yml
    echo "    microbiome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MICROBIOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MICROBIOME(ch_input)

    emit:
    results  = BIOC_MICROBIOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MICROBIOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MICROBIOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MICROBIOME.out.versions  // channel: path(versions.yml)
}
