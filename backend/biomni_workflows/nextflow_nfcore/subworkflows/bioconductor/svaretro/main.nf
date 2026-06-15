#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: svaRetro — detect_and_visualize_rts
// Detect retrotransposed transcripts from structural variant calls and visualize the resulting junctions and insertion sites.
// Input: diploidSV.vcf, TxDb.Hsapiens.UCSC.hg19.knownGene
// Container: quay.io/biocontainers/bioconductor-svaretro:1.15.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, GenomeInfoDb, S4Vectors, StructuralVariantAnnotation, TxDb.Hsapiens.UCSC.hg19.knownGene, VariantAnnotation, circlize, dplyr, svaRetro
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load VCF data and convert to breakend-centric GRanges
//  * 2. [Visualization & Output] Load Transcript Database
//  * 3. [Visualization & Output] Identify retrotransposed transcripts using rtDetect
//  * 4. [Visualization & Output] Format the detected breakends into pairs using
//  * 5. [Visualization & Output] Visualize the breakpoint pairs using circlize

nextflow.enable.dsl = 2

process BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("StructuralVariantAnnotation", "VariantAnnotation", "svaRetro", "dplyr", "circlize", "GenomeInfoDb", "S4Vectors", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
    library(StructuralVariantAnnotation)
    library(VariantAnnotation)
    library(svaRetro)
    library(dplyr)
    library(circlize)
    library(GenomeInfoDb)
    library(S4Vectors)
    
    # --- Load VCF data and convert to breakend-centric GRanges ---
    # Read exactly the user-provided VCF file from the working directory
    vcf_file <- "diploidSV.vcf"
    if (!file.exists(vcf_file)) {
      stop(paste("Required input file missing:", vcf_file))
    }
    
    RT_vcf <- readVcf(vcf_file)
    RT_gr <- StructuralVariantAnnotation::breakpointRanges(RT_vcf,
      nominalPosition = TRUE
    )
    head(RT_gr)
    
    # --- Load Transcript Database ---
    # Read the user-provided TxDb from the working directory if present,
    # otherwise fall back to loading the installed package.
    txdb_file <- "TxDb.Hsapiens.UCSC.hg19.knownGene"
    if (file.exists(txdb_file)) {
      message("Loading TxDb from local file...")
      hg19.genes <- tryCatch({
        AnnotationDbi::loadDb(txdb_file)
      }, error = function(e) {
        readRDS(txdb_file)
      })
    } else {
      message("Loading TxDb from package...")
      library(TxDb.Hsapiens.UCSC.hg19.knownGene)
      hg19.genes <- TxDb.Hsapiens.UCSC.hg19.knownGene
    }
    
    # --- Identify retrotransposed transcripts using rtDetect ---
    RT <- rtDetect(RT_gr, hg19.genes, maxgap = 10, minscore = 0.8)
    
    # Save the complete detected retrotransposed transcripts object
    saveRDS(RT, "detected_retrotranscripts.rds")
    
    # Dynamically select a detected gene for downstream steps
    if (length(RT) > 0) {
      # Find first gene with any junctions or insertion sites
      has_events <- sapply(RT, function(x) length(x\$junctions) > 0 || length(x\$insSite) > 0)
      if (any(has_events)) {
        target_gene <- names(RT)[which(has_events)[1]]
        message(paste("Selected gene", target_gene, "for downstream steps."))
      } else {
        target_gene <- names(RT)[1]
        message("Selected first gene for downstream steps.")
      }
      rt_target <- RT[[target_gene]]
    } else {
      # Create an empty placeholder structure if no genes were detected
      target_gene <- "None"
      rt_target <- list(junctions = GRanges(), insSite = GRanges())
      message("No retrotransposition events detected. Using empty placeholders.")
    }
    
    # Print target gene details
    rt_target
    
    # Export target gene junctions and insertion sites to CSV if they exist
    if (length(rt_target\$junctions) > 0) {
      write.csv(as.data.frame(rt_target\$junctions), paste0(target_gene, "_junctions.csv"), row.names = FALSE)
    }
    if (length(rt_target\$insSite) > 0) {
      write.csv(as.data.frame(rt_target\$insSite), paste0(target_gene, "_insertion_sites.csv"), row.names = FALSE)
    }
    
    # --- Format the detected breakends into pairs using ---
    rt_chr_prefix <- c(rt_target\$junctions, rt_target\$insSite)
    
    if (length(rt_chr_prefix) > 0) {
      GenomeInfoDb::seqlevelsStyle(rt_chr_prefix) <- "UCSC"
      pairs <- breakpointgr2pairs(rt_chr_prefix)
      pairs
      saveRDS(pairs, "breakpoint_pairs.rds")
    } else {
      pairs <- GRangesList()
      message("No junctions or insertion sites to pair.")
    }
    
    # --- Visualize the breakpoint pairs using circlize ---
    # Save the visualization to a PDF file
    pdf("retrotransposition_circos_plot.pdf", width = 8, height = 8)
    
    tryCatch({
      if (length(pairs) > 0) {
        first_gr <- S4Vectors::first(pairs)
        second_gr <- S4Vectors::second(pairs)
        
        all_gr <- c(first_gr, second_gr)
        
        seqs <- as.character(seqnames(all_gr))
        starts <- start(all_gr)
        ends <- end(all_gr)
        
        df <- data.frame(chr = seqs, start = starts, end = ends)
        
        agg_df <- df %>%
          group_by(chr) %>%
          summarize(
            min_start = max(1, min(start) - 50000),
            max_end = max(end) + 50000,
            .groups = "drop"
          ) %>%
          as.data.frame()
        
        ideo_df <- data.frame(
          V1 = agg_df\$chr,
          V2 = agg_df\$min_start,
          V3 = agg_df\$max_end,
          V4 = paste0("reg", 1:nrow(agg_df)),
          V5 = rep("gneg", nrow(agg_df))
        )
        
        circos.initializeWithIdeogram(ideo_df)
        
        circos.genomicLink(
          as.data.frame(first_gr),
          as.data.frame(second_gr)
        )
      } else {
        message("Skipping genomic link plotting due to empty breakpoint pairs.")
      }
      
      circos.clear()
    }, error = function(e) {
      message("Circos plotting encountered an error: ", e\$message)
      # Ensure device is cleared even on error
      circos.clear()
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS":',
        paste0('    svaRetro: ', as.character(packageVersion('svaRetro')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_and_visualize_rts.csv versions.yml
    """
}

workflow BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ diploidSV.vcf, TxDb.Hsapiens.UCSC.hg19.knownGene ] ]

    main:
    BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS(ch_input)

    emit:
    tables   = BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS.out.tables
    plots    = BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS.out.plots
    objects  = BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS.out.objects
    versions = BIOC_SVARETRO_DETECT_AND_VISUALIZE_RTS.out.versions
}
