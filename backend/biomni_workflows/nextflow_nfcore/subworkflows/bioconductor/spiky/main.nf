#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spiky
// spiky implements methods and model generation for cfMeDIP (cell-free methylated DNA immunoprecipitat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spiky/inst/doc/spiky_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("spiky")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPIKY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spiky"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spiky:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spiky:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spiky_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spiky_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spiky_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spiky)
    library(jsonlite)


    # --- Eval = False [] ---
    # Key functions: requireNamespace, install, show, generate_spike_fasta, spiky, extdata, example.spike.bam
    #  #To install this package, start R (version "3.6" or later) and enter:
    #    #if (!requireNamespace("BiocManager", quietly = TRUE))
    #    #  install.packages("BiocManager")
    #    #
    #    #BiocManager::install("spiky")
    #  
    #  library(spiky)

    ## -----------------------------------------------------------------------------
    data(spike)

    ## -----------------------------------------------------------------------------
    sb <- system.file("extdata", "example.spike.bam", package="spiky",              mustWork=TRUE)
    outFasta <- paste(system.file("extdata", package="spiky", mustWork=TRUE),"/spike_contigs.fa",sep="")
    show(generate_spike_fasta(sb, spike=spike,fa=outFasta))

    # --- Eval=true [] ---
    # Key functions: scan_genomic_contigs, scan_spike_contigs, scan_genomic_bedpe, scan_spike_bedpe, extdata, example_chr21.bam, spiky, example.spike.bam
    genomic_bam_path <- system.file("extdata", "example_chr21.bam", package="spiky", mustWork=TRUE)
    genomic_coverage <- scan_genomic_contigs(genomic_bam_path,spike=spike)
    spike_bam_path <- system.file("extdata", "example.spike.bam", package="spiky", mustWork=TRUE)
    spikes_coverage <- scan_spike_contigs(spike_bam_path,spike=spike)


    ## -----------------------------------------------------------------------------
    genomic_bedpe_path <- system.file("extdata", "example_chr21_bedpe.bed.gz", package="spiky", mustWork=TRUE)
    genomic_coverage <- scan_genomic_bedpe(genomic_bedpe_path,genome="hg38")
    spike_bedpe_path <- system.file("extdata", "example_spike_bedpe.bed.gz", package="spiky", mustWork=TRUE)
    spikes_coverage <- scan_spike_bedpe(spike_bedpe_path,spike=spike)

    # --- Eval=true [] ---
    # Key functions: methylation_specificity
    ##Calculate methylation specificity
    methyl_spec <- methylation_specificity(spikes_coverage,spike=spike)
    print(methyl_spec)

    # --- Eval=true [] ---
    # Key functions: model_glm_pmol, summary
    ## Build the Gaussian generalized linear model on the spike-in control data
    gaussian_glm <- model_glm_pmol(spikes_coverage,spike=spike)
    summary(gaussian_glm)

    # --- Eval=true [] ---
    # Key functions: available.packages, predict_pmol
    # Predict pmol concentration
    # To select a genome other than hg38, use BSgenome::available.packages() to find valid BSgenome name
    #library("BSgenome.Hsapiens.UCSC.hg38")
    sample_data_pmol <- predict_pmol(gaussian_glm, genomic_coverage,bsgenome="BSgenome.Hsapiens.UCSC.hg38",ret="df")
    head(sample_data_pmol,n=1)

    # --- Eval=true [] ---
    # Key functions: bin_pmol, sessionInfo
    sample_binned_data <- bin_pmol(sample_data_pmol)
    head(sample_binned_data,n=1)

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spiky_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spiky_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spiky_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPIKY:", paste0("    spiky: ", packageVersion("spiky"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spiky_results.csv
    touch ${prefix}_spiky_output.rds
    echo "BIOC_SPIKY:" > versions.yml
    echo "    spiky: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPIKY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPIKY(ch_input)

    emit:
    results  = BIOC_SPIKY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPIKY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPIKY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPIKY.out.versions  // channel: path(versions.yml)
}
