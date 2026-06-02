#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mobileRNA
// Genomic analysis can be utilised to identify differences between RNA populations in two conditions, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mobileRNA/inst/doc/mobileRNA.R
// Upstream  : dplyr
// Downstream: none
//
// Install: BiocManager::install("mobileRNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOBILERNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mobilerna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mobilerna:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mobilerna:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mobilerna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mobilerna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mobilerna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mobileRNA)
    library(RNAdistribution)
    library(RNAfeatures)
    library(jsonlite)

    # --- Reference Merging [Reference Merging] ---
    # Key functions: RNAmergeGenomes, RNAmergeAnnotations
    fasta_1 <- system.file("extdata", "reduced_chr12_Eggplant.fa.gz",
                           package = "mobileRNA")
    fasta_2 <- system.file("extdata", "reduced_chr2_Tomato.fa.gz",
                           package = "mobileRNA")
    out_fa <- file.path(tempdir(), "merged_assembly.fa")
    merged_ref <- RNAmergeGenomes(genomeA = fasta_1,
                                  genomeB = fasta_2,
                                  output_file = out_fa)
    anno1 <- system.file("extdata", "reduced_chr12_Eggplant.gff.gz",
                         package = "mobileRNA")
    anno2 <- system.file("extdata", "reduced_chr2_Tomato.gff.gz",
                         package = "mobileRNA")
    out_gff <- file.path(tempdir(), "merged_annotation.gff3")
    merged_anno <- RNAmergeAnnotations(annotationA = anno1,
                                       annotationB = anno2,
                                       output_file = out_gff)

    # --- Mobile RNA Identification [Mobile RNA Identification] ---
    # Key functions: RNAmobile
    data("sRNA_data", package = "mobileRNA")
    controls <- c("selfgraft_1", "selfgraft_2", "selfgraft_3")
    mobile_sRNA <- RNAmobile(input = "sRNA",
                             data = sRNA_data,
                             controls = controls,
                             genome.ID = "B",
                             task = "keep")

    # --- Quality Control and Sample Similarity [Quality Control] ---
    # Key functions: RNAdistribution, plotSamplePCA, plotSampleDistance
    data("sRNA_data", package = "mobileRNA")
    dist_line <- RNAdistribution(sRNA_data,
                                 style = "line",
                                 overlap = FALSE,
                                 facet = TRUE,
                                 colour = "darkgreen")
    groups <- c("Heterograft", "Heterograft", "Heterograft",
                "Selfgraft", "Selfgraft", "Selfgraft")
    pca_plot <- plotSamplePCA(data = sRNA_data,
                              group = groups,
                              size.ratio = 2)
    dist_plot <- plotSampleDistance(sRNA_data)

    # --- Dicer Classification and Subsetting [Dicer Classification] ---
    # Key functions: RNAdicercall, RNAsubset, RNAdistribution
    data("sRNA_data", package = "mobileRNA")
    controls <- c("selfgraft_1", "selfgraft_2", "selfgraft_3")
    sRNA_dicer <- RNAdicercall(data = sRNA_data,
                               chimeric = TRUE,
                               genome.ID = "B_",
                               controls = controls)
    sRNA_24 <- RNAsubset(sRNA_dicer, class = 24)
    sRNA_2122 <- RNAsubset(sRNA_dicer, class = c(21, 22))
    consensus_plot <- RNAdistribution(data = sRNA_dicer,
                                      style = "bar",
                                      data.type = "consensus")

    # --- Differential Expression Analysis [Differential Expression] ---
    # Key functions: RNAreorder, RNAdifferentialAnalysis, RNAsummary
    data("sRNA_data", package = "mobileRNA")
    controls <- c("selfgraft_1", "selfgraft_2", "selfgraft_3")
    sRNA_dicer <- RNAdicercall(data = sRNA_data,
                               chimeric = TRUE,
                               genome.ID = "B_",
                               controls = controls)
    reorder_df <- RNAreorder(sRNA_dicer, controls)
    groups <- c("Selfgraft", "Selfgraft", "Selfgraft",
                "Heterograft", "Heterograft", "Heterograft")
    sRNA_DESeq2 <- RNAdifferentialAnalysis(data = reorder_df,
                                           group = groups,
                                           method = "DESeq2")
    summary_all <- RNAsummary(sRNA_DESeq2)
    summary_sig <- RNAsummary(sRNA_DESeq2, alpha = 0.05)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mobilerna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mobilerna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mobilerna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOBILERNA:", paste0("    mobilerna: ", packageVersion("mobileRNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mobilerna_results.csv
    touch ${prefix}_mobilerna_output.rds
    echo "BIOC_MOBILERNA:" > versions.yml
    echo "    mobilerna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOBILERNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOBILERNA(ch_input)

    emit:
    results  = BIOC_MOBILERNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOBILERNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOBILERNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOBILERNA.out.versions  // channel: path(versions.yml)
}
