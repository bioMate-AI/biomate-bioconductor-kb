#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ATACseqTFEA — one_step_tfea
// Perform transcription factor enrichment analysis (TFEA) in a single step using pre-shifted BAM files and prepared binding sites.
// Input: bamExp.bam, bamCtl.bam, PWMatrixList.rds, peaks.granges
// Container: quay.io/biocontainers/bioconductor-atacseqtfea:1.12.0--r45hdfd78af_0
// R packages: BSgenome.Drerio.UCSC.danRer10, GenomicRanges, ATACseqQC, ATACseqTFEA, Rsamtools
// Bioconductor: 3.20 | R: 4.4
// Requires: ATACseqQC, ATACseqTFEA, BSgenome.Drerio.UCSC.danRer10, GenomicRanges, Tal1
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load motifs and scan genome for binding sites using prepareBindingSites
//  * 2. [Core Analysis] Run one-step TFEA using TFEA
//  * 3. [Visualization & Output] Visualize results using ESvolcanoplot, plotES, and factorFootprints

nextflow.enable.dsl = 2

process BIOC_ATACSEQTFEA_ONE_STEP_TFEA {
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
    .bm_deps <- c("BSgenome.Drerio.UCSC.danRer10", "GenomicRanges", "ATACseqQC", "ATACseqTFEA", "Rsamtools")
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
        library(ATACseqTFEA)
        library(BSgenome.Drerio.UCSC.danRer10)
        library(ATACseqQC)
        library(GenomicRanges)
        
        # 1. Load user-provided input files
        motifs <- readRDS("PWMatrixList.rds")
        peaks <- readRDS("peaks.granges")
        
        # Define BAM files
        bamExp <- "bamExp.bam"
        bamCtl <- "bamCtl.bam"
        
        # Extract sequence levels (chromosomes) from the peaks object
        seqlev <- unique(as.character(seqnames(peaks)))
        
        # 2. Scan genome for binding sites
        bindingSites <- prepareBindingSites(
          motifs, 
          Drerio, 
          seqlev,
          grange = peaks,
          p.cutoff = 5e-05
        )
        
        # 3. Run one-step TFEA
        res <- TFEA(
          bamExp, 
          bamCtl, 
          bindingSites = bindingSites,
          positive = 0, 
          negative = 0
        )
        
        # Determine a TF to plot (use "Tal1::Gata1" if present, otherwise fallback to the first available TF)
        TF <- "Tal1::Gata1"
        if (!(TF %in% names(motifs))) {
          TF <- names(motifs)[1]
        }
        
        # 4. Visualize and save results
        # Volcano plot
        pdf("ES_volcanoplot.pdf", width = 8, height = 6)
        print(ESvolcanoplot(TFEAresults = res, TFnameToShow = TF))
        dev.off()
        
        # Enrichment score plot
        pdf("plotES.pdf", width = 8, height = 6)
        print(plotES(res, TF = TF, outfolder = NA))
        dev.off()
        
        # Footprint plot (wrapped in tryCatch for robustness)
        tryCatch({
          pdf("factor_footprints.pdf", width = 8, height = 6)
          sigs <- factorFootprints(
            c(bamCtl, bamExp), 
            pfm = as.matrix(motifs[[TF]]),
            bindingSites = getBindingSites(res, TF = TF),
            seqlev = seqlev, 
            genome = Drerio,
            upstream = 100, 
            downstream = 100,
            group = rep(c("WT", "KD"), c(length(bamCtl), length(bamExp)))
          )
          dev.off()
        }, error = function(e) {
          message("Warning: factorFootprints plotting skipped or failed: ", e\$message)
          if (dev.cur() > 1) dev.off()
        })
        
        # Export results table and object
        write.csv(res\$resultsTable, "TFEA_results.csv", row.names = FALSE)
        saveRDS(res, "TFEA_results.rds")

    writeLines(c(
        '"BIOC_ATACSEQTFEA_ONE_STEP_TFEA":',
        paste0('    ATACseqTFEA: ', as.character(packageVersion('ATACseqTFEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_tfea.csv versions.yml
    """
}

workflow BIOC_ATACSEQTFEA_ONE_STEP_TFEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamExp.bam, bamCtl.bam, PWMatrixList.rds, peaks.granges ] ]

    main:
    BIOC_ATACSEQTFEA_ONE_STEP_TFEA(ch_input)

    emit:
    tables   = BIOC_ATACSEQTFEA_ONE_STEP_TFEA.out.tables
    plots    = BIOC_ATACSEQTFEA_ONE_STEP_TFEA.out.plots
    objects  = BIOC_ATACSEQTFEA_ONE_STEP_TFEA.out.objects
    versions = BIOC_ATACSEQTFEA_ONE_STEP_TFEA.out.versions
}
