#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: musicatk
// Mutational signatures are carcinogenic exposures or aberrant cellular processes that can cause alter
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/musicatk/inst/doc/musicatk.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("musicatk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSICATK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-musicatk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-musicatk:2.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-musicatk:2.0.0--r44_0'}"

    input:
    tuple val(meta), path(vcf_object)

    output:
    tuple val(meta), path("${meta.id}_musicatk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_musicatk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_musicatk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(musicatk)
    library(jsonlite)

    # --- Extract Variants [] ---
    # Key functions: extract_variants_from_maf_file, extract_variants_from_vcf_file, files, glob2rx, extract_variants
    # Extract variants from a MAF File
    lusc_maf <- system.file("extdata", "public_TCGA.LUSC.maf", package = "musicatk")
    lusc.variants <- extract_variants_from_maf_file(maf_file = lusc_maf)
    # Extract variants from an individual VCF file
    luad_vcf <- system.file("extdata", "public_LUAD_TCGA-97-7938.vcf",
    # --- Select Genome [] ---
    # Key functions: select_genome
    g <- select_genome("hg38")
    # --- Create Musica [] ---
    # Key functions: create_musica_from_variants
    musica <- create_musica_from_variants(x = variants, genome = g)
    # --- Build Tables [] ---
    # Key functions: build_standard_table
    build_standard_table(musica, g = g, table_name = "SBS96")
    # --- Combine Tables [] ---
    # Key functions: build_standard_table, tables, combine_count_tables
    data(dbs_musica)
    build_standard_table(dbs_musica, g, "SBS96", overwrite = TRUE)
    build_standard_table(dbs_musica, g, "DBS78", overwrite = TRUE)
    # Subset SBS table to DBS samples so they cam be combined
    count_tables <- tables(dbs_musica)
    # --- Create Musica From Counts [] ---
    # Key functions: csv, create_musica_from_counts
    luad_count_table_path <- system.file("extdata", "luad_tcga_count_table.csv",
      package = "musicatk"
    )
    luad_count_table <- as.matrix(read.csv(luad_count_table_path))
    musica_from_counts <- create_musica_from_counts(luad_count_table, "SBS96")
    # --- Discover Sigs [] ---
    # Key functions: discover_signatures
    discover_signatures(
      musica = musica, modality = "SBS96", num_signatures = 3,
      algorithm = "nmf", model_id = "ex_result", nstart = 10
    )
    # --- Result Accessors [] ---
    # Key functions: exposures, signatures
    # Extract the exposure matrix
    expos <- exposures(musica, "result", "SBS96", "ex_result")
    expos[1:3, 1:3]
    # Extract the signature matrix
    sigs <- signatures(musica, "result", "SBS96", "ex_result")
    # --- Compare K Vals [] ---
    # Key functions: compare_k_vals
    k_comparison <- compare_k_vals(musica, "SBS96",
      reps = 5, min_k = 2, max_k = 4,
      algorithm = "nmf"
    )
    # --- Plot Sigs [] ---
    # Key functions: plot_signatures
    plot_signatures(musica, model_id = "ex_result", modality = "SBS96")
    # --- Name Sigs [] ---
    # Key functions: name_signatures, plot_signatures
    name_signatures(musica, "ex_result", c("Smoking", "APOBEC", "UV"))
    plot_signatures(musica, model_id = "ex_result", modality = "SBS96")
    # --- Exposures Raw [] ---
    # Key functions: plot_exposures
    plot_exposures(musica, "ex_result", plot_type = "bar")
    # --- Exposures Prop [] ---
    # Key functions: plot_exposures
    plot_exposures(musica, "ex_result", plot_type = "bar", proportional = TRUE)
    # --- Sample Counts [] ---
    # Key functions: sample_names, plot_sample_counts
    samples <- sample_names(musica)
    plot_sample_counts(musica, sample_names = samples[c(3, 4, 5)],
                       modality = "SBS96")
    # --- Compare Cosmic [] ---
    # Key functions: compare_cosmic_v2
    compare_cosmic_v2(musica, "ex_result", threshold = 0.75)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_musicatk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_musicatk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_musicatk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUSICATK:", paste0("    musicatk: ", packageVersion("musicatk"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_musicatk_results.csv
    touch ${prefix}_musicatk_output.rds
    echo "BIOC_MUSICATK:" > versions.yml
    echo "    musicatk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUSICATK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(vcf_object) ]

    main:
    BIOC_MUSICATK(ch_input)

    emit:
    results  = BIOC_MUSICATK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUSICATK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUSICATK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUSICATK.out.versions  // channel: path(versions.yml)
}
