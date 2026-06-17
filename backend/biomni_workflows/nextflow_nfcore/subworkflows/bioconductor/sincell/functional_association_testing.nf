#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sincell — functional_association_testing
// Test the association of a reconstructed cell-state hierarchy with predefined gene sets (e.g., pathways).
// Input: SO_t72, geneset.list
// Container: quay.io/biocontainers/bioconductor-sincell:1.42.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sincell
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the gene sets
//  * 2. [Core Analysis] Run the association test for gene sets that meet the minimum size overlap with the expression matrix

nextflow.enable.dsl = 2

process BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING {
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
    .bm_deps <- c("sincell")
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
    library(sincell)
    
    # -----------------------------------------------------------------------------
    # 1. Load User Inputs
    # -----------------------------------------------------------------------------
    
    # Load the Sincell object containing the reconstructed hierarchy
    if (file.exists("SO_t72.rds")) {
      SO_t72 <- readRDS("SO_t72.rds")
    } else if (file.exists("SO_t72")) {
      SO_t72 <- readRDS("SO_t72")
    } else {
      stop("Error: SO_t72 input file not found in the working directory.")
    }
    
    # Load the gene sets list
    if (file.exists("geneset.list.rds")) {
      geneset.list <- readRDS("geneset.list.rds")
    } else if (file.exists("geneset.list")) {
      geneset.list <- tryCatch({
        readRDS("geneset.list")
      }, error = function(e) {
        # Fallback: Parse as a standard GMT file if it is a text file
        lines <- readLines("geneset.list")
        parsed <- lapply(strsplit(lines, "\t"), function(x) {
          if (length(x) > 2) {
            genes <- x[3:length(x)]
            genes <- genes[genes != ""]
            return(genes)
          } else {
            return(character(0))
          }
        })
        names(parsed) <- sapply(strsplit(lines, "\t"), function(x) x[1])
        parsed
      })
    } else {
      stop("Error: geneset.list input file not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Run Functional Association Testing
    # -----------------------------------------------------------------------------
    
    minimum.geneset.size=30
    myAssociationOfCellsHierarchyWithAGeneSet<-list()
    for (i in 1:length(geneset.list)){
      if(sum(rownames(SO_t72[["expressionmatrix"]]) 
      	%in% geneset.list[[i]])>=minimum.geneset.size){
    	
        SO_t72<-sc_AssociationOfCellsHierarchyWithAGeneSet(SO_t72,geneset.list[[i]],
        	minimum.geneset.size=minimum.geneset.size,p.value.assessment=TRUE,
    	spearman.rank.threshold=0.5,num_it=1000)
        
        # Define SO as SO_t72 to resolve the vignette's internal object reference
        SO <- SO_t72
        
        myAssociationOfCellsHierarchyWithAGeneSet[[
        	as.character(i)]]<-list()
        myAssociationOfCellsHierarchyWithAGeneSet[[
        	as.character(i)]][["AssociationOfCellsHierarchyWithAGeneSet"]]<-
    		SO[["AssociationOfCellsHierarchyWithAGeneSet"]]
        myAssociationOfCellsHierarchyWithAGeneSet[[
        	as.character(i)]][["AssociationOfCellsHierarchyWithAGeneSet.pvalue"]]<-
    	SO[["AssociationOfCellsHierarchyWithAGeneSet.pvalue"]]
      }
    }
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the updated Sincell object and the association list
    saveRDS(SO_t72, "SO_t72_associated.rds")
    saveRDS(myAssociationOfCellsHierarchyWithAGeneSet, "myAssociationOfCellsHierarchyWithAGeneSet.rds")
    
    # Export a structured CSV summary of the association results
    if (length(myAssociationOfCellsHierarchyWithAGeneSet) > 0) {
      results_list <- lapply(names(myAssociationOfCellsHierarchyWithAGeneSet), function(idx) {
        gene_set_name <- names(geneset.list)[as.numeric(idx)]
        if (is.null(gene_set_name) || is.na(gene_set_name)) {
          gene_set_name <- paste0("GeneSet_", idx)
        }
        val <- myAssociationOfCellsHierarchyWithAGeneSet[[idx]][["AssociationOfCellsHierarchyWithAGeneSet"]]
        pval <- myAssociationOfCellsHierarchyWithAGeneSet[[idx]][["AssociationOfCellsHierarchyWithAGeneSet.pvalue"]]
        data.frame(
          GeneSet_Index = idx,
          GeneSet_Name = gene_set_name,
          Association_Score = ifelse(is.null(val), NA, val),
          P_Value = ifelse(is.null(pval), NA, pval),
          stringsAsFactors = FALSE
        )
      })
      results_df <- do.call(rbind, results_list)
      write.csv(results_df, "association_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No gene sets met the minimum size overlap criteria."), 
                "association_results.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING":',
        paste0('    sincell: ', as.character(packageVersion('sincell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_functional_association_testing.csv versions.yml
    """
}

workflow BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SO_t72, geneset.list ] ]

    main:
    BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING.out.objects
    versions = BIOC_SINCELL_FUNCTIONAL_ASSOCIATION_TESTING.out.versions
}
