#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DMRcate — array_dmr_analysis
// Identify and plot differentially methylated regions from Illumina Infinium array data (such as EPICv2 or EPICv1).
// Input: ALLMs, design
// Container: quay.io/biocontainers/bioconductor-dmrcate:3.6.0--r45hdfd78af_0
// R packages: biocmanager, DMRcate, ExperimentHub
// Bioconductor: 3.20 | R: 4.4
// Requires: DMRcate
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Filter out SNP-proximal and cross-hybridising probes
//  * 2. [Visualization & Output] Annotate CpGs and model differential methylation
//  * 3. [Visualization & Output] Call DMRs
//  * 4. [Visualization & Output] Extract genomic coordinates of the identified DMRs
//  * 5. [Visualization & Output] Plot specific DMRs

nextflow.enable.dsl = 2

process BIOC_DMRCATE_ARRAY_DMR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("biocmanager", "DMRcate", "ExperimentHub")
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
    library(DMRcate)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    # Read ALLMs (matrix of M-values or Beta-values)
    if (file.exists("ALLMs.rds")) {
      ALLMs <- readRDS("ALLMs.rds")
    } else if (file.exists("ALLMs.csv")) {
      ALLMs <- as.matrix(read.csv("ALLMs.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: ALLMs file (ALLMs.rds or ALLMs.csv) not found in the working directory.")
    }
    
    # Read design matrix
    if (file.exists("design.rds")) {
      design <- readRDS("design.rds")
    } else if (file.exists("design.csv")) {
      design <- as.matrix(read.csv("design.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: design file (design.rds or design.csv) not found in the working directory.")
    }
    
    # ==========================================
    # 2. EXECUTE WORKFLOW
    # ==========================================
    
    # --- Filter out SNP-proximal and cross-hybridising probes ---
    ALLMs.noSNPs <- rmSNPandCH(ALLMs, rmcrosshyb = FALSE)
    
    # --- Annotate CpGs and model differential methylation ---
    myannotation <- cpg.annotate("array", object=ALLMs.noSNPs, what = "M", 
                                 arraytype = "EPICv2", epicv2Filter = "mean", 
                                 epicv2Remap = TRUE,  analysis.type="differential", 
                                 design=design, coef=2, fdr=0.001)
    
    # --- Call DMRs ---
    dmrcoutput <- dmrcate(myannotation, lambda=1000, C=2)
    
    # --- Extract genomic coordinates of the identified DMRs ---
    results.ranges <- extractRanges(dmrcoutput, genome = "hg38")
    
    # ==========================================
    # 3. WRITE OUTPUTS & PLOT
    # ==========================================
    
    # Save the genomic ranges of identified DMRs
    saveRDS(results.ranges, "results_ranges.rds")
    write.csv(as.data.frame(results.ranges), "results_ranges.csv", row.names = FALSE)
    
    # Dynamically define colors for plotting based on the design matrix
    if (ncol(design) >= 2) {
      group_vals <- design[, 2]
      unique_vals <- unique(group_vals)
      color_palette <- c("forestgreen", "orange", "blue", "purple", "red", "magenta", "cyan", "brown")
      val_to_col <- setNames(color_palette[1:min(length(unique_vals), length(color_palette))], unique_vals)
      cols <- val_to_col[as.character(group_vals)]
      names(cols) <- rownames(design)
    } else {
      cols <- rep("forestgreen", ncol(ALLMs.noSNPs))
      names(cols) <- colnames(ALLMs.noSNPs)
    }
    
    # --- Plot specific DMRs ---
    pdf("dmr_plot.pdf", width = 10, height = 8)
    tryCatch({
      DMR.plot(ranges=results.ranges, dmr=3, CpGs=myannotation, 
               what = "Beta", arraytype = "EPICv2", phen.col=cols, genome = "hg38")
    }, error = function(e) {
      warning("DMR.plot failed for dmr=3 (possibly fewer than 3 DMRs found). Attempting to plot dmr=1...")
      if (length(results.ranges) >= 1) {
        DMR.plot(ranges=results.ranges, dmr=1, CpGs=myannotation, 
                 what = "Beta", arraytype = "EPICv2", phen.col=cols, genome = "hg38")
      } else {
        message("No DMRs found to plot.")
      }
    })
    dev.off()

    writeLines(c(
        '"BIOC_DMRCATE_ARRAY_DMR_ANALYSIS":',
        paste0('    DMRcate: ', as.character(packageVersion('DMRcate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_array_dmr_analysis.csv versions.yml
    """
}

workflow BIOC_DMRCATE_ARRAY_DMR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALLMs, design ] ]

    main:
    BIOC_DMRCATE_ARRAY_DMR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DMRCATE_ARRAY_DMR_ANALYSIS.out.tables
    plots    = BIOC_DMRCATE_ARRAY_DMR_ANALYSIS.out.plots
    objects  = BIOC_DMRCATE_ARRAY_DMR_ANALYSIS.out.objects
    versions = BIOC_DMRCATE_ARRAY_DMR_ANALYSIS.out.versions
}
