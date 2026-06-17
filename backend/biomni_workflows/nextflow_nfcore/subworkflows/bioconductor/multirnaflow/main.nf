#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MultiRNAflow — temporal_multicondition_rnaseq_flow
// Perform preprocessing, normalization, exploratory unsupervised analysis (PCA, HCPC, Mfuzz), supervised differential expression analysis, and downstream function
// Input: raw_counts.csv
// Container: quay.io/biocontainers/bioconductor-multirnaflow:1.8.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiRNAflow, SummarizedExperiment
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Preprocessing and SummarizedExperiment creation using DATAprepSE()
//  * 2. [Core Analysis] Normalization of raw counts using DATAnormalization()
//  * 3. [Core Analysis] Unsupervised exploratory analysis using PCAanalysis(), HCPCanalysis(), and temporal soft clustering with MFUZZanalysis()
//  * 4. [Core Analysis] Gene expression profiling across conditions and time using DATAplotExpressionGenes()
//  * 5. [Core Analysis] Supervised differential expression analysis using DEanalysisGlobal()
//  * 6. [Visualization & Output] Visualization of DE results using DEplotVolcanoMA() and DEplotHeatmaps()
//  * 7. [Visualization & Output] Functional enrichment analysis using GSEAQuickAnalysis() and export of gene lists using GSEApreprocessing()

nextflow.enable.dsl = 2

process BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW {
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
    .bm_deps <- c("MultiRNAflow", "SummarizedExperiment")
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
        library(MultiRNAflow)
        library(SummarizedExperiment)
        
        # Create results directory
        dir.create("results", showWarnings = FALSE, recursive = TRUE)
        
        # Read user input raw counts file
        # Column names must be formatted with underscore-separated metadata like Condition_Time_Replicate
        raw_counts <- read.csv("raw_counts.csv", check.names = FALSE)
        
        # 1. Preprocessing and SummarizedExperiment creation
        resDATAprepSE <- DATAprepSE(RawCounts=raw_counts,
                                    Column.gene=1,
                                    Group.position=1,
                                    Time.position=2,
                                    Individual.position=3)
        
        # 2. Normalization of raw counts
        resNorm <- DATAnormalization(SEres=resDATAprepSE,
                                     Normalization="vst",
                                     Blind.rlog.vst=FALSE,
                                     Plot.Boxplot=FALSE,
                                     Colored.By.Factors=TRUE,
                                     Color.Group=NULL,
                                     path.result="results")
        
        # 3. Unsupervised exploratory analysis
        resPCA <- PCAanalysis(SEresNorm=resNorm,
                              DATAnorm=TRUE,
                              gene.deletion=NULL,
                              sample.deletion=NULL,
                              Plot.PCA=FALSE,
                              Mean.Accross.Time=FALSE,
                              Color.Group=NULL,
                              Cex.label=0.6,
                              Cex.point=0.7, epsilon=0.2,
                              Phi=25,Theta=140,
                              motion3D=FALSE,
                              path.result="results")
        
        resHCPC <- HCPCanalysis(SEresNorm=resPCA,
                                DATAnorm=TRUE,
                                gene.deletion=NULL,
                                sample.deletion=NULL,
                                Plot.HCPC=FALSE,
                                Phi=25,Theta=140,
                                Cex.point=0.6,
                                epsilon=0.2,
                                Cex.label=0.6,
                                motion3D=FALSE,
                                path.result="results")
        
        resMFUZZ <- MFUZZanalysis(SEresNorm=resHCPC,
                                  DATAnorm=TRUE,
                                  DataNumberCluster=NULL,
                                  Method="hcpc",
                                  Membership=0.5,
                                  Min.std=0.1,
                                  Plot.Mfuzz=FALSE,
                                  path.result="results")
        
        # 4. Gene expression profiling across conditions and time
        # Ensure the selected gene index is within bounds of the dataset
        gene_index <- if(nrow(raw_counts) >= 17) 17 else nrow(raw_counts)
        
        resEXPR <- DATAplotExpressionGenes(SEresNorm=resMFUZZ,
                                           DATAnorm=TRUE,
                                           Vector.row.gene=c(gene_index),
                                           Color.Group=NULL,
                                           Plot.Expression=FALSE,
                                           path.result="results")
        
        # 5. Supervised differential expression analysis
        resDE <- DEanalysisGlobal(SEres=resEXPR,
                                  pval.min=0.05,
                                  log.FC.min=1,
                                  Plot.DE.graph=FALSE,
                                  path.result="results")
        
        # 6. Visualization of DE results
        resMAvolcano <- DEplotVolcanoMA(SEresDE=resDE,
                                        NbGene.plotted=2,
                                        SizeLabel=3,
                                        Display.plots=FALSE,
                                        Save.plots=FALSE)
        
        # Dynamically determine ColumnsCriteria to avoid out-of-bounds errors
        cols_criteria <- if (ncol(SummarizedExperiment::rowData(resDE)) >= 2) 2 else 1
        
        resHEAT <- DEplotHeatmaps(SEresDE=resMAvolcano,
                                  ColumnsCriteria=cols_criteria,
                                  Set.Operation="union",
                                  NbGene.analysis=20,
                                  SizeLabelRows=5,
                                  SizeLabelCols=5,
                                  Display.plots=FALSE,
                                  Save.plots=TRUE)
        
        # 7. Downstream functional enrichment and gene list export
        resRgprofiler2 <- GSEAQuickAnalysis(Internet.Connection=FALSE,
                                            SEresDE=resHEAT,
                                            ColumnsCriteria=cols_criteria,
                                            ColumnsLog2ordered=NULL,
                                            Set.Operation="union",
                                            Organism="mmusculus",
                                            MaxNumberGO=20,
                                            Background=FALSE,
                                            Display.plots=FALSE,
                                            Save.plots=TRUE)
        
        resGSEApreprocess <- GSEApreprocessing(SEresDE=resDE,
                                               ColumnsCriteria=cols_criteria,
                                               Set.Operation="union",
                                               Rnk.files=FALSE,
                                               Save.files=FALSE)
        
        # Save final R objects to disk
        saveRDS(resNorm, "results/resNorm.rds")
        saveRDS(resPCA, "results/resPCA.rds")
        saveRDS(resHCPC, "results/resHCPC.rds")
        saveRDS(resMFUZZ, "results/resMFUZZ.rds")
        saveRDS(resDE, "results/resDE.rds")
        saveRDS(resHEAT, "results/resHEAT.rds")
        saveRDS(resRgprofiler2, "results/resRgprofiler2.rds")
        saveRDS(resGSEApreprocess, "results/resGSEApreprocess.rds")

    writeLines(c(
        '"BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW":',
        paste0('    MultiRNAflow: ', as.character(packageVersion('MultiRNAflow')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_temporal_multicondition_rnaseq_flow.csv versions.yml
    """
}

workflow BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.csv ] ]

    main:
    BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW(ch_input)

    emit:
    tables   = BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW.out.tables
    plots    = BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW.out.plots
    objects  = BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW.out.objects
    versions = BIOC_MULTIRNAFLOW_TEMPORAL_MULTICONDITION_RNASEQ_FLOW.out.versions
}
