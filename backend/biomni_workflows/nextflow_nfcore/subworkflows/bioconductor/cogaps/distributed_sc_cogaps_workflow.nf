#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CoGAPS — distributed_sc_cogaps_workflow
// Run distributed CoGAPS on large single-cell transcriptomics data, identify pattern markers, perform gene set overrepresentation analysis, and run MANOVA on meta
// Input: pdac_epi_counts, interestedVariables
// Container: quay.io/biocontainers/bioconductor-cogaps:3.30.0--r45ha27e39d_0
// R packages: CoGAPS
// Bioconductor: 3.20 | R: 4.4
// Requires: CoGAPS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize parameters with sparse optimization and distributed settings using CogapsParams()
//  * 2. [Core Analysis] Set distributed parameters using setDistributedParams()
//  * 3. [Core Analysis] Run factorization using CoGAPS()
//  * 4. [Visualization & Output] Save results using saveRDS() or toCSV()
//  * 5. [Core Analysis] Identify pattern markers using patternMarkers()
//  * 6. [Core Analysis] Perform gene set overrepresentation analysis using getPatternGeneSet()
//  * 7. [Visualization & Output] Plot gene set enrichment results using plotPatternGeneSet()
//  * 8. [Core Analysis] Run MANOVA on metadata variables using MANOVA()

nextflow.enable.dsl = 2

process BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW {
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
    .bm_deps <- c("CoGAPS")
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
    library(CoGAPS)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input Files from the Working Directory
    # -----------------------------------------------------------------------------
    
    # Read pdac_epi_counts (matrix of raw single-cell counts)
    if (file.exists("pdac_epi_counts.rds")) {
      pdac_epi_counts <- readRDS("pdac_epi_counts.rds")
    } else if (file.exists("pdac_epi_counts.csv")) {
      pdac_epi_counts <- as.matrix(read.csv("pdac_epi_counts.csv", row.names = 1))
    } else {
      stop("Error: Required input file 'pdac_epi_counts' (RDS or CSV) not found in the working directory.")
    }
    
    # Read interestedVariables (matrix/dataframe of metadata variables of interest)
    if (file.exists("interestedVariables.rds")) {
      interestedVariables <- readRDS("interestedVariables.rds")
    } else if (file.exists("interestedVariables.csv")) {
      interestedVariables <- as.matrix(read.csv("interestedVariables.csv", row.names = 1))
    } else {
      stop("Error: Required input file 'interestedVariables' (RDS or CSV) not found in the working directory.")
    }
    
    # Ensure output directory exists
    dir.create("../data", showWarnings = FALSE, recursive = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Initialize Parameters and Run CoGAPS
    # -----------------------------------------------------------------------------
    
    # Initialize parameters with sparse optimization and distributed settings
    pdac_params <- CogapsParams(nIterations=50000, # 50000 iterations
                   	seed=42, # for consistency across stochastic runs
                   	nPatterns=8, # each thread will learn 8 patterns
                    sparseOptimization=TRUE, # optimize for sparse data
                    distributed="genome-wide") # parallelize across sets
    
    # Set distributed parameters
    pdac_params <- setDistributedParams(pdac_params, nSets=7)
    
    # Run factorization
    pdac_epi_result <- CoGAPS(pdac_epi_counts, pdac_params)
    
    # Save results
    saveRDS(pdac_epi_result, "../data/pdac_epi_cogaps_result.Rds")
    toCSV(pdac_epi_result, "../data")
    
    # Assign result to cogapsresult for downstream vignette compatibility
    cogapsresult <- pdac_epi_result
    
    # -----------------------------------------------------------------------------
    # Stage 3: Downstream Analysis (Pattern Markers, GSEA, MANOVA)
    # -----------------------------------------------------------------------------
    
    # Identify pattern markers
    pm <- patternMarkers(cogapsresult)
    saveRDS(pm, "pattern_markers.rds")
    
    # Define hallmark gene sets
    hallmark_ls <- list(
      "HALLMARK_ALLOGRAFT_REJECTION" = c(
        "AARS1","ABCE1","ABI1","ACHE","ACVR2A","AKT1","APBB1","B2M","BCAT1","BCL10","BCL3","BRCA1","C2","CAPG","CARTPT","CCL11","CCL13","CCL19","CCL2","CCL22","CCL4","CCL5","CCL7","CCND2","CCND3","CCR1","CCR2","CCR5","CD1D","CD2","CD247","CD28","CD3D","CD3E","CD3G","CD4","CD40","CD40LG","CD47","CD7","CD74","CD79A","CD80","CD86","CD8A","CD8B","CD96","CDKN2A","CFP","CRTAM","CSF1","CSK","CTSS","CXCL13","CXCL9","CXCR3","DARS1","DEGS1","DYRK3","EGFR","EIF3A","EIF3D","EIF3J","EIF4G3","EIF5A","ELANE","ELF4","EREG","ETS1","F2","F2R","FAS","FASLG","FCGR2B","FGR","FLNA","FYB1","GALNT1","GBP2","GCNT1","GLMN","GPR65","GZMA","GZMB","HCLS1","HDAC9","HIF1A","HLA-A","HLA-DMA","HLA-DMB","HLA-DOA","HLA-DOB","HLA-DQA1","HLA-DRA","HLA-E","HLA-G","ICAM1","ICOSLG","IFNAR2","IFNG","IFNGR1","IFNGR2","IGSF6","IKBKB","IL10","IL11","IL12A","IL12B","IL12RB1","IL13","IL15","IL16","IL18","IL18RAP","IL1B","IL2","IL27RA","IL2RA","IL2RB","IL2RG","IL4","IL4R","IL6","IL7","IL9","INHBA","INHBB","IRF4","IRF7","IRF8","ITGAL","ITGB2","ITK","JAK2","KLRD1","KRT1","LCK","LCP2","LIF","LTB","LY75","LY86","LYN","MAP3K7","MAP4K1","MBL2","MMP9","MRPL3","MTIF2","NCF4","NCK1","NCR1","NLRP3","NME1","NOS2","NPM1","PF4","PRF1","PRKCB","PRKCG","PSMB10","PTPN6","PTPRC","RARS1","RIPK2","RPL39","RPL3L","RPL9","RPS19","RPS3A","RPS9","SIT1","SOCS1","SOCS5","SPI1","SRGN","ST8SIA4","STAB1","STAT1","STAT4","TAP1","TAP2","TAPBP","TGFB1","TGFB2","THY1","TIMP1","TLR1","TLR2","TLR3","TLR6","TNF","TPD52","TRAF2","TRAT1","UBE2D1","UBE2N","WARS1","WAS","ZAP70"
      ),
      "HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION" = c(
        "ABI3BP","ACTA2","ADAM12","ANPEP","APLP1","AREG","BASP1","BDNF","BGN","BMP1","CADM1","CALD1","CALU","CAP2","CAPG","CD44","CD59","CDH11","CDH2","CDH6","COL11A1","COL12A1","COL16A1","COL1A1","COL1A2","COL3A1","COL4A1","COL4A2","COL5A1","COL5A2","COL5A3","COL6A2","COL6A3","COL7A1","COL8A2","COMP","COPA","CRLF1","CCN2","CTHRC1","CXCL1","CXCL12","CXCL6","CCN1","DAB2","DCN","DKK1","DPYSL3","DST","ECM1","ECM2","EDIL3","EFEMP2","ELN","EMP3","ENO2","FAP","FAS","FBLN1","FBLN2","FBLN5","FBN1","FBN2","FERMT2","FGF2","FLNA","FMOD","FN1","FOXC2","FSTL1","FSTL3","FUCA1","FZD8","GADD45A","GADD45B","GAS1","GEM","GJA1","GLIPR1","COLGALT1","GPC1","GPX7","GREM1","HTRA1","ID2","IGFBP2","IGFBP3","IGFBP4","IL15","IL32","IL6","CXCL8","INHBA","ITGA2","ITGA5","ITGAV","ITGB1","ITGB3","ITGB5","JUN","LAMA1","LAMA2","LAMA3","LAMC1","LAMC2","P3H1","LGALS1","LOX","LOXL1","LOXL2","LRP1","LRRC15","LUM","MAGEE1","MATN2","MATN3","MCM7","MEST","MFAP5","MGP","MMP1","MMP14","MMP2","MMP3","MSX1","MXRA5","MYL9","MYLK","NID2","NNMT","NOTCH2","NT5E","NTM","OXTR","PCOLCE","PCOLCE2","PDGFRB","PDLIM4","PFN2","PLAUR","PLOD1","PLOD2","PLOD3","PMEPA1","PMP22","POSTN","PPIB","PRRX1","PRSS2","PTHLH","PTX3","PVR","QSOX1","RGS4","RHOB","SAT1","SCG2","SDC1","SDC4","SERPINE1","SERPINE2","SERPINH1","SFRP1","SFRP4","SGCB","SGCD","SGCG","SLC6A8","SLIT2","SLIT3","SNAI2","SNTB1","SPARC","SPOCK1","SPP1","TAGLN","TFPI2","TGFB1","TGFBI","TGFBR3","TGM2","THBS1","THBS2","THY1","TIMP1","TIMP3","TNC","TNFAIP3","TNFRSF11B","TNFRSF12A","TPM1","TPM2","TPM4","VCAM1","VCAN","VEGFA","VEGFC","VIM","WIPF1","WNT5A"
      )
    )
    
    # Perform gene set overrepresentation analysis
    hallmarks_ora <- getPatternGeneSet(cogapsresult,
                                       gene.sets = hallmark_ls,
                                       method = "overrepresentation")
    saveRDS(hallmarks_ora, "hallmarks_ora.rds")
    
    # Plot gene set enrichment results and save to PDF
    pdf("pl_pattern7.pdf", width = 8, height = 6)
    pl_pattern7 <- plotPatternGeneSet(
      patterngeneset = hallmarks_ora, whichpattern = 7, padj_threshold = 0.05
    )
    if (!is.null(pl_pattern7)) {
      print(pl_pattern7)
    }
    dev.off()
    
    # Run MANOVA on metadata variables
    manova_results <- MANOVA(interestedVariables, cogapsresult)
    saveRDS(manova_results, "manova_results.rds")
    
    # Print MANOVA results to standard output
    print(manova_results)

    writeLines(c(
        '"BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW":',
        paste0('    CoGAPS: ', as.character(packageVersion('CoGAPS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_distributed_sc_cogaps_workflow.csv versions.yml
    """
}

workflow BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pdac_epi_counts, interestedVariables ] ]

    main:
    BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW.out.tables
    plots    = BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW.out.plots
    objects  = BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW.out.objects
    versions = BIOC_COGAPS_DISTRIBUTED_SC_COGAPS_WORKFLOW.out.versions
}
