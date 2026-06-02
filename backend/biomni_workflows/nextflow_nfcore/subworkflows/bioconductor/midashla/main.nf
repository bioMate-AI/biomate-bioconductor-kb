#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: midasHLA
// MiDAS is a R package for immunogenetics data transformation and statistical analysis. MiDAS accepts 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/midasHLA/inst/doc/MiDAS_tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("midasHLA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIDASHLA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-midashla"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-midashla:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-midashla:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_midashla_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_midashla_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_midashla_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(midasHLA)
    library(jsonlite)

    # --- Phenotype Preparation and Hardy-Weinberg Equilibrium Testing [] ---
    # Key functions: prepareMiDAS, HWETest
    dat_pheno <- read.table(
        file = system.file("extdata", "MiDAS_tut_pheno.txt", package = "midasHLA"),
        header = TRUE
    )
    HLA <- prepareMiDAS(
        hla_calls = dat_HLA,
        colData = dat_pheno,
        experiment = "hla_alleles"
    )
    HLA <- HWETest(
        object = HLA,
        experiment = "hla_alleles",
        HWE_cutoff = 0.05 / 447,
        as.MiDAS = TRUE
    )


    # --- HLA Association Analysis [] ---
    # Key functions: runMiDAS
    HLA_model <- glm(disease ~ term, data = HLA, family = binomial())
    HLA_results <- runMiDAS(
        object = HLA_model,
        experiment = "hla_alleles",
        inheritance_model = "dominant",
        lower_frequency_cutoff = 0.02,
        upper_frequency_cutoff = 0.98,
        correction = "bonferroni",
        exponentiate = TRUE
    )


    # --- Amino Acid Association Mapping [] ---
    # Key functions: prepareMiDAS, runMiDAS, getAllelesForAA
    HLA_AA <- prepareMiDAS(
        hla_calls = dat_HLA,
        colData = dat_pheno,
        experiment = "hla_aa"
    )
    HLA_AA_model <- glm(disease ~ term, data = HLA_AA, family = binomial())
    HLA_AA_results <- runMiDAS(
        HLA_AA_model,
        experiment = "hla_aa",
        inheritance_model = "dominant",
        omnibus_groups_filter = "DQB1_9",
        lower_frequency_cutoff = 0.02,
        upper_frequency_cutoff = 0.98,
        correction = "bonferroni",
        exponentiate = TRUE
    )
    HLA_AA_DQB1_9_alleles <- getAllelesForAA(HLA_AA, "DQB1_9")


    # --- KIR Ligand and Interaction Analysis [] ---
    # Key functions: readKirCalls, getKIRFrequencies, prepareMiDAS, runMiDAS
    dat_KIR <- readKirCalls(
        file = system.file("extdata", "MiDAS_tut_KIR.txt", package = "midasHLA")
    )
    kir_freq <- getKIRFrequencies(dat_KIR)
    HLAKIR <- prepareMiDAS(
        hla_calls = dat_HLA,
        kir_calls = dat_KIR,
        colData = dat_pheno,
        experiment = c("hla_NK_ligands", "kir_genes", "hla_kir_interactions")
    )
    KIR_model <- glm(disease ~ term, data = HLAKIR, family = binomial())
    KIR_results <- runMiDAS(
        KIR_model,
        experiment = "kir_genes",
        lower_frequency_cutoff = 0.02,
        upper_frequency_cutoff = 0.98,
        exponentiate = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_midashla_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_midashla_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_midashla_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIDASHLA:", paste0("    midashla: ", packageVersion("midasHLA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_midashla_results.csv
    touch ${prefix}_midashla_output.rds
    echo "BIOC_MIDASHLA:" > versions.yml
    echo "    midashla: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIDASHLA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIDASHLA(ch_input)

    emit:
    results  = BIOC_MIDASHLA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIDASHLA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIDASHLA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIDASHLA.out.versions  // channel: path(versions.yml)
}
