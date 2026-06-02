#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: motifStack
// The motifStack package is designed for graphic representation of multiple motifs with different simi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/motifStack/inst/doc/motifStack_HTML.R
// Upstream  : JASPAR2020, MotifDb, RColorBrewer, TFBSTools, ade4
// Downstream: generegulation
//
// Install: BiocManager::install("motifStack")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motifstack"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motifstack:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-motifstack:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motifstack_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motifstack_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motifstack_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(motifStack)
    library(DNAmotifToRNAmotif)
    library(jsonlite)

    # --- Motif Import and Object Construction [Importing] ---
    # Key functions: importMatrix, pcm2pfm
    pcm_file <- system.file("extdata", "bin_SOLEXA.pcm",
                            package = "motifStack")
    pcm_data <- read.table(pcm_file)
    pcm_data <- pcm_data[, 3:ncol(pcm_data)]
    rownames(pcm_data) <- c("A", "C", "G", "T")
    motif_pcm <- new("pcm", mat = as.matrix(pcm_data), name = "bin_SOLEXA")
    motif_pfm <- pcm2pfm(pcm_data)
    motif_pfm_obj <- new("pfm", mat = motif_pfm, name = "bin_SOLEXA")

    # --- Single Motif Customization and Plotting [Visualisation] ---
    # Key functions: colorset, plot
    markerRect <- new("marker", type = "rect", start = 6, stop = 7,
                      gp = grid::gpar(lty = 2, fill = NA, col = "orange"))
    markerLine <- new("marker", type = "line", start = 2, stop = 7,
                      gp = grid::gpar(lwd = 2, col = "red"))
    motif_pcm@markers <- c(markerRect, markerLine)
    motif_pcm@color <- colorset(colorScheme = "basepairing")
    plot(motif_pcm, ic.scale = FALSE, ylab = "probability", font = "serif")

    # --- Motif Stack Visualization [Visualisation] ---
    # Key functions: importMatrix, DNAmotifToRNAmotif, motifStack
    motif_files <- dir(system.file("extdata", package = "motifStack"),
                       pattern = "pcm$", full.names = TRUE)
    motifs_list <- importMatrix(motif_files)
    rna_motifs <- DNAmotifToRNAmotif(motifs_list)
    motifStack(rna_motifs, layout = "stack", reorder = FALSE)

    # --- Radial Motif Tree Visualization [Visualisation] ---
    # Key functions: trimMotif, motifStack
    trimmed_motifs <- lapply(motifs_list, trimMotif, t = 0.4)
    formatted_motifs <- mapply(trimmed_motifs, names(trimmed_motifs),
                               FUN = function(.ele, .name) {
                                   new("pfm", mat = .ele, name = .name)
                               }, SIMPLIFY = FALSE)
    motifStack(formatted_motifs, layout = "radialPhylog",
               circle = 0.3, cleaves = 0.2, clabel.leaves = 0.5,
               circle.motif = 1.2, angle = 350)

    # --- Motif Clustering and Signature Analysis [Analysis] ---
    # Key functions: clusterMotifs, motifSignature
    hc <- clusterMotifs(formatted_motifs)
    phylog <- ade4::hclust2phylog(hc)
    ordered_motifs <- formatted_motifs[names(phylog$leaves)]
    motif_sig <- motifSignature(ordered_motifs, phylog,
                                cutoffPval = 0.0001, min.freq = 1)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motifstack_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motifstack_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motifstack_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFSTACK:", paste0("    motifstack: ", packageVersion("motifStack"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motifstack_results.csv
    touch ${prefix}_motifstack_output.rds
    echo "BIOC_MOTIFSTACK:" > versions.yml
    echo "    motifstack: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFSTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFSTACK(ch_input)

    emit:
    results  = BIOC_MOTIFSTACK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFSTACK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFSTACK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFSTACK.out.versions  // channel: path(versions.yml)
}
