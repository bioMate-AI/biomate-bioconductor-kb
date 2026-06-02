#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BBCAnalyzer
// BBCAnalyzer is a package for visualizing the relative or absolute number of bases, deletions and ins
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BBCAnalyzer/inst/doc/BBCAnalyzer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BBCAnalyzer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BBCANALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bbcanalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bbcanalyzer:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bbcanalyzer:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bbcanalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bbcanalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bbcanalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BBCAnalyzer)
    library(jsonlite)

    # --- Base Analysis [analyzeBases] ---
    # Key functions: analyzeBases
    ref_genome <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    output1 <- analyzeBases(
        sample_names = system.file("extdata", "SampleNames.txt",
            package = "BBCAnalyzer"),
        bam_input = system.file("extdata", package = "BBCAnalyzer"),
        target_regions = system.file("extdata", "targetRegions.txt",
            package = "BBCAnalyzer"),
        vcf_input = "",
        output = tempdir(),
        output_pictures = "",
        known_file = system.file("extdata", "dbsnp_138.part.vcf.gz",
            package = "BBCAnalyzer"),
        genome = ref_genome,
        MQ_threshold = 60,
        BQ_threshold = 50,
        frequency_threshold = 0.01,
        qual_lower_bound = 58,
        qual_upper_bound = 63,
        marks = c(0.01),
        relative = TRUE,
        per_sample = TRUE
    )

    # --- Visualise Base Analysis [analyzeBasesPlot] ---
    # Key functions: analyzeBasesPlot
    analyzeBasesPlot(
        output = output1,
        output_pictures = tempdir(),
        vcf_input = system.file("extdata", "Example_IonTorrent.vcf",
            package = "BBCAnalyzer"),
        vcf_names = "IonTorrent",
        target_regions = system.file("extdata", "targetRegions.txt",
            package = "BBCAnalyzer"),
        colors = c("blue", "green", "red", "yellow", "purple", "orange"),
        height = 10,
        width = 10,
        per_sample = TRUE,
        relative = TRUE,
        plots_per_page = 1
    )

    # --- Extract Analysis Results [analyzeBases] ---
    # Key functions: analyzeBases
    sample_1_freq <- output1[[1]][[1]]
    sample_1_counts <- output1[[1]][[2]]
    sample_2_freq <- output1[[2]][[1]]
    sample_2_counts <- output1[[2]][[2]]
    head(sample_1_freq)
    head(sample_1_counts)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bbcanalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bbcanalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bbcanalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BBCANALYZER:", paste0("    bbcanalyzer: ", packageVersion("BBCAnalyzer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bbcanalyzer_results.csv
    touch ${prefix}_bbcanalyzer_output.rds
    echo "BIOC_BBCANALYZER:" > versions.yml
    echo "    bbcanalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BBCANALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BBCANALYZER(ch_input)

    emit:
    results  = BIOC_BBCANALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BBCANALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BBCANALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BBCANALYZER.out.versions  // channel: path(versions.yml)
}
