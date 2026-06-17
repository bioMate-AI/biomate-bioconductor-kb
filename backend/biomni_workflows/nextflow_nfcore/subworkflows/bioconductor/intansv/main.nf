#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: intansv — sv_integration_annotation_visualization
// Read structural variation predictions from multiple callers, merge them into a consensus set, annotate their genomic effects, and visualize their distribution.
// Input: ZS97.breakdancer.sv, cnvnator, svseq2, ZS97.DELLY.vcf, pindel, ZS97.LUMPY.vcf, ZS97.softsearch, chr05_chr10.anno.txt, chr05_chr10.genome.txt
// Container: quay.io/biocontainers/bioconductor-intansv:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: intansv, plyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read predictions from individual SV callers using readBreakDancer, readCnvnator, readSvseq, readDelly, readPindel, readLumpy, and 
//  * 2. [Core Analysis] Integrate predictions from multiple programs using methodsMerge
//  * 3. [Input & Preparation] Load genomic annotation and annotate SV effects using svAnnotation
//  * 4. [Visualization & Output] Load genome chromosome lengths and plot whole-genome SV distribution using plotChromosome
//  * 5. [Visualization & Output] Visualize SVs in a specific genomic region using plotRegion

nextflow.enable.dsl = 2

process BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("intansv", "plyr")
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
    library(intansv)
    library(plyr)
    
    # Define input file paths from the working directory
    breakdancer.file.path <- "ZS97.breakdancer.sv"
    cnvnator.dir.path     <- "cnvnator"
    svseq.dir.path        <- "svseq2"
    delly.file.path       <- "ZS97.DELLY.vcf"
    pindel.dir.path       <- "pindel"
    lumpy.file.path       <- "ZS97.LUMPY.vcf"
    softSearch.file.path  <- "ZS97.softsearch"
    anno.file.path        <- "chr05_chr10.anno.txt"
    genome.file.path      <- "chr05_chr10.genome.txt"
    
    # 1. Read predictions from individual SV callers
    message("Reading BreakDancer predictions...")
    breakdancer <- readBreakDancer(breakdancer.file.path)
    
    message("Reading CNVnator predictions...")
    cnvnator <- readCnvnator(cnvnator.dir.path)
    
    message("Reading SVseq2 predictions...")
    svseq <- readSvseq(svseq.dir.path)
    
    message("Reading DELLY predictions...")
    delly <- readDelly(delly.file.path)
    
    message("Reading Pindel predictions...")
    pindel <- readPindel(pindel.dir.path)
    
    message("Reading Lumpy predictions...")
    lumpy <- readLumpy(lumpy.file.path)
    
    message("Reading softSearch predictions...")
    softSearch <- readSoftSearch(softSearch.file.path)
    
    # 2. Integrate predictions from multiple programs
    message("Merging SV predictions...")
    sv_all_methods <- methodsMerge(breakdancer, pindel, cnvnator, delly, svseq)
    
    # Save merged SV predictions
    saveRDS(sv_all_methods, "sv_all_methods.rds")
    
    # 3. Load genomic annotation and annotate SV effects
    message("Loading genomic annotations...")
    msu_gff_v7 <- read.table(anno.file.path, head=TRUE, as.is=TRUE)
    
    message("Annotating SV effects...")
    sv_all_methods.anno <- llply(sv_all_methods, svAnnotation,
                                 genomeAnnotation=msu_gff_v7)
    
    # Save annotated SV predictions
    saveRDS(sv_all_methods.anno, "sv_all_methods_annotated.rds")
    
    # Export annotated SVs to CSV files
    for (sv_type in names(sv_all_methods.anno)) {
      df <- sv_all_methods.anno[[sv_type]]
      if (!is.null(df) && nrow(df) > 0) {
        write.csv(df, file = paste0("annotated_", sv_type, ".csv"), row.names = FALSE)
      }
    }
    
    # 4. Load genome chromosome lengths and plot whole-genome SV distribution
    message("Loading genome chromosome lengths...")
    genome <- read.table(genome.file.path, head=TRUE, as.is=TRUE)
    
    message("Plotting whole-genome SV distribution...")
    pdf("sv_chromosome_distribution.pdf", width = 10, height = 10)
    plotChromosome(genome, sv_all_methods, 1000000)
    dev.off()
    
    # 5. Visualize SVs in a specific genomic region
    message("Plotting SVs in specific genomic region (chr05:1-200000)...")
    pdf("sv_region_visualization.pdf", width = 10, height = 8)
    plotRegion(sv_all_methods, msu_gff_v7, "chr05", 1, 200000)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION":',
        paste0('    intansv: ', as.character(packageVersion('intansv')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sv_integration_annotation_visualization.csv versions.yml
    """
}

workflow BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ZS97.breakdancer.sv, cnvnator, svseq2, ZS97.DELLY.vcf, pindel, ZS97.LUMPY.vcf, ZS97.softsearch, chr05_chr10.anno.txt, chr05_chr10.genome.txt ] ]

    main:
    BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION.out.tables
    plots    = BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION.out.plots
    objects  = BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION.out.objects
    versions = BIOC_INTANSV_SV_INTEGRATION_ANNOTATION_VISUALIZATION.out.versions
}
