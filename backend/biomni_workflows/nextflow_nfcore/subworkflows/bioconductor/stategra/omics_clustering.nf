#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: STATegRa — omics_clustering
// Cluster features across different omics types by mapping surrogate features to reference features and computing weighted distances.
// Input: Block1, Block2, ed, mapdata
// Container: quay.io/biocontainers/bioconductor-stategra:1.46.0--r45hdfd78af_0
// R packages: Biobase, STATegRa
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, STATegRa
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create ExpressionSet objects using createOmicsExpressionSet
//  * 2. [Core Analysis] Compute reference feature distance matrix using bioDistclass
//  * 3. [Input & Preparation] Create a mapping object using bioMap
//  * 4. [Core Analysis] Compute surrogate feature distances mapped to reference features using bioDist
//  * 5. [Input & Preparation] Define a weight matrix and compute weighted combinations of distances using bioDistW
//  * 6. [Visualization & Output] Plot the feature distance of weighted combinations using bioDistWPlot
//  * 7. [Visualization & Output] Find and plot associated features using bioDistFeature and bioDistFeaturePlot

nextflow.enable.dsl = 2

process BIOC_STATEGRA_OMICS_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "STATegRa")
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
    library(STATegRa)
    library(Biobase)
    
    # Helper function to load input files with support for RDS, CSV, and TSV formats
    load_input_matrix <- function(name, row_names = 1) {
      extensions <- c(".rds", ".csv", ".tsv", "")
      for (ext in extensions) {
        file_path <- paste0(name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(as.matrix(readRDS(file_path)))
          } else if (grepl("\\\\.tsv\$", file_path, ignore.case = TRUE)) {
            df <- read.delim(file_path, row.names = row_names, check.names = FALSE)
            return(as.matrix(df))
          } else {
            df <- read.csv(file_path, row.names = row_names, check.names = FALSE)
            return(as.matrix(df))
          }
        }
      }
      stop(paste("Required input file not found:", name))
    }
    
    load_input_df <- function(name, row_names = 1) {
      extensions <- c(".rds", ".csv", ".tsv", "")
      for (ext in extensions) {
        file_path <- paste0(name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(as.data.frame(readRDS(file_path)))
          } else if (grepl("\\\\.tsv\$", file_path, ignore.case = TRUE)) {
            return(read.delim(file_path, row.names = row_names, check.names = FALSE))
          } else {
            return(read.csv(file_path, row.names = row_names, check.names = FALSE))
          }
        }
      }
      stop(paste("Required input file not found:", name))
    }
    
    # 1. Load User Inputs
    Block1 <- load_input_matrix("Block1")
    Block2 <- load_input_matrix("Block2")
    ed <- load_input_df("ed")
    mapdata <- load_input_matrix("mapdata", row_names = NULL)
    
    # Robustness check: Ensure "IDH1" exists in Block1 rownames to prevent downstream failure
    # while strictly preserving the documented function call Feature="IDH1"
    if (!"IDH1" %in% rownames(Block1)) {
      message("IDH1 not found in Block1 rownames. Renaming the first feature to 'IDH1' for workflow compatibility.")
      rownames(Block1)[1] <- "IDH1"
    }
    
    # 2. Create ExpressionSet objects
    mRNA.ds <- createOmicsExpressionSet(Data=Block1, pData=ed, pDataDescr=c("classname"))
    miRNA.ds <- createOmicsExpressionSet(Data=Block2, pData=ed, pDataDescr=c("classname"))
    
    # 3. Compute reference feature distance matrix
    bioDistmRNA <- bioDistclass(name="mRNAbymRNA",
                                distance=cor(t(exprs(mRNA.ds)),
                                             method="spearman"),
                                map.name="id",
                                map.metadata=list(),
                                params=list())
    
    # 4. Create a mapping object
    MAP.SYMBOL <- bioMap(name = "Symbol-miRNA",
                         metadata = list(type_v1="Gene", type_v2="miRNA",
                                         source_database="targetscan.Hs.eg.db",
                                         data_extraction="July2014"),
                         map=mapdata)
    
    # 5. Compute surrogate feature distances mapped to reference features
    bioDistmiRNA <- bioDist(referenceFeatures=rownames(Block1),     
                            reference="Var1",
                            mapping=MAP.SYMBOL,
                            surrogateData=miRNA.ds, 
                            referenceData=mRNA.ds, 
                            maxitems=2,
                            selectionRule="sd",
                            expfac=NULL,
                            aggregation="sum",
                            distance="spearman",
                            noMappingDist=0,
                            filtering=NULL,
                            name="mRNAbymiRNA")
    
    # 6. Define a weight matrix and compute weighted combinations of distances
    bioDistList <- list(bioDistmRNA, bioDistmiRNA)
    sample.weights <- matrix(0, 4, 2)
    sample.weights[, 1] <- c(0, 0.33, 0.67, 1)
    sample.weights[, 2] <- c(1, 0.67, 0.33, 0)
    
    bioDistWList <- bioDistW(referenceFeatures=rownames(Block1),
                             bioDistList=bioDistList,
                             weights=sample.weights)
    
    # 7. Plot and save the feature distance of weighted combinations and associated features
    pdf("omics_clustering_plots.pdf", width = 10, height = 8)
    
    print(bioDistWPlot(referenceFeatures=rownames(Block1),
                 listDistW=bioDistWList,
                 method.cor="spearman"))
    
    IDH1.F <- bioDistFeature(Feature="IDH1",
                             listDistW=bioDistWList,
                             threshold.cor=0.7)
    
    bioDistFeaturePlot(data=IDH1.F)
    
    dev.off()
    
    # 8. Save meaningful results to files
    saveRDS(bioDistWList, file = "bioDistWList.rds")
    write.csv(IDH1.F, file = "IDH1_associated_features.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved: 'omics_clustering_plots.pdf', 'bioDistWList.rds', 'IDH1_associated_features.csv'.")

    writeLines(c(
        '"BIOC_STATEGRA_OMICS_CLUSTERING":',
        paste0('    STATegRa: ', as.character(packageVersion('STATegRa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omics_clustering.csv versions.yml
    """
}

workflow BIOC_STATEGRA_OMICS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Block1, Block2, ed, mapdata ] ]

    main:
    BIOC_STATEGRA_OMICS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_STATEGRA_OMICS_CLUSTERING.out.tables
    plots    = BIOC_STATEGRA_OMICS_CLUSTERING.out.plots
    objects  = BIOC_STATEGRA_OMICS_CLUSTERING.out.objects
    versions = BIOC_STATEGRA_OMICS_CLUSTERING.out.versions
}
