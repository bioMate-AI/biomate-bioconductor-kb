#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hopach — hopach_gene_and_array_clustering
// Perform hybrid hierarchical clustering on genes and arrays, estimate cluster membership confidence using bootstrap resampling, and export the results for visual
// Input: golub.subset, gnames.subset
// Container: quay.io/biocontainers/bioconductor-hopach:2.70.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: hopach
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute gene distance matrix
//  * 2. [Core Analysis] Run HOPACH clustering on genes
//  * 3. [Visualization & Output] Plot the ordered gene distance matrix
//  * 4. [Core Analysis] Perform bootstrap resampling on gene clusters
//  * 5. [Visualization & Output] Plot bootstrap reappearance proportions
//  * 6. [Core Analysis] Run HOPACH clustering on arrays
//  * 7. [Visualization & Output] Export gene clustering and bootstrap results to a text file
//  * 8. [Visualization & Output] Export fuzzy clustering files for MapleTree
//  * 9. [Visualization & Output] Export hierarchical tree files for MapleTree/TreeView

nextflow.enable.dsl = 2

process BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(hopach)
    
    # Helper function to robustly read input files from the working directory
    read_input_matrix <- function(filename) {
      # Try reading as RDS first
      for (ext in c("", ".rds", ".RDS")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          res <- tryCatch({ readRDS(fn) }, error = function(e) NULL)
          if (!is.null(res)) return(as.matrix(res))
        }
      }
      # Try reading as delimited text (CSV/TSV)
      for (ext in c("", ".csv", ".tsv", ".txt")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          res <- tryCatch({
            read.table(fn, header = TRUE, row.names = 1, sep = "", check.names = FALSE)
          }, error = function(e) NULL)
          if (!is.null(res)) return(as.matrix(res))
          
          res <- tryCatch({
            read.csv(fn, header = TRUE, row.names = 1, check.names = FALSE)
          }, error = function(e) NULL)
          if (!is.null(res)) return(as.matrix(res))
        }
      }
      stop(paste("Error: Could not read input file:", filename))
    }
    
    read_input_gnames <- function(filename) {
      for (ext in c("", ".rds", ".RDS")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          res <- tryCatch({ readRDS(fn) }, error = function(e) NULL)
          if (!is.null(res)) return(res)
        }
      }
      for (ext in c("", ".csv", ".tsv", ".txt")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          res <- tryCatch({
            read.csv(fn, header = FALSE, stringsAsFactors = FALSE)
          }, error = function(e) NULL)
          if (!is.null(res)) return(res)
          
          res <- tryCatch({
            read.table(fn, header = FALSE, sep = "\t", stringsAsFactors = FALSE)
          }, error = function(e) NULL)
          if (!is.null(res)) return(res)
        }
      }
      stop(paste("Error: Could not read input file:", filename))
    }
    
    # Read user input files
    golub.subset <- read_input_matrix("golub.subset")
    gnames.subset <- read_input_gnames("gnames.subset")
    
    # Ensure gnames.subset is formatted to safely allow gnames.subset[,3] indexing
    if (is.null(dim(gnames.subset))) {
      gnames.subset <- data.frame(V1 = gnames.subset, V2 = gnames.subset, V3 = gnames.subset, stringsAsFactors = FALSE)
    } else {
      gnames.subset <- as.data.frame(gnames.subset, stringsAsFactors = FALSE)
      while (ncol(gnames.subset) < 3) {
        gnames.subset[[paste0("V", ncol(gnames.subset) + 1)]] <- gnames.subset[[1]]
      }
    }
    
    # 1. Compute gene distance matrix
    gene.dist<-distancematrix(golub.subset,"cosangle")
    
    # 2. Run HOPACH clustering on genes
    gene.hobj<-hopach(golub.subset,dmat=gene.dist)
    
    # 3. Plot the ordered gene distance matrix
    pdf("gene_distance_matrix_plot.pdf", width = 8, height = 8)
    dplot(gene.dist,gene.hobj,ord="final",main="Golub AML/ALL Data (1999): Gene Distance Matrix",showclusters=FALSE)  
    dev.off()
    
    # 4. Perform bootstrap resampling on gene clusters
    bobj<-boothopach(golub.subset,gene.hobj,B=100)
    
    # 5. Plot bootstrap reappearance proportions
    pdf("bootstrap_reappearance_plot.pdf", width = 8, height = 8)
    bootplot(bobj,gene.hobj,ord="bootp",main="Golub AML/ALL Data (1999)",showclusters=FALSE)
    dev.off()
    
    # 6. Run HOPACH clustering on arrays
    array.hobj<-hopach(t(golub.subset),d="euclid")
    
    # 7. Export gene clustering and bootstrap results to a text file
    makeoutput(golub.subset,gene.hobj,bobj,file="Golub.out",gene.names=gnames.subset[,3])
    
    # 8. Export fuzzy clustering files for MapleTree
    boot2fuzzy(golub.subset,bobj,gene.hobj,array.hobj,file="GolubFuzzy",gene.names=gnames.subset[,3]) 
    
    # 9. Export hierarchical tree files for MapleTree/TreeView
    hopach2tree(golub.subset,file="GolubTree",hopach.genes=gene.hobj,hopach.arrays=NULL,dist.genes=gene.dist,gene.names=gnames.subset[,3])
    
    # Save R objects for downstream analysis
    saveRDS(gene.hobj, "gene_hobj.rds")
    saveRDS(array.hobj, "array_hobj.rds")
    saveRDS(bobj, "bobj.rds")
    saveRDS(gene.dist, "gene_dist.rds")
    
    cat("Pipeline completed successfully. Outputs generated:\n")
    cat("- gene_distance_matrix_plot.pdf\n")
    cat("- bootstrap_reappearance_plot.pdf\n")
    cat("- Golub.out\n")
    cat("- GolubFuzzy.cdt, GolubFuzzy.fct, GolubFuzzy.mb\n")
    cat("- GolubTree.cdt, GolubTree.gtr\n")
    cat("- gene_hobj.rds, array_hobj.rds, bobj.rds, gene_dist.rds\n")

    writeLines(c(
        '"BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING":',
        paste0('    hopach: ', as.character(packageVersion('hopach')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hopach_gene_and_array_clustering.csv versions.yml
    """
}

workflow BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ golub.subset, gnames.subset ] ]

    main:
    BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING.out.tables
    plots    = BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING.out.plots
    objects  = BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING.out.objects
    versions = BIOC_HOPACH_HOPACH_GENE_AND_ARRAY_CLUSTERING.out.versions
}
