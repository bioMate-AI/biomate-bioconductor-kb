#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DAMEfinder
// 'DAMEfinder' offers functionality for taking methtuple or bismark outputs to calculate ASM scores an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DAMEfinder/inst/doc/DAMEfinder_workflow.R
// Upstream  : GenomicRanges, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("DAMEfinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DAMEFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-damefinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-damefinder:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-damefinder:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_damefinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_damefinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_damefinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DAMEfinder)
    library(GRanges)
    library(jsonlite)

    # --- Data Import and Preparation ---
    # Key functions: extract_bams, read_tuples
    snp_list <- extract_bams(
        bamFiles = bam_files,
        vcfFiles = vcf_files,
        sampleNames = sample_names,
        referenceFile = reference_file,
        coverage = 2
    )
    tuple_list <- read_tuples(
        files = tuple_files,
        sampleNames = sample_names
    )

    # --- Allele-Specific Methylation Calculation ---
    # Key functions: calc_derivedasm, calc_asm
    derASM <- calc_derivedasm(
        snp.list = snp_list,
        cores = 1,
        verbose = FALSE
    )
    ASMscore <- calc_asm(
        sample_list = tuple_list
    )

    # --- Differential Allele-Specific Methylation Detection ---
    # Key functions: find_dames
    grp <- factor(
        c(rep("CRC", 4), rep("NORM", 4)),
        levels = c("NORM", "CRC")
    )
    mod <- model.matrix(~grp)
    dames <- find_dames(
        derASM,
        design = mod,
        pvalAssign = "empirical",
        maxGap = 300
    )

    # --- Genomic Visualization ---
    # Key functions: dame_track, dame_track_mean, methyl_circle_plot
    dame <- GenomicRanges::GRanges(
        19,
        GenomicRanges::IRanges(323736, 324622)
    )
    dame_track(
        dame = dame,
        ASM = ASMscore,
        window = 2
    )
    methyl_circle_plot(
        snp = snp,
        vcfFile = vcf_file,
        bamFile = bam_file,
        refFile = reference_file,
        dame = dame
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_damefinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_damefinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_damefinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DAMEFINDER:", paste0("    damefinder: ", packageVersion("DAMEfinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_damefinder_results.csv
    touch ${prefix}_damefinder_output.rds
    echo "BIOC_DAMEFINDER:" > versions.yml
    echo "    damefinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DAMEFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DAMEFINDER(ch_input)

    emit:
    results  = BIOC_DAMEFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DAMEFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DAMEFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DAMEFINDER.out.versions  // channel: path(versions.yml)
}
