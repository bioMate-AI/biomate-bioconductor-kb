#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: abseqR
// AbSeq is a comprehensive bioinformatic pipeline for the analysis of sequencing datasets generated fr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/abseqR/inst/doc/abseqR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("abseqR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-abseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-abseqr:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-abseqr:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_abseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_abseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_abseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(abseqR)
    library(jsonlite)


    # --- Abseq R Vignette Helper Functions [] ---
    # Key functions: function, Biocpkg, file.exists, rasterGrob, as.raster, readPNG, include_graphics, normalizePath
    sabseqR <- function() { return(Biocpkg("abseqR")); }
    #sabseqR <- function() { return("`abseqR`"); }
    sabseqPy <- function() { return("[abseqPy](https://github.com/malhamdoosh/abseqPy)"); }
    sabseq <- function() { return("`AbSeq`"); }
    # --- Abseq R Abseq Report Compare Argument [] ---
    # Key functions: abseqReport, name, report, refined_comparison
    # Example of 1 comparison
    # Analyze all samples, but only compare PCR1 with PCR2
    pcr1.pcr2 <- abseqReport(dataPath,
                             compare = c("PCR1, PCR2"),
                             report = 0)

    # Example of 2 comparisons
    # Analyze all samples. In addition, compare:
    #  * PCR1 with PCR2
    #  * PCR2 with PCR3
    # compare = c("PCR1,PCR2")
    names(pcr1.pcr2)

    # compare = c("PCR1, PCR2", "PCR2 ,PCR3")
    names(multiComparison)
    # recall that samples is a named list where each element's name
    # is the sample's own name (see names(samples))

    # use report = 3 if the results should be collated in a HTML document
    pcr1.pcr3 <- samples[["PCR1"]] + samples[["PCR3"]]

    # --- Abseq R Plot Path Setup [] ---
    # Key functions: read_png, auxiliary, PCR1_vs_PCR2_vs_PCR3, annot, PCR1_all_clones_len_dist.png, abundance, PCR1_igv_align_quality_bitscore_hm_static.png, PCR1_igv_gaps_dist.png
    # [s]ingle sample [dir]ectory
    sdir <- file.path(dataPath, "auxiliary", "PCR1")
    # [m]ulti sample [dir]ectory
    mdir <- file.path(dataPath, "auxiliary", "PCR1_vs_PCR2_vs_PCR3")

    ## ----seq-len, fig.cap="Sequence length distribution of PCR1. Histogram of (merged) sequence lengths.", echo=FALSE, out.width="100%"----
    read_png(file.path(sdir, "annot", "PCR1_all_clones_len_dist.png"))

    ## ----align-qual, fig.cap="Bitscore vs V germline alignment length in PCR1. Heatmap of bitscore vs alignment length shows percentage of sequences in a given value range.", echo=FALSE, out.width="100%"----
    read_png(file.path(sdir, "abundance", "PCR1_igv_align_quality_bitscore_hm_static.png"))
    read_png(file.path(sdir, "abundance", "PCR1_igv_gaps_dist.png"))
    read_png(file.path(sdir, "abundance", "PCR1_igv_dist_family_level.png"))
    read_png(file.path(sdir, "abundance", "PCR1_vjassoc.png"))

    ## ----prod-summ, fig.cap="Productivity rate of sequences in PCR1. This plot shows the percentage of productive and unproductive sequences, the reason for unproductive sequences are colour coded.", echo=FALSE, out.width="100%"----
    read_png(file.path(sdir, "productivity", "PCR1_productivity.png"))

    # --- Frameshift [] ---
    # Key functions: read_png, productivity, PCR1_vjframe_dist.png, PCR1_stopcodon_region_outframe.png, PCR1_fr3_mismatches_dist.png, PCR1_fr3_gaps_dist.png, PCR1_fr3_gaps_dist_out_of_frame.png
    read_png(file.path(sdir, "productivity", "PCR1_vjframe_dist.png"))
    read_png(file.path(sdir, "productivity", "PCR1_stopcodon_region_outframe.png"))
    read_png(file.path(sdir, "productivity", "PCR1_fr3_mismatches_dist.png"))
    read_png(file.path(sdir, "productivity", "PCR1_fr3_gaps_dist.png"))

    ## ----gaps-out, fig.cap="Proportion of indels in out-of-frame sequences of PCR1.", echo=FALSE, out.width="100%"----
    read_png(file.path(sdir, "productivity", "PCR1_fr3_gaps_dist_out_of_frame.png"))

    # --- Duplication [] ---
    # Key functions: read_png, diversity, PCR1_cdr_duplication.png, PCR1_cdr_rarefaction.png, PCR1_cdr_recapture.png, spectratypes, PCR1_cdr3_spectratype_no_outliers.png
    read_png(file.path(sdir, "diversity", "PCR1_cdr_duplication.png"))
    read_png(file.path(sdir, "diversity", "PCR1_cdr_rarefaction.png"))
    read_png(file.path(sdir, "diversity", "PCR1_cdr_recapture.png"))
    read_png(file.path(sdir, "diversity", "spectratypes", "PCR1_cdr3_spectratype_no_outliers.png"))

    # --- Comp [] ---
    # Key functions: rasterGrob, as.raster, readPNG, grid.arrange, diversity, composition_logos, PCR1_cumulative_logo.png, PCR1_cumulative_logo_scaled.png
    unscaled <- file.path(sdir, "diversity", "composition_logos", "CDR3", "PCR1_cumulative_logo.png")
    scaled <- file.path(sdir, "diversity", "composition_logos", "CDR3", "PCR1_cumulative_logo_scaled.png")
    img1 <-  rasterGrob(as.raster(readPNG(unscaled)), interpolate = TRUE)
    img2 <- rasterGrob(as.raster(readPNG(scaled)), interpolate = TRUE)
    grid.arrange(img1, img2, ncol = 2)
    read_png(file.path(mdir, "clonotype_analysis", "PCR1_PCR2_PCR3_top10Clonotypes.png"))
    read_png(file.path(mdir, "clonotype_analysis", "PCR1_PCR2_PCR3_cdr3_clonotypeIntersection.png"))
    read_png(file.path(mdir, "clonotype_analysis", "PCR1_vs_PCR2_clone_scatter.png"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_abseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_abseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_abseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ABSEQR:", paste0("    abseqr: ", packageVersion("abseqR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_abseqr_results.csv
    touch ${prefix}_abseqr_output.rds
    echo "BIOC_ABSEQR:" > versions.yml
    echo "    abseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ABSEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_ABSEQR(ch_input)

    emit:
    results  = BIOC_ABSEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ABSEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ABSEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ABSEQR.out.versions  // channel: path(versions.yml)
}
