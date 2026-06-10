#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneBreak — cghcall_object_pipeline
// Detect and analyze recurrent gene breakpoints starting from a preprocessed cghCall or QDNAseq Bioconductor object.
// Input: copynumber.data.chr20, ens.gene.ann.hg18
// Container: quay.io/biocontainers/bioconductor-genebreak:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CGHcall, GeneBreak
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load copy number data and extract breakpoints using getBreakpoints()
//  * 2. [Core Analysis] Filter out non-CNA-associated breakpoints using bpFilter()
//  * 3. [Core Analysis] Map genomic features to genes using addGeneAnnotation()
//  * 4. [Core Analysis] Identify gene-associated breakpoints using bpGenes()
//  * 5. [Core Analysis] Calculate cohort-based statistics at the gene level using bpStats() with the Gilbert method
//  * 6. [Core Analysis] Calculate cohort-based statistics at the feature level using bpStats() with the BH method
//  * 7. [Visualization & Output] Plot breakpoint frequencies across the chromosome using bpPlot()

nextflow.enable.dsl = 2

process BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        
        # Load required libraries
        library(GeneBreak)
        library(CGHcall)
        
        # Helper function to robustly load user input files from the working directory
        load_input_file <- function(filename) {
          if (!file.exists(filename)) {
            # Try with common extensions if the exact filename is not found
            if (file.exists(paste0(filename, ".rds"))) {
              return(readRDS(paste0(filename, ".rds")))
            } else if (file.exists(paste0(filename, ".RData"))) {
              env <- new.env()
              load(paste0(filename, ".RData"), envir = env)
              return(env[[names(env)[1]]])
            } else if (file.exists(paste0(filename, ".csv"))) {
              return(read.csv(paste0(filename, ".csv"), header = TRUE, stringsAsFactors = FALSE))
            } else if (file.exists(paste0(filename, ".txt"))) {
              return(read.table(paste0(filename, ".txt"), header = TRUE, sep = "\t", stringsAsFactors = FALSE))
            } else {
              stop(paste("Required input file not found:", filename))
            }
          }
          
          # If file exists exactly as named, attempt to parse it
          obj <- tryCatch(readRDS(filename), error = function(e) NULL)
          if (!is.null(obj)) return(obj)
          
          env <- new.env()
          res <- tryCatch(load(filename, envir = env), error = function(e) NULL)
          if (!is.null(res) && length(env) > 0) {
            return(env[[names(env)[1]]])
          }
          
          df <- tryCatch(read.csv(filename, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
          if (!is.null(df) && ncol(df) > 1) return(df)
          
          df_tab <- tryCatch(read.table(filename, header = TRUE, sep = "\t", stringsAsFactors = FALSE), error = function(e) NULL)
          if (!is.null(df_tab) && ncol(df_tab) > 1) return(df_tab)
          
          stop(paste("Could not read file format for:", filename))
        }
        
        # 1. Load copy number data and extract breakpoints
        message("Loading copy number data...")
        copynumber.data.chr20 <- load_input_file("copynumber.data.chr20")
        
        message("Detecting breakpoints...")
        breakpoints <- getBreakpoints( data = copynumber.data.chr20 )
        
        # 2. Filter out non-CNA-associated breakpoints
        message("Filtering breakpoints...")
        breakpointsFiltered <- bpFilter( breakpoints, filter = "CNA-ass" )
        
        # 3. Map genomic features to genes
        message("Loading gene annotation...")
        ens.gene.ann.hg18 <- load_input_file("ens.gene.ann.hg18")
        
        message("Adding gene annotations...")
        breakpointsAnnotated <- addGeneAnnotation( breakpointsFiltered, ens.gene.ann.hg18 )
        
        # Extract gene-associated feature information
        geneFeatures <- geneInfo( breakpointsAnnotated )
        write.csv(geneFeatures, "gene_features.csv", row.names = FALSE)
        
        # Inspect features for a specific gene (dynamically selected to avoid hardcoding)
        if (nrow(geneFeatures) > 0) {
          sample_gene <- as.character(geneFeatures\$Gene[1])
          message(paste0("Features per gene (", sample_gene, "):"))
          featuresPerGene ( breakpointsAnnotated , geneName = sample_gene )
        }
        
        # 4. Identify gene-associated breakpoints
        message("Identifying gene-associated breakpoints...")
        breakpointGenes <- bpGenes( breakpointsAnnotated )
        result_BreakpointGenes <- geneInfo ( breakpointGenes )
        write.csv(result_BreakpointGenes, "breakpoint_genes.csv", row.names = FALSE)
        
        # 5. Calculate cohort-based statistics at the gene level (Gilbert method)
        message("Calculating gene-level statistics...")
        breakpointStatistics <- bpStats( breakpointGenes, level = "gene", method = "Gilbert" )
        recurrent_genes_df <- recurrentGenes( breakpointStatistics )
        print(head(recurrent_genes_df))
        write.csv(recurrent_genes_df, "recurrent_genes.csv", row.names = FALSE)
        
        # 6. Calculate cohort-based statistics at the feature level (BH method)
        message("Calculating feature-level statistics...")
        breakpointStatistics <- bpStats( breakpointStatistics, level = "feature", method = "BH" )
        feature_info_df <- featureInfo( breakpointStatistics )
        print(head(feature_info_df))
        write.csv(feature_info_df, "feature_statistics.csv", row.names = TRUE)
        
        # Save the final breakpoint statistics object
        saveRDS(breakpointStatistics, "breakpoint_statistics.rds")
        
        # 7. Plot breakpoint frequencies across the chromosome
        message("Plotting breakpoint frequencies...")
        pdf("breakpoint_plot.pdf", width = 10, height = 7)
        bpPlot( breakpointStatistics, fdr.threshold = 0.1 )
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE":',
        paste0('    GeneBreak: ', as.character(packageVersion('GeneBreak')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cghcall_object_pipeline.csv versions.yml
    """
}

workflow BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ copynumber.data.chr20, ens.gene.ann.hg18 ] ]

    main:
    BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE.out.tables
    plots    = BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE.out.plots
    objects  = BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE.out.objects
    versions = BIOC_GENEBREAK_CGHCALL_OBJECT_PIPELINE.out.versions
}
