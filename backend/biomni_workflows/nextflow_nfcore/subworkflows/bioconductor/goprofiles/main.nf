#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goProfiles — basic_profiling_and_visualization
// Generate functional profiles for gene lists at a specific GO level and visually compare them.
// Input: list1, list2
// Container: quay.io/biocontainers/bioconductor-goprofiles:1.72.0--r45hdfd78af_0
// R packages: goProfiles, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: goProfiles, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute basic profiles for each gene list using `basicProfile`
//  * 2. [Core Analysis] Merge the profiles using `mergeProfilesLists`
//  * 3. [Core Analysis] Print the merged profiles using `printProfiles`
//  * 4. [Visualization & Output] Plot individual or merged profiles using `plotProfiles`

nextflow.enable.dsl = 2

process BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("goProfiles", "org.Hs.eg.db")
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
    library(goProfiles)
    library(org.Hs.eg.db)
    
    # Helper function to read Entrez gene IDs from user input files
    read_gene_list <- function(filename) {
      if (file.exists(filename)) {
        filepath <- filename
      } else if (file.exists(paste0(filename, ".txt"))) {
        filepath <- paste0(filename, ".txt")
      } else if (file.exists(paste0(filename, ".csv"))) {
        filepath <- paste0(filename, ".csv")
      } else {
        stop(paste("Error: Input file for", filename, "not found in the working directory."))
      }
      
      # Read lines, omit empty lines and comments
      genes <- readLines(filepath)
      genes <- trimws(genes)
      genes <- genes[genes != "" & !grepl("^#", genes)]
      
      # If comma-separated in a single line, split them
      if (length(genes) == 1 && grepl(",", genes)) {
        genes <- unlist(strsplit(genes, ","))
        genes <- trimws(genes)
      }
      
      return(genes)
    }
    
    # 1. Read user input gene lists
    list1_genes <- read_gene_list("list1")
    list2_genes <- read_gene_list("list2")
    
    # 2. Compute basic profiles for each gene list using basicProfile
    list1.MF <- basicProfile (list1_genes, onto="MF", level=2, orgPackage="org.Hs.eg.db") 
    list2.MF <- basicProfile (list2_genes, onto="MF", level=2, orgPackage="org.Hs.eg.db") 
    
    # 3. Merge the profiles using mergeProfilesLists
    merged.MF <-mergeProfilesLists(list1.MF, list2.MF, profNames=c("List 1", "List 2"))
    
    # 4. Print the merged profiles using printProfiles (capturing output to a text file)
    sink("merged_profiles_summary.txt")
    printProfiles(merged.MF, percentage=TRUE)
    sink()
    
    # Also print to console for visibility
    printProfiles(merged.MF, percentage=TRUE)
    
    # 5. Plot individual profiles using plotProfiles (saving to PDF)
    pdf("individual_profile_list1.pdf", width=8, height=8)
    plotProfiles (list1.MF, aTitle="List 1 Profile")
    dev.off()
    
    # 6. Compute profile for all three ontologies (ANY)
    list1.ANY <- basicProfile (list1_genes, onto="ANY", level=2, orgPackage="org.Hs.eg.db") 
    
    # 7. Plot merged profiles using plotProfiles (saving to PDF)
    pdf("merged_profiles_comparison.pdf", width=10, height=8)
    plotProfiles (merged.MF, percentage=T,aTitle="List 1 vs List 2", legend=T)
    dev.off()
    
    # Save meaningful results as RDS objects for downstream analysis
    saveRDS(list1.MF, "list1_MF_profile.rds")
    saveRDS(list2.MF, "list2_MF_profile.rds")
    saveRDS(merged.MF, "merged_MF_profile.rds")
    saveRDS(list1.ANY, "list1_ANY_profile.rds")
    
    # Export merged profile data frame to CSV if possible
    if (!is.null(merged.MF\$MF)) {
      write.csv(as.data.frame(merged.MF\$MF), "merged_profiles_MF.csv", row.names=FALSE)
    }

    writeLines(c(
        '"BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION":',
        paste0('    goProfiles: ', as.character(packageVersion('goProfiles')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_profiling_and_visualization.csv versions.yml
    """
}

workflow BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list1, list2 ] ]

    main:
    BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION.out.tables
    plots    = BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION.out.plots
    objects  = BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION.out.objects
    versions = BIOC_GOPROFILES_BASIC_PROFILING_AND_VISUALIZATION.out.versions
}
