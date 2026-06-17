#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylPipe — methylation_profiling_and_visualization
// Profile absolute and relative DNA methylation levels across specific genomic regions of interest and visualize the profiles.
// Input: H1.db, IMR90.db, GR_chr20.Rdata, gec.IMR90.Rdata
// Container: quay.io/biocontainers/bioconductor-methylpipe:1.44.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg18, TxDb.Hsapiens.UCSC.hg18.knownGene, methylPipe
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg18, TxDb.Hsapiens.UCSC.hg18.knownGene, methylPipe
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map methylation data to genomic ranges using mapBSdata2GRanges
//  * 2. [Input & Preparation] Profile absolute and relative methylation in bins using profileDNAmetBin to create a GEcollection
//  * 3. [Core Analysis] Combine multiple GEcollection objects into a GElist
//  * 4. [Visualization & Output] Plot methylation profiles alongside gene annotations using plotMeth

nextflow.enable.dsl = 2

process BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg18", "TxDb.Hsapiens.UCSC.hg18.knownGene", "methylPipe")
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
        library(methylPipe)
        library(BSgenome.Hsapiens.UCSC.hg18)
        library(TxDb.Hsapiens.UCSC.hg18.knownGene)
        
        # ----------------------------------------------------------------------
        # 1. Load User Input Files
        # ----------------------------------------------------------------------
        
        # Load GR_chr20.Rdata (contains GR_chr20)
        gr_objs <- load("GR_chr20.Rdata")
        if (!exists("GR_chr20")) {
          GR_chr20 <- get(gr_objs[1])
        }
        
        # Load gec.IMR90.Rdata (contains gec.IMR90)
        gec_objs <- load("gec.IMR90.Rdata")
        if (!exists("gec.IMR90")) {
          gec.IMR90 <- get(gec_objs[1])
        }
        
        # Helper function to load BSdata objects robustly (handles RData or RDS)
        load_bsdata <- function(file_path) {
          env <- new.env()
          tryCatch({
            load(file_path, envir = env)
            vars <- names(env)
            if (length(vars) > 0) {
              return(get(vars[1], envir = env))
            }
          }, error = function(e) {
            return(readRDS(file_path))
          })
        }
        
        H1.db <- load_bsdata("H1.db")
        IMR90.db <- load_bsdata("IMR90.db")
        
        # ----------------------------------------------------------------------
        # 2. Map Methylation Data to Genomic Ranges
        # ----------------------------------------------------------------------
        resmC <- mapBSdata2GRanges(GenoRanges=GR_chr20, Sample=H1.db, context='CG')
        
        # ----------------------------------------------------------------------
        # 3. Profile Absolute and Relative Methylation in Bins
        # ----------------------------------------------------------------------
        gec.H1 <- profileDNAmetBin(GenoRanges=GR_chr20, Sample=H1.db, mcCLASS='mCG', nbins=3)
        
        # Extract and display bin values
        bin_mC_val <- binmC(gec.H1)
        bin_C_val <- binC(gec.H1)
        bin_rC_val <- binrC(gec.H1)
        
        # Subset the GEcollection
        gec1 <- gec.H1[start(gec.H1) < 153924]
        gec2 <- gec.H1[start(gec.H1) > 153924]
        
        # ----------------------------------------------------------------------
        # 4. Combine Multiple GEcollection Objects into a GElist
        # ----------------------------------------------------------------------
        gel <- GElist(gecIMR90=gec.IMR90, gecH1=gec.H1)
        
        # ----------------------------------------------------------------------
        # 5. Plot Methylation Profiles Alongside Gene Annotations
        # ----------------------------------------------------------------------
        txdb <- TxDb.Hsapiens.UCSC.hg18.knownGene
        
        plot_chr <- as.character(seqnames(gel[[1]]))[1]
        plot_start <- min(start(gel[[1]]))
        plot_end <- max(end(gel[[1]]))
        
        pdf("methylation_profile_plot.pdf", width=10, height=8)
        plotMeth(gel, colors=c("red","blue"), datatype=c("mC","mC"), yLim=c(.025, .025), brmeth=list(IMR90=IMR90.db, H1=H1.db),
                 mcContext="CG", transcriptDB=txdb, chr=plot_chr, start=plot_start, end=plot_end, org=Hsapiens)
        dev.off()
        
        # ----------------------------------------------------------------------
        # 6. Save Outputs
        # ----------------------------------------------------------------------
        saveRDS(resmC, "resmC.rds")
        saveRDS(gec.H1, "gec.H1.rds")
        saveRDS(gec1, "gec1.rds")
        saveRDS(gec2, "gec2.rds")
        saveRDS(gel, "gel.rds")
        
        write.csv(bin_mC_val, "bin_mC_val.csv", row.names=FALSE)
        write.csv(bin_C_val, "bin_C_val.csv", row.names=FALSE)
        write.csv(bin_rC_val, "bin_rC_val.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION":',
        paste0('    methylPipe: ', as.character(packageVersion('methylPipe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_profiling_and_visualization.csv versions.yml
    """
}

workflow BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H1.db, IMR90.db, GR_chr20.Rdata, gec.IMR90.Rdata ] ]

    main:
    BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION.out.tables
    plots    = BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION.out.plots
    objects  = BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION.out.objects
    versions = BIOC_METHYLPIPE_METHYLATION_PROFILING_AND_VISUALIZATION.out.versions
}
