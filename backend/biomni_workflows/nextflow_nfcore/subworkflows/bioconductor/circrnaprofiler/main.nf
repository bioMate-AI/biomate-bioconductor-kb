#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: circRNAprofiler — circrna_downstream_analysis
// Perform a comprehensive downstream analysis of predicted circRNAs, including merging, filtering, differential expression, structural annotation, sequence retrie
// Input: gencode.V19.annotation.gtf, experiment.txt, circRNAs_X.txt, motifs.txt, miRs.txt, transcripts.txt, traits.txt
// Container: quay.io/biocontainers/bioconductor-circrnaprofiler:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BSgenome.Hsapiens.UCSC.hg19, BiocManager, VennDiagram, circRNAprofiler, dplyr, ggplot2, ggpubr, gridExtra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize project folder structure using initCircRNAprofiler()
//  * 2. [Core Analysis] Verify folder structure using checkProjectFolder()
//  * 3. [Core Analysis] Format the GTF file using formatGTF()
//  * 4. [Input & Preparation] Import predicted circRNAs using getBackSplicedJunctions()
//  * 5. [Core Analysis] Merge commonly identified circRNAs across tools using mergeBSJunctions()
//  * 6. [Input & Preparation] Filter circRNAs based on read counts and conditions using filterCirc()
//  * 7. [Core Analysis] Identify differentially expressed circRNAs using getDeseqRes() or getEdgerRes()
//  * 8. [Core Analysis] Map coordinates between assemblies (optional) using liftBSJcoords()
//  * 9. [Core Analysis] Annotate internal structure and flanking introns using annotateBSJs()
//  * 10. [Core Analysis] Generate random background junctions using getRandomBSJunctions()
//  * 11. [Core Analysis] Retrieve target sequences (internal, BSJ, or flanking) using getCircSeqs(), getSeqsAcrossBSJs(), or getSeqsFromGRs()
//  * 12. [Core Analysis] Screen for RBP motifs using getMotifs() and mergeMotifs()
//  * 13. [Core Analysis] Screen for miRNA binding sites using getMiRsites() and rearrangeMiRres()
//  * 14. [Core Analysis] Annotate GWAS SNPs using annotateSNPsGWAS()
//  * 15. [Core Analysis] Annotate repetitive elements using annotateRepeats()

nextflow.enable.dsl = 2

process BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("circRNAprofiler", "ggplot2", "ggpubr", "gridExtra", "VennDiagram", "BSgenome", "dplyr")
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
            library(circRNAprofiler)
            library(ggplot2)
            library(ggpubr)
            library(gridExtra)
            library(VennDiagram)
            library(BSgenome)
            library(dplyr)
            
            # Store the original working directory
            orig_wd <- getwd()
            
            # Module 1 - Set up project folder
            initCircRNAprofiler(
                projectFolderName = "projectCirc",
                detectionTools = c("mapsplice", "nclscan", "circmarker")
            )
            
            # Copy user input files from the original directory to the project folder
            files_to_copy <- c("gencode.V19.annotation.gtf", "experiment.txt", "motifs.txt", "miRs.txt", "transcripts.txt", "traits.txt")
            for (f in files_to_copy) {
                src <- file.path(orig_wd, f)
                if (file.exists(src)) {
                    file.copy(src, file.path("projectCirc", f), overwrite = TRUE)
                }
            }
            
            # Copy tool-specific subfolders and their circRNAs_X.txt files
            tools <- c("mapsplice", "nclscan", "circmarker")
            for (tool in tools) {
                src_dir <- file.path(orig_wd, tool)
                if (dir.exists(src_dir)) {
                    files <- list.files(src_dir, pattern = "circRNAs_.*\\\\.txt", full.names = TRUE)
                    for (fl in files) {
                        dest_file <- file.path("projectCirc", tool, basename(fl))
                        file.copy(fl, dest_file, overwrite = TRUE)
                    }
                }
            }
            
            # Change working directory to the project folder
            setwd("projectCirc")
            
            # Verify folder structure
            check <- checkProjectFolder()
            message("Project folder check code: ", check)
            
            # Module 2 - Import predicted circRNAs
            gtf <- formatGTF("gencode.V19.annotation.gtf")
            backSplicedJunctions <- getBackSplicedJunctions(gtf)
            write.csv(backSplicedJunctions, "backSplicedJunctions.csv", row.names = FALSE)
            
            # Module 3 - Merge commonly identified circRNAs
            mergedBSJunctions <- mergeBSJunctions(backSplicedJunctions, gtf)
            write.csv(mergedBSJunctions, "mergedBSJunctions.csv", row.names = FALSE)
            
            # Module 4 - Filter circRNAs
            filteredCirc <- filterCirc(mergedBSJunctions, allSamples = FALSE, min = 5)
            write.csv(filteredCirc, "filteredCirc.csv", row.names = FALSE)
            
            # Module 5 - Find differentially expressed circRNAs
            cond_AB <- "A-B"
            cond_AC <- "A-C"
            if (file.exists("experiment.txt")) {
                exp_data <- read.table("experiment.txt", header = TRUE, stringsAsFactors = FALSE)
                if ("condition" %in% colnames(exp_data)) {
                    conds <- sort(unique(exp_data\$condition))
                    if (length(conds) >= 2) cond_AB <- paste(conds[1], conds[2], sep="-")
                    if (length(conds) >= 3) cond_AC <- paste(conds[1], conds[3], sep="-")
                }
            }
        
            deseqResBvsA <- NULL
            deseqResCvsA <- NULL
            tryCatch({
                deseqResBvsA <- getDeseqRes(
                    filteredCirc,
                    condition = cond_AB,
                    fitType = "local",
                    pAdjustMethod = "BH"
                )
                write.csv(deseqResBvsA, "deseqResBvsA.csv", row.names = FALSE)
            }, error = function(e) {
                warning("DESeq2 BvsA analysis failed: ", e\$message)
            })
            
            tryCatch({
                deseqResCvsA <- getDeseqRes(
                    filteredCirc,
                    condition = cond_AC,
                    fitType = "local",
                    pAdjustMethod = "BH"
                )
                write.csv(deseqResCvsA, "deseqResCvsA.csv", row.names = FALSE)
            }, error = function(e) {
                warning("DESeq2 CvsA analysis failed: ", e\$message)
            })
            
            edgerResBvsA <- NULL
            tryCatch({
                edgerResBvsA <- getEdgerRes(
                    filteredCirc,
                    condition = cond_AB,
                    normMethod = "TMM",
                    pAdjustMethod = "BH"
                )
                write.csv(edgerResBvsA, "edgerResBvsA.csv", row.names = FALSE)
            }, error = function(e) {
                warning("edgeR BvsA analysis failed: ", e\$message)
            })
            
            # Module 6 - Map BSJ coordinates between species and genome assemblies
            liftedBSJcoords <- NULL
            tryCatch({
                liftedBSJcoords <- liftBSJcoords(filteredCirc, map = "hg19ToMm9", annotationHubID = "AH14155")
                if (!is.null(liftedBSJcoords)) {
                    write.csv(liftedBSJcoords, "liftedBSJcoords.csv", row.names = FALSE)
                }
            }, error = function(e) {
                warning("liftBSJcoords failed: ", e\$message)
            })
            
            # Module 7 - Annotate circRNAs internal structure and flanking introns
            annotatedBSJs <- NULL
            if (nrow(filteredCirc) > 0) {
                num_to_annotate <- min(30, nrow(filteredCirc))
                annotatedBSJs <- annotateBSJs(filteredCirc[1:num_to_annotate, ], gtf, isRandom = FALSE)
                write.csv(annotatedBSJs, "annotatedBSJs.csv", row.names = FALSE)
            }
            
            # Module 8 - Generate random BSJs
            randomBSJunctions <- NULL
            annotatedRBSJs <- NULL
            if (!is.null(annotatedBSJs) && nrow(annotatedBSJs) > 0) {
                f <- sum((annotatedBSJs\$exNumUpBSE == 1 | annotatedBSJs\$exNumDownBSE == 1), na.rm = TRUE) / (nrow(annotatedBSJs) * 2)
                if (is.nan(f) || is.na(f)) f <- 0.1 # Fallback if division by zero or NA
                
                randomBSJunctions <- getRandomBSJunctions(gtf, n = nrow(annotatedBSJs), f = f, setSeed = 123)
                write.csv(randomBSJunctions, "randomBSJunctions.csv", row.names = FALSE)
                
                annotatedRBSJs <- annotateBSJs(randomBSJunctions, gtf, isRandom = TRUE)
                write.csv(annotatedRBSJs, "annotatedRBSJs.csv", row.names = FALSE)
            }
            
            # Retrieve target sequences
            # Load the genome of interest
            if (!requireNamespace("BSgenome.Hsapiens.UCSC.hg19", quietly = TRUE)) {
                BiocManager::install("BSgenome.Hsapiens.UCSC.hg19", update = FALSE, ask = FALSE)
            }
            genome <- BSgenome::getBSgenome("BSgenome.Hsapiens.UCSC.hg19")
            
            # Select target circRNA and background circRNAs
            annotatedCirc <- NULL
            annotatedBackgroundCircs <- NULL
            if (!is.null(annotatedBSJs) && nrow(annotatedBSJs) > 0) {
                if ("ALPK2:-:chr18:56247780:56246046" %in% annotatedBSJs\$id) {
                    annotatedCirc <- annotatedBSJs[annotatedBSJs\$id == "ALPK2:-:chr18:56247780:56246046", ]
                    annotatedBackgroundCircs <- annotatedBSJs[annotatedBSJs\$id != "ALPK2:-:chr18:56247780:56246046", ]
                } else {
                    annotatedCirc <- annotatedBSJs[1, ]
                    annotatedBackgroundCircs <- annotatedBSJs[-1, ]
                }
            }
            
            # Module 9 - Retrieve internal circRNA sequences
            targetsFTS_circ <- NULL
            targetsBTS_circ <- NULL
            if (!is.null(annotatedCirc) && nrow(annotatedCirc) > 0) {
                targetsFTS_circ <- getCircSeqs(annotatedCirc, gtf, genome)
                saveRDS(targetsFTS_circ, "targetsFTS_circ.rds")
            }
            if (!is.null(annotatedBackgroundCircs) && nrow(annotatedBackgroundCircs) > 0) {
                targetsBTS_circ <- getCircSeqs(annotatedBackgroundCircs, gtf, genome)
                saveRDS(targetsBTS_circ, "targetsBTS_circ.rds")
            }
            
            # Module 10 - Retrieve BSJ sequences
            targetsFTS_bsj <- NULL
            targetsBTS_bsj <- NULL
            if (!is.null(annotatedCirc) && nrow(annotatedCirc) > 0) {
                targetsFTS_bsj <- getSeqsAcrossBSJs(annotatedCirc, gtf, genome)
                saveRDS(targetsFTS_bsj, "targetsFTS_bsj.rds")
            }
            if (!is.null(annotatedBackgroundCircs) && nrow(annotatedBackgroundCircs) > 0) {
                targetsBTS_bsj <- getSeqsAcrossBSJs(annotatedBackgroundCircs, gtf, genome)
                saveRDS(targetsBTS_bsj, "targetsBTS_bsj.rds")
            }
            
            # Module 11 - Retrieve sequences flanking the BSJs
            targetsFTS_gr <- NULL
            targetsBTS_gr <- NULL
            if (!is.null(annotatedCirc) && nrow(annotatedCirc) > 0) {
                targetsFTS_gr <- getSeqsFromGRs(annotatedCirc, genome, lIntron = 200, lExon = 9, type = "ie")
                saveRDS(targetsFTS_gr, "targetsFTS_gr.rds")
            }
            if (!is.null(annotatedBackgroundCircs) && nrow(annotatedBackgroundCircs) > 0) {
                targetsBTS_gr <- getSeqsFromGRs(annotatedBackgroundCircs, genome, lIntron = 200, lExon = 9, type = "ie")
                saveRDS(targetsBTS_gr, "targetsBTS_gr.rds")
            }
            
            # Module 12 - Screen target sequences for RBP/de Novo motifs
            motifsFTS_gr <- NULL
            motifsBTS_gr <- NULL
            mergedMotifsFTS_gr <- NULL
            mergedMotifsBTS_gr <- NULL
            if (!is.null(targetsFTS_gr)) {
                tryCatch({
                    motifsFTS_gr <- getMotifs(targetsFTS_gr, width = 6, database = 'ATtRACT', species = "Hsapiens", rbp = TRUE, reverse = FALSE)
                    mergedMotifsFTS_gr <- mergeMotifs(motifsFTS_gr)
                    saveRDS(mergedMotifsFTS_gr, "mergedMotifsFTS_gr.rds")
                }, error = function(e) {
                    warning("Motif screening for foreground failed: ", e\$message)
                })
            }
            if (!is.null(targetsBTS_gr)) {
                tryCatch({
                    motifsBTS_gr <- getMotifs(targetsBTS_gr, width = 6, database = 'ATtRACT', species = "Hsapiens", rbp = TRUE, reverse = FALSE)
                    mergedMotifsBTS_gr <- mergeMotifs(motifsBTS_gr)
                    saveRDS(mergedMotifsBTS_gr, "mergedMotifsBTS_gr.rds")
                }, error = function(e) {
                    warning("Motif screening for background failed: ", e\$message)
                })
            }
            
            # Module 13 - Screen circRNA sequences for miRNA binding sites
            miRsites <- NULL
            rearragedMiRres <- NULL
            if (!is.null(targetsFTS_circ)) {
                tryCatch({
                    miRsites <- getMiRsites(
                        targetsFTS_circ,
                        miRspeciesCode = "hsa",
                        miRBaseLatestRelease = TRUE,
                        totalMatches = 6,
                        maxNonCanonicalMatches = 1
                    )
                    rearragedMiRres <- rearrageMiRres(miRsites)
                    saveRDS(rearragedMiRres, "rearragedMiRres.rds")
                }, error = function(e) {
                    warning("miRNA binding site screening failed: ", e\$message)
                })
            }
            
            # Module 14 - Annotate GWAS SNPs
            snpsGWAS <- NULL
            if (!is.null(targetsFTS_gr)) {
                tryCatch({
                    snpsGWAS <- annotateSNPsGWAS(targetsFTS_gr, assembly = "hg19", makeCurrent = TRUE)
                    saveRDS(snpsGWAS, "snpsGWAS.rds")
                }, error = function(e) {
                    warning("GWAS SNP annotation failed: ", e\$message)
                })
            }
            
            # Module 15 - Annotate repetitive elements
            repeats <- NULL
            if (!is.null(targetsFTS_gr)) {
                tryCatch({
                    repeats <- annotateRepeats(targetsFTS_gr, annotationHubID = "AH5122", complementary = TRUE)
                    saveRDS(repeats, "repeats.rds")
                }, error = function(e) {
                    warning("Repetitive elements annotation failed: ", e\$message)
                })
            }
            
            # Generate and save plots to PDF
            pdf("circRNA_analysis_plots.pdf", width = 11, height = 8.5)
            
            # Plot 1: Number of circRNAs identified by each detection tool
            tryCatch({
                p1 <- ggplot(backSplicedJunctions, aes(x = tool)) + 
                    geom_bar() + 
                    labs(title = "circRNAs Identified by Tool", x = "Detection tool", y = "No. of circRNAs") + 
                    theme_classic()
                dt <- getDetectionTools() %>% 
                    dplyr::filter(name %in% c("mapsplice", "nclscan", "circmarker")) %>% 
                    gridExtra::tableGrob(rows = NULL)
                gridExtra::grid.arrange(p1, dt, nrow = 1)
            }, error = function(e) {
                warning("Plot 1 failed: ", e\$message)
            })
            
            # Plot 2: Commonly identified circRNAs after merging
            tryCatch({
                p2 <- ggplot(mergedBSJunctions, aes(x = tool)) + 
                    geom_bar() + 
                    labs(title = "Merged circRNAs by Tool Combination", x = "Detection tool", y = "No. of circRNAs") + 
                    theme_classic()
                gridExtra::grid.arrange(p2, dt, nrow = 1)
            }, error = function(e) {
                warning("Plot 2 failed: ", e\$message)
            })
            
            # Plot 3: Filtered circRNAs
            tryCatch({
                p3 <- ggplot(filteredCirc, aes(x = tool)) + 
                    geom_bar() + 
                    labs(title = "Filtered circRNAs by Tool Combination", x = "Detection tool", y = "No. of circRNAs") + 
                    theme_classic()
                gridExtra::grid.arrange(p3, dt, nrow = 1)
            }, error = function(e) {
                warning("Plot 3 failed: ", e\$message)
            })
            
            # Plot 4: Volcano plots for differential expression
            if (!is.null(deseqResBvsA) && !is.null(deseqResCvsA)) {
                tryCatch({
                    vp1 <- volcanoPlot(
                        deseqResBvsA,
                        log2FC = 1,
                        padj = 0.05,
                        title = "DCMs Vs. Con",
                        setxLim = TRUE,
                        xlim = c(-8, 7.5),
                        setyLim = TRUE,
                        ylim = c(0, 4),
                        gene = FALSE
                    )
                    vp2 <- volcanoPlot(
                        deseqResCvsA,
                        log2FC = 1,
                        padj = 0.05,
                        title = "HCMs Vs. Con",
                        setxLim = TRUE,
                        xlim = c(-8, 7.5),
                        setyLim = TRUE,
                        ylim = c(0, 4),
                        gene = FALSE
                    )
                    print(ggarrange(vp1, vp2, ncol = 1, nrow = 2))
                }, error = function(e) {
                    warning("Volcano plots failed: ", e\$message)
                })
            }
            
            # Plot 5: Structural features comparison
            if (!is.null(annotatedBSJs) && !is.null(annotatedRBSJs)) {
                tryCatch({
                    sp1 <- plotLenIntrons(annotatedBSJs, annotatedRBSJs, title = "Length flanking introns", df1Name = "predicted", df2Name = "random", setyLim = TRUE, ylim = c(0, 7))
                    sp2 <- plotLenBSEs(annotatedBSJs, annotatedRBSJs, title = "Length back-spliced exons", df1Name = "predicted", df2Name = "random", setyLim = TRUE, ylim = c(0, 7))
                    sp3 <- plotHostGenes(annotatedBSJs, title = "# CircRNAs produced from host genes")
                    sp4 <- plotExBetweenBSEs(annotatedBSJs, title = "# Exons between back-spliced junctions")
                    sp5 <- plotExPosition(annotatedBSJs, n = 1, title = "Position back-spliced exons in the transcripts")
                    sp6 <- plotTotExons(annotatedBSJs, title = "Total number of exons in the host transcripts")
                    print(ggarrange(sp1, sp2, sp3, sp4, sp5, sp6, ncol = 2, nrow = 3))
                }, error = function(e) {
                    warning("Structural feature plots failed: ", e\$message)
                })
            }
            
            # Plot 6: Motifs plot
            if (!is.null(mergedMotifsFTS_gr) && !is.null(mergedMotifsBTS_gr)) {
                tryCatch({
                    mp <- plotMotifs(
                        mergedMotifsFTS_gr,
                        mergedMotifsBTS_gr,
                        nf1 = sum(targetsFTS_gr\$upGR\$length, na.rm = TRUE) + sum(targetsFTS_gr\$downGR\$length, na.rm = TRUE),
                        nf2 = sum(targetsBTS_gr\$upGR\$length, na.rm = TRUE) + sum(targetsBTS_gr\$downGR\$length, na.rm = TRUE),
                        log2FC = 1,
                        removeNegLog2FC = TRUE,
                        df1Name = "Foreground",
                        df2Name = "Background",
                        angle = 45
                    )
                    print(ggarrange(mp[[1]], mp[[2]], labels = c("", ""), ncol = 2, nrow = 1))
                }, error = function(e) {
                    warning("Motifs plot failed: ", e\$message)
                })
            }
            
            # Plot 7: miRNA plot
            if (!is.null(rearragedMiRres)) {
                tryCatch({
                    mirp <- plotMiR(rearragedMiRres, n = 40, color = "blue", miRid = TRUE, id = 1)
                    print(mirp)
                }, error = function(e) {
                    warning("miRNA plot failed: ", e\$message)
                })
            }
            
            dev.off()
            
            # Return to original working directory
            setwd(orig_wd)
            message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS":',
        paste0('    circRNAprofiler: ', as.character(packageVersion('circRNAprofiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_circrna_downstream_analysis.csv versions.yml
    """
}

workflow BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gencode.V19.annotation.gtf, experiment.txt, circRNAs_X.txt, motifs.txt, miRs.txt, transcripts.txt, traits.txt ] ]

    main:
    BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS.out.tables
    plots    = BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS.out.plots
    objects  = BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS.out.objects
    versions = BIOC_CIRCRNAPROFILER_CIRCRNA_DOWNSTREAM_ANALYSIS.out.versions
}
