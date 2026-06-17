#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: svaNUMT — detect_and_visualize_numts
// Detect nuclear-mitochondrial DNA fusion (NUMT) events from structural variant calls and visualize them using circos plots.
// Input: vcf_file.vcf, numtS_file.txt, BSgenome
// Container: quay.io/biocontainers/bioconductor-svanumt:1.16.0--r45hdfd78af_0
// R packages: GenomeInfoDb, S4Vectors, circlize, readr, StructuralVariantAnnotation, svaNUMT, VariantAnnotation
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, S4Vectors, StructuralVariantAnnotation, VariantAnnotation, circlize, readr, svaNUMT
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load structural variant calls from VCF and convert to breakend-centric GRanges
//  * 2. [Input & Preparation] Load and format known NUMT regions
//  * 3. [Core Analysis] Extract the mitochondrial genome sequence
//  * 4. [Core Analysis] Detect NUMT events using numtDetect
//  * 5. [Core Analysis] Subset or filter detected NUMTs by genomic region
//  * 6. [Visualization & Output] Convert breakends to pairs and visualize using circlize circos plots

nextflow.enable.dsl = 2

process BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS {
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
    .bm_deps <- c("GenomeInfoDb", "S4Vectors", "circlize", "readr", "StructuralVariantAnnotation", "svaNUMT", "VariantAnnotation")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
        library(svaNUMT)
        library(readr)
        library(circlize)
        library(GenomeInfoDb)
        library(S4Vectors)
        
        # 1. Load structural variant calls from VCF and convert to breakend-centric GRanges
        vcf <- readVcf("vcf_file.vcf")
        gr <- breakpointRanges(vcf)
        
        # 2. Load and format known NUMT regions
        numtS <- read_table("numtS_file.txt", col_names = FALSE)
        colnames(numtS) <- c("bin", "seqnames", "start", "end", "name", "score", "strand")
        numtS <- GRanges(numtS)
        GenomeInfoDb::seqlevelsStyle(numtS) <- "NCBI"
        
        # 3. Extract the mitochondrial genome sequence from the provided BSgenome object
        genome <- readRDS("BSgenome")
        genomeMT <- genome\$chrMT
        
        # 4. Detect NUMT events using numtDetect
        NUMT <- numtDetect(gr, numtS, genomeMT, max_ins_dist = 20)
        saveRDS(NUMT, "detected_numts.rds")
        
        # Save GRangesList of the first detected NUMT event if available
        tryCatch({
          if ("1" %in% names(NUMT\$MT\$NU) && length(NUMT\$MT\$NU\$`1`) >= 1) {
            gr_list <- GRangesList(NU=NUMT\$MT\$NU\$`1`[[1]], MT=NUMT\$MT\$MT\$`1`[[1]])
            saveRDS(gr_list, "numt_granges_list.rds")
          }
        }, error = function(e) {
          message("Could not save GRangesList: ", e\$message)
        })
        
        # 5. Subset or filter detected NUMTs by genomic region
        seqnames <- "1"
        if (!(seqnames %in% names(NUMT\$MT\$NU)) && length(names(NUMT\$MT\$NU)) > 0) {
          seqnames <- names(NUMT\$MT\$NU)[1]
        }
        
        tryCatch({
          if (seqnames %in% names(NUMT\$MT\$NU) && length(NUMT\$MT\$NU[[seqnames]]) > 0) {
            start <- 1000000
            end <- 3000000
            i <- sapply(NUMT\$MT\$NU[[seqnames]], function(x) {
              sum(countOverlaps(x, GRanges(seqnames = seqnames, IRanges(start, end)))) > 0
            })
            subset_numts <- list(NU=NUMT\$MT\$NU[[seqnames]][i], MT=NUMT\$MT\$MT[[seqnames]][i])
            saveRDS(subset_numts, "subset_numts.rds")
          }
        }, error = function(e) {
          message("Subsetting NUMTs failed: ", e\$message)
        })
        
        # 6. Convert breakends to pairs and visualize using circlize circos plots
        tryCatch({
          if ("1" %in% names(NUMT\$MT\$NU) && length(NUMT\$MT\$NU\$`1`) >= 2) {
            numt_chr_prefix <- c(NUMT\$MT\$NU\$`1`[[2]], NUMT\$MT\$MT\$`1`[[2]])
          } else if (length(names(NUMT\$MT\$NU)) > 0 && length(NUMT\$MT\$NU[[1]]) >= 1) {
            first_chrom <- names(NUMT\$MT\$NU)[1]
            numt_chr_prefix <- c(NUMT\$MT\$NU[[first_chrom]][[1]], NUMT\$MT\$MT[[first_chrom]][[1]])
          } else {
            stop("No valid NUMT events found for visualization.")
          }
        
          GenomeInfoDb::seqlevelsStyle(numt_chr_prefix) <- "UCSC"
          pairs <- breakpointgr2pairs(numt_chr_prefix)
          saveRDS(pairs, "breakpoint_pairs.rds")
        
          pdf("numt_circos_plot.pdf", width = 8, height = 8)
          
          # Dynamically determine the nuclear chromosome and coordinates for the ideogram
          nu_idx <- as.character(seqnames(numt_chr_prefix)) != "chrM"
          nu_chr <- as.character(seqnames(numt_chr_prefix)[nu_idx][1])
          nu_start <- max(1, min(start(numt_chr_prefix[nu_idx])) - 10)
          nu_end <- max(end(numt_chr_prefix[nu_idx])) + 10
          
          circos.initializeWithIdeogram(
              data.frame(V1=c(nu_chr, "chrM"),
                         V2=c(nu_start, 1),
                         V3=c(nu_end, 16571),
                         V4=c("p15.4",NA),
                         V5=c("gpos50",NA)),  sector.width = c(0.2, 0.8))
          
          circos.genomicLink(as.data.frame(S4Vectors::first(pairs)), 
                             as.data.frame(S4Vectors::second(pairs)))
          circos.clear()
          dev.off()
        }, error = function(e) {
          message("Circos plotting skipped or failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS":',
        paste0('    svaNUMT: ', as.character(packageVersion('svaNUMT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_and_visualize_numts.csv versions.yml
    """
}

workflow BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vcf_file.vcf, numtS_file.txt, BSgenome ] ]

    main:
    BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS(ch_input)

    emit:
    tables   = BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS.out.tables
    plots    = BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS.out.plots
    objects  = BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS.out.objects
    versions = BIOC_SVANUMT_DETECT_AND_VISUALIZE_NUMTS.out.versions
}
