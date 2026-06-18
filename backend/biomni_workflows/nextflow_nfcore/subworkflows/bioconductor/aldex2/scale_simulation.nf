#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ALDEx2 — scale_simulation
// Incorporate scale uncertainty or scale differences to correct for compositional asymmetry and control false positives.
// Input: selex.sub, conds
// Container: quay.io/biocontainers/bioconductor-aldex2:1.42.0--r45hdfd78af_0
// R packages: ALDEx2
// Bioconductor: 3.20 | R: 4.4
// Requires: ALDEx2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create scale matrix using `aldex.makeScaleMatrix`
//  * 2. [Core Analysis] Generate CLR instances with scale matrix in `aldex.clr`
//  * 3. [Core Analysis] Calculate effect sizes and t-tests using `aldex.effect` and `aldex.ttest`

nextflow.enable.dsl = 2

process BIOC_ALDEX2_SCALE_SIMULATION {
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
    .bm_deps <- c("ALDEx2")
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
    
    # Load required library
    library(ALDEx2)
    
    # Set seed for reproducibility
    set.seed(11)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Read selex.sub (count matrix of features by samples)
    if (file.exists("selex.sub.rds")) {
      selex.sub <- readRDS("selex.sub.rds")
    } else if (file.exists("selex.sub.csv")) {
      selex.sub <- read.csv("selex.sub.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("selex.sub.tsv")) {
      selex.sub <- read.table("selex.sub.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    } else if (file.exists("selex.sub")) {
      selex.sub <- tryCatch({
        read.csv("selex.sub", row.names = 1, check.names = FALSE)
      }, error = function(e) {
        read.table("selex.sub", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
      })
    } else {
      stop("Error: 'selex.sub' file not found in the working directory.")
    }
    
    # Read conds (vector of group conditions)
    if (file.exists("conds.rds")) {
      conds <- readRDS("conds.rds")
    } else if (file.exists("conds.csv")) {
      conds_df <- read.csv("conds.csv", header = FALSE, stringsAsFactors = FALSE)
      conds <- as.vector(t(conds_df))
    } else if (file.exists("conds.txt")) {
      conds <- readLines("conds.txt")
      if (length(conds) == 1 && grepl(",", conds)) {
        conds <- trimws(strsplit(conds, ",")[[1]])
      }
    } else if (file.exists("conds")) {
      conds <- readLines("conds")
      if (length(conds) == 1 && grepl(",", conds)) {
        conds <- trimws(strsplit(conds, ",")[[1]])
      }
    } else {
      stop("Error: 'conds' file not found in the working directory.")
    }
    
    # Ensure conds is a character vector and matches the number of columns in selex.sub
    conds <- as.character(conds)
    if (length(conds) != ncol(selex.sub)) {
      stop(paste("Error: Length of 'conds' (", length(conds), 
                 ") does not match the number of columns in 'selex.sub' (", ncol(selex.sub), ").", sep=""))
    }
    
    # Convert selex.sub to matrix if it is a data frame
    selex.sub <- as.matrix(selex.sub)
    
    # ==========================================
    # 2. RUN ALDEx2 WORKFLOW (scale_simulation)
    # ==========================================
    
    # Unscaled analysis
    x.u <- aldex.clr(selex.sub, conds, mc.samples=16, 
        gamma=1e-3, verbose=FALSE)
    x.u.e <- aldex.effect(x.u, CI=T)
    
    # Scaled analysis
    # Dynamically construct mu.mod to represent an 8-fold difference in scale between groups
    unique_conds <- unique(conds)
    if (length(unique_conds) < 2) {
      mu.mod <- rep(1, length(conds))
    } else {
      mu.mod <- ifelse(conds == unique_conds[1], 1, 8)
    }
    
    scale.model <- aldex.makeScaleMatrix(gamma=0.5, mu=mu.mod, conditions=conds, mc.samples=16, log=FALSE)
    
    x.ss <- aldex.clr(selex.sub, conds, mc.samples=16, 
        gamma=scale.model, verbose=FALSE)
    x.ss.e <- aldex.effect(x.ss, CI=T)
    x.ss.tt <- aldex.ttest(x.ss)
    x.ss.all <- cbind(x.ss.e, x.ss.tt)
    
    # Determine feature to plot (fallback to first feature if 'S:D:S:D' is not present)
    feature_to_plot <- 'S:D:S:D'
    if (!(feature_to_plot %in% rownames(selex.sub))) {
      feature_to_plot <- rownames(selex.sub)[1]
    }
    
    # ==========================================
    # 3. WRITE OUTPUTS
    # ==========================================
    
    # Save CSV tables
    write.csv(x.u.e, "unscaled_effect.csv", row.names = TRUE)
    write.csv(x.ss.e, "scaled_effect.csv", row.names = TRUE)
    write.csv(x.ss.tt, "scaled_ttest.csv", row.names = TRUE)
    write.csv(x.ss.all, "scaled_all_results.csv", row.names = TRUE)
    
    # Save RDS objects
    saveRDS(x.u, "x_u.rds")
    saveRDS(x.ss, "x_ss.rds")
    
    # Save PDF plots
    pdf("aldex_plot_feature_unscaled.pdf")
    aldex.plotFeature(x.u, feature_to_plot, pooledOnly=T)
    dev.off()
    
    pdf("aldex_plot_feature_scaled.pdf")
    aldex.plotFeature(x.ss, feature_to_plot, pooledOnly=T)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to the working directory.")

    writeLines(c(
        '"BIOC_ALDEX2_SCALE_SIMULATION":',
        paste0('    ALDEx2: ', as.character(packageVersion('ALDEx2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scale_simulation.csv versions.yml
    """
}

workflow BIOC_ALDEX2_SCALE_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ selex.sub, conds ] ]

    main:
    BIOC_ALDEX2_SCALE_SIMULATION(ch_input)

    emit:
    tables   = BIOC_ALDEX2_SCALE_SIMULATION.out.tables
    plots    = BIOC_ALDEX2_SCALE_SIMULATION.out.plots
    objects  = BIOC_ALDEX2_SCALE_SIMULATION.out.objects
    versions = BIOC_ALDEX2_SCALE_SIMULATION.out.versions
}
