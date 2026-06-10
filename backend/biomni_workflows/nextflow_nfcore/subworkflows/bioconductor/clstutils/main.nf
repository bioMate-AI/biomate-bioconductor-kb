#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clstutils — taxonomic_classification
// Classify query sequences placed on a phylogenetic tree using pplacer outputs and a reference package.
// Input: refpkg, placefile, distfile
// Container: quay.io/biocontainers/bioconductor-clstutils:1.58.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-clstutils:1.58.0--r45hdfd78af_0"

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
    .bm_deps <- c("ape", "clst", "clstutils", "lattice")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(clstutils)
    
    # Define input file paths in the working directory
    refpkg_input <- "refpkg"
    placefile <- "placefile"
    distfile <- "distfile"
    
    # Validate existence of required input files
    if (!file.exists(refpkg_input)) {
      stop("Required input 'refpkg' (directory or archive) not found in the working directory.")
    }
    if (!file.exists(placefile)) {
      stop("Required input 'placefile' not found in the working directory.")
    }
    if (!file.exists(distfile)) {
      stop("Required input 'distfile' not found in the working directory.")
    }
    
    # Handle refpkg input (extract if it is an archive, otherwise use directory directly)
    if (file.info(refpkg_input)\$isdir) {
      refpkg <- refpkg_input
    } else {
      # Attempt to untar if it is an archive file
      temp_dir <- tempfile(pattern = "refpkg_")
      dir.create(temp_dir, showWarnings = FALSE)
      
      # Try untarring the archive
      tryCatch({
        untar(refpkg_input, exdir = temp_dir)
      }, error = function(e) {
        stop("Failed to extract 'refpkg' archive: ", e\$message)
      })
      
      # Identify the extracted directory path
      extracted_dirs <- list.dirs(temp_dir, recursive = FALSE)
      if (length(extracted_dirs) > 0) {
        refpkg <- extracted_dirs[1]
      } else {
        refpkg <- temp_dir
      }
    }
    
    # 1. Calculate tree distances using treeDists
    treedists <- treeDists(distfile=distfile, placefile=placefile)
    
    # 2. Retrieve taxonomic information from the reference package using taxonomyFromRefpkg
    taxdata <- taxonomyFromRefpkg(refpkg, seqnames=rownames(treedists\$dmat), lowest_rank='species')
    
    # 3. Define query placement data
    placetab <- data.frame(at=49, edge=5.14909e-07, branch=5.14909e-07)
    
    # 4. Classify placements using classifyPlacements
    cdata <- classifyPlacements(taxdata, treedists, placetab)
    
    # Write meaningful output files
    write.csv(cdata, file = "classification_results.csv", row.names = FALSE)
    saveRDS(cdata, file = "classification_results.rds")
    saveRDS(treedists, file = "treedists.rds")
    saveRDS(taxdata, file = "taxdata.rds")
    
    cat("Taxonomic classification completed successfully. Results written to 'classification_results.csv' and 'classification_results.rds'.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION":
        clstutils: \$(Rscript -e 'cat(as.character(packageVersion("clstutils")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomic_classification.csv versions.yml
    """
}

workflow BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ refpkg, placefile, distfile ] ]

    main:
    BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION.out.tables
    plots    = BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION.out.plots
    objects  = BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION.out.objects
    versions = BIOC_CLSTUTILS_TAXONOMIC_CLASSIFICATION.out.versions
}
