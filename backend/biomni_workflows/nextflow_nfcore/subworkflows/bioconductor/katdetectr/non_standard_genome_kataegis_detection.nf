#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: katdetectr — non_standard_genome_kataegis_detection
// Detect kataegis foci in samples aligned to non-standard reference genomes by providing explicit sequence lengths.
// Input: genomic_variants.rds
// Container: quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0
// R packages: GenomeInfoDb, GenomicRanges, VariantAnnotation, katdetectr
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomeInfoDb, GenomicRanges, VariantAnnotation, katdetectr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a data frame containing the lengths of the non-standard sequences
//  * 2. [Core Analysis] Run detectKataegis with the refSeq argument

nextflow.enable.dsl = 2

process BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GenomeInfoDb", "GenomicRanges", "VariantAnnotation", "katdetectr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(katdetectr)
    library(VariantAnnotation)
    library(GenomicRanges)
    library(GenomeInfoDb)
    
    # Define input file
    input_file <- "genomic_variants.rds"
    
    if (!file.exists(input_file)) {
        stop(paste("Required input file missing:", input_file))
    }
    
    # Read the VRanges object containing variants on non-standard chromosomes
    syndata <- readRDS(input_file)
    
    # 1. Construct a data frame containing the lengths of the non-standard sequences
    # We dynamically extract the sequence names from the input VRanges object
    # and estimate their lengths based on the maximum variant coordinate.
    seqs <- unique(as.character(GenomeInfoDb::seqnames(syndata)))
    lengths_list <- list()
    for (s in seqs) {
        variants_on_chr <- syndata[GenomeInfoDb::seqnames(syndata) == s]
        if (length(variants_on_chr) > 0) {
            max_coord <- max(BiocGenerics::end(variants_on_chr))
            # Add a buffer to ensure the sequence length is greater than the last variant position
            lengths_list[[s]] <- as.numeric(max_coord + 100000)
        } else {
            lengths_list[[s]] <- 1000000
        }
    }
    sequenceLength <- as.data.frame(lengths_list)
    
    # 2. Run detectKataegis with the refSeq argument
    kdNonStandard <- detectKataegis(genomicVariants = syndata, refSeq = sequenceLength)
    
    # Write named output files for the meaningful results
    # Save the KatDetect object
    saveRDS(kdNonStandard, "kdNonStandard.rds")
    
    # Extract and save genomic variants with kataegis status
    gv <- getGenomicVariants(kdNonStandard)
    saveRDS(gv, "genomic_variants_output.rds")
    write.csv(as.data.frame(gv), "genomic_variants_output.csv", row.names = FALSE)
    
    # Extract and save segments
    seg <- getSegments(kdNonStandard)
    saveRDS(seg, "segments.rds")
    write.csv(as.data.frame(seg), "segments.csv", row.names = FALSE)
    
    # Extract and save kataegis foci
    foci <- getKataegisFoci(kdNonStandard)
    saveRDS(foci, "kataegis_foci.rds")
    write.csv(as.data.frame(foci), "kataegis_foci.csv", row.names = FALSE)
    
    # Generate and save rainfall plot
    pdf("rainfall_plot.pdf", width = 12, height = 7)
    tryCatch({
        p <- rainfallPlot(kdNonStandard)
        print(p)
    }, error = function(e) {
        warning("Could not generate rainfall plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION":',
        paste0('    katdetectr: ', as.character(packageVersion('katdetectr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_standard_genome_kataegis_detection.csv versions.yml
    """
}

workflow BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_variants.rds ] ]

    main:
    BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION(ch_input)

    emit:
    tables   = BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION.out.tables
    plots    = BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION.out.plots
    objects  = BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION.out.objects
    versions = BIOC_KATDETECTR_NON_STANDARD_GENOME_KATAEGIS_DETECTION.out.versions
}
