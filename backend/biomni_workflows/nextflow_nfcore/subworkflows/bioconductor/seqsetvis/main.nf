#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqsetvis — peak_set_overlap_analysis
// Overlap multiple genomic interval sets (such as peak calls) and visualize their intersections using barplots, Venn diagrams, Euler diagrams, or binary heatmaps.
// Input: np_files
// Container: quay.io/biocontainers/bioconductor-seqsetvis:1.30.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqsetvis:1.30.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("biocfilecache", "chippeakanno", "cowplot", "genomicranges", "ggplot2", "seqsetvis")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(seqsetvis)
    library(GenomicRanges)
    library(ggplot2)
    
    # -----------------------------------------------------------------------------
    # 1. Input Handling
    # -----------------------------------------------------------------------------
    # The pipeline expects a named character vector 'np_files' pointing to narrowPeak or BED files.
    # If not already defined in the environment, we automatically discover them in the working directory.
    if (!exists("np_files")) {
      found_files <- list.files(pattern = "\\.(narrowPeak|bed|BED)\$", full.names = TRUE)
      if (length(found_files) == 0) {
        stop("Error: No narrowPeak or BED files found in the working directory, and 'np_files' is not defined.")
      }
      # Name the files based on their file names without extension
      names(found_files) <- tools::file_path_sans_ext(basename(found_files))
      np_files <- found_files
    }
    
    message("Processing the following peak files:")
    print(np_files)
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # -----------------------------------------------------------------------------
    
    # Stage 1: Load peak files into a list of GRanges
    np_grs = easyLoad_narrowPeak(np_files)
    
    # Stage 2: Overlap the interval sets to create a consensus GRanges object with membership metadata
    olaps = ssvOverlapIntervalSets(np_grs)
    
    # Stage 3: Extract the logical membership table
    memb_table = ssvMakeMembTable(olaps)
    
    # Stage 4: Visualize the overlaps
    p_bars = ssvFeatureBars(olaps)
    p_pie = ssvFeaturePie(olaps)
    
    # Venn diagrams in seqsetvis are limited to a maximum of 3 sets.
    # We wrap this in a tryCatch to prevent failure if the user provides more than 3 sets.
    p_venn <- NULL
    if (length(np_files) <= 3) {
      tryCatch({
        p_venn = ssvFeatureVenn(olaps)
      }, error = function(e) {
        message("Warning: Could not generate Venn diagram. ", e\$message)
      })
    } else {
      message("Skipping Venn diagram: ssvFeatureVenn is limited to a maximum of 3 sets (input has ", length(np_files), " sets).")
    }
    
    # Euler diagrams can be computationally expensive or fail with too many sets.
    p_euler <- NULL
    tryCatch({
      p_euler = ssvFeatureEuler(olaps)
    }, error = function(e) {
      message("Warning: Could not generate Euler diagram. ", e\$message)
    })
    
    p_heatmap = ssvFeatureBinaryHeatmap(olaps)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    message("Saving results...")
    
    # Save the consensus GRanges object with membership metadata
    saveRDS(olaps, file = "consensus_overlaps.rds")
    
    # Save the logical membership table
    write.csv(as.data.frame(memb_table), file = "membership_table.csv", row.names = TRUE)
    
    # Save visualization plots
    ggsave("overlap_barplot.pdf", plot = p_bars, width = 6, height = 4)
    ggsave("overlap_piechart.pdf", plot = p_pie, width = 6, height = 4)
    
    if (!is.null(p_venn)) {
      ggsave("overlap_venn.pdf", plot = p_venn, width = 6, height = 6)
    }
    
    if (!is.null(p_euler)) {
      ggsave("overlap_euler.pdf", plot = p_euler, width = 6, height = 6)
    }
    
    ggsave("overlap_binary_heatmap.pdf", plot = p_heatmap, width = 5, height = 7)
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS":
        seqsetvis: \$(Rscript -e 'cat(as.character(packageVersion("seqsetvis")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_set_overlap_analysis.csv versions.yml
    """
}

workflow BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ np_files ] ]

    main:
    BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS.out.tables
    plots    = BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS.out.plots
    objects  = BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS.out.objects
    versions = BIOC_SEQSETVIS_PEAK_SET_OVERLAP_ANALYSIS.out.versions
}
