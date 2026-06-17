#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cydar — differential_abundance_analysis
// Identify differentially abundant cell subpopulations between conditions in mass cytometry data by counting cells in hyperspheres and controlling the spatial FDR
// Input: FCS files, ncdfFlowSet
// Container: quay.io/biocontainers/bioconductor-cydar:1.34.0--r45ha27e39d_0
// R packages: BiocParallel, cydar, edgeR, flowCore, knitr, ncdfFlow
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, cydar, edgeR, flowCore, ncdfFlow
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Pool cells across samples using poolCells
//  * 2. [Core Analysis] Estimate transformation parameters using estimateLogicle and apply them
//  * 3. [Core Analysis] Gate out uninteresting cells using outlierGate and subset the data
//  * 4. [Input & Preparation] Prepare cell data for counting using prepareCellData
//  * 5. [Core Analysis] Count cells into hyperspheres using countCells
//  * 6. [Core Analysis] Filter low-abundance hyperspheres and perform differential abundance testing using edgeR (QL framework)
//  * 7. [Core Analysis] Control the spatial FDR using spatialFDR
//  * 8. [Visualization & Output] Visualize results using plotSphereLogFC, intensityRanges, and plotSphereIntensity
//  * 9. [Core Analysis] Identify non-redundant hyperspheres using findFirstSphere and interpret them interactively using interpretSpheres

nextflow.enable.dsl = 2

process BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "cydar", "edgeR", "flowCore", "knitr", "ncdfFlow", "SummarizedExperiment")
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
            
               
            library(SummarizedExperiment)
         library(cydar)
            library(BiocParallel)
            register(SerialParam())
            set.seed(100)
            
            library(ncdfFlow)
            library(flowCore)
            
            # ==========================================
            # 1. LOAD USER INPUT FILES
            # ==========================================
            
            # Check for pre-loaded ncdfFlowSet RDS first
            ncdf_files <- list.files(pattern = "\\\\.(rds|RData|Rdata)\$", ignore.case = TRUE, full.names = TRUE)
            collected.exprs <- NULL
            for (f in ncdf_files) {
                obj <- tryCatch(readRDS(f), error = function(e) NULL)
                if (inherits(obj, "ncdfFlowSet")) {
                    collected.exprs <- obj
                    break
                }
            }
            
            # If not found, read FCS files from the working directory
            if (is.null(collected.exprs)) {
                fcs_files <- list.files(pattern = "\\\\.fcs\$", ignore.case = TRUE, full.names = TRUE)
                if (length(fcs_files) == 0) {
                    stop("No FCS files or pre-loaded ncdfFlowSet RDS found in the working directory.")
                }
                collected.exprs <- read.ncdfFlowSet(fcs_files)
            }
            
            # Define conditions based on metadata or default to two groups (A and B)
            if (file.exists("metadata.csv")) {
                metadata <- read.csv("metadata.csv")
                conditions <- metadata\$condition
            } else {
                conditions <- rep(c("A", "B"), length.out = length(collected.exprs))
            }
            
            # ==========================================
            # 2. PRE-PROCESSING OF INTENSITIES
            # ==========================================
            
            pool.ff <- poolCells(collected.exprs)
            
            trans <- estimateLogicle(pool.ff, colnames(pool.ff))
            
            proc.ff <- transform(pool.ff, trans)
            
            # Gating out uninteresting cells (e.g., using the last marker as a QC marker)
            qc_marker <- colnames(proc.ff)[length(colnames(proc.ff))]
            gate.qc <- outlierGate(proc.ff, qc_marker, type="upper")
            
            processed.exprs <- transform(collected.exprs, trans)
            processed.exprs <- Subset(processed.exprs, gate.qc)
            
            # Discard the marker used for gating
            processed.exprs <- processed.exprs[, 1:(length(colnames(proc.ff)) - 1)]
            
            # ==========================================
            # 3. COUNTING CELLS INTO HYPOSPHERES
            # ==========================================
            
            cd <- prepareCellData(processed.exprs)
            
            cd <- countCells(cd, tol=0.5)
            
            head(assay(cd))
            
            head(intensities(cd))
            
            # ==========================================
            # 4. DIFFERENTIAL ABUNDANCE TESTING
            # ==========================================
            
            library(edgeR)
            y <- DGEList(assay(cd), lib.size=cd\$totals)
            
            keep <- aveLogCPM(y) >= aveLogCPM(5, mean(cd\$totals))
            cd <- cd[keep,]
            y <- y[keep,]
            
            design <- model.matrix(~factor(conditions))
            y <- estimateDisp(y, design)
            fit <- glmQLFit(y, design, robust=TRUE)
            res <- glmQLFTest(fit, coef=2)
            
            # ==========================================
            # 5. CONTROLLING THE SPATIAL FDR
            # ==========================================
            
            qvals <- spatialFDR(intensities(cd), res\$table\$PValue)
            
            is.sig <- qvals <= 0.05
            summary(is.sig)
            
            # ==========================================
            # 6. VISUALIZATION AND INTERPRETATION
            # ==========================================
            
            if (sum(is.sig) > 1) {
                sig.coords <- intensities(cd)[is.sig,]
                sig.res <- res\$table[is.sig,]
                coords <- prcomp(sig.coords)
            
                pdf("sphere_plots.pdf", width=10, height=12)
                plotSphereLogFC(coords\$x[,1], coords\$x[,2], sig.res\$logFC)
            
                par(mfrow=c(6,5), mar=c(2.1, 1.1, 3.1, 1.1))
                limits <- intensityRanges(cd, p=0.05)
                all.markers <- markernames(cd)
                for (i in order(all.markers)) { 
                    plotSphereIntensity(coords\$x[,1], coords\$x[,2], sig.coords[,i],
                        irange=limits[,i], main=all.markers[i])
                }
                dev.off()
            } else {
                message("Skipping sphere plots: fewer than 2 significant hyperspheres found.")
            }
            
            nonred <- findFirstSphere(intensities(cd), res\$table\$PValue)
            summary(nonred)
            
            all.coords <- prcomp(intensities(cd))
            app <- interpretSpheres(cd, select=nonred, metrics=res\$table, run=FALSE,
                                    red.coords=all.coords\$x[,1:2], red.highlight=is.sig)
            
            # ==========================================
            # 7. WRITE OUTPUTS
            # ==========================================
            
            write.csv(res\$table, "differential_abundance_results.csv", row.names=FALSE)
            write.csv(data.frame(Hypersphere=seq_along(qvals), SpatialFDR=qvals, IsSignificant=is.sig), "spatial_fdr_results.csv", row.names=FALSE)
            saveRDS(cd, "cydar_processed_data.rds")
            
            sessionInfo()

    writeLines(c(
        '"BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS":',
        paste0('    cydar: ', as.character(packageVersion('cydar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FCS files, ncdfFlowSet ] ]

    main:
    BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_CYDAR_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
