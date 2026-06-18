#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CluMSID — lc_ms_ms_external_peaklist
// Combine MS2 spectra from multiple LC-MS/MS runs, merge them using an external peak list, integrate annotations, and perform cluster analysis.
// Input: file1.mzML, file2.mzML, peak_table.tsv
// Container: quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0
// R packages: CluMSID, dplyr, magrittr, readr, stringr
// Bioconductor: 3.20 | R: 4.4
// Requires: CluMSID, dplyr, magrittr, readr, stringr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract MS2 spectra from multiple files using extractMS2spectra() and combine them
//  * 2. [Core Analysis] Format the external peak table to match CluMSID requirements
//  * 3. [Core Analysis] Merge spectra matching the external peak list using mergeMS2spectra() with peaktable and exclude_unmatched = TRUE
//  * 4. [Core Analysis] Add annotations using addAnnotations()
//  * 5. [Core Analysis] Generate a distance matrix using distanceMatrix()
//  * 6. [Visualization & Output] Plot cluster dendrograms and individual spectra using HCplot() and specplot()

nextflow.enable.dsl = 2

process BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("CluMSID", "dplyr", "magrittr", "readr", "stringr")
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
        library(CluMSID)
        library(dplyr)
        library(stringr)
        library(readr)
        library(magrittr)
        
        # Define input files from the working directory
        file1 <- "file1.mzML"
        file2 <- "file2.mzML"
        
        raw_mtbls_df <- "peak_table.tsv"
        
        # 1. Extract MS2 spectra from multiple files
        list1 <- extractMS2spectra (file1)
        list2 <- extractMS2spectra (file2)
        raw_oillist <- c (list1, list2)
        
        # 2. Format the external peak table to match CluMSID requirements
        mtbls_df <- readr :: read_delim (raw_mtbls_df, "\t" ) %>% 
          dplyr :: rename ( mz = 1, rt = 2, annotation = 3) %>% 
          dplyr :: mutate ( annotation = stringr :: str_replace (as.character(annotation), "unknown" , "" )) %>% 
          dplyr :: mutate ( id = paste0 ( "M" , mz, "T" , rt)) %>% 
          dplyr :: mutate ( rt = as.numeric(rt) * 60 ) %>% 
          dplyr :: select (id, mz, rt, annotation)
        
        # 3. Merge spectra matching the external peak list
        oillist <- mergeMS2spectra (raw_oillist, peaktable = mtbls_df[, 1 : 3 ], exclude_unmatched = TRUE , rt_tolerance = 60 , mz_tolerance = 3e-5 )
        
        # 4. Add annotations
        fl <- featureList (oillist)
        fl_annos <- dplyr :: left_join (fl, mtbls_df, by = "id" )
        annolist <- addAnnotations (oillist, fl_annos, annotationColumn = 6 )
        
        # Save annotated list and feature list
        saveRDS(annolist, "annolist.rds")
        write.csv(fl_annos, "feature_list_annotations.csv", row.names = FALSE)
        
        # 5. Generate a distance matrix
        distmat <- distanceMatrix (annolist, mz_tolerance = 3e-5 )
        saveRDS(distmat, "distance_matrix.rds")
        
        # 6. Plot cluster dendrograms and individual spectra
        pdf("clumsid_plots.pdf", width = 10, height = 10)
        
        tryCatch({
          HCplot (distmat, h = 0.7 , cex = 0.7 )
        }, error = function(e) {
          message("Could not generate HCplot: ", e\$message)
        })
        
        tryCatch({
          if (length(annolist) >= 1) {
            specplot ( annolist[[1]] )
          }
        }, error = function(e) {
          message("Could not plot first spectrum: ", e\$message)
        })
        
        tryCatch({
          if (length(annolist) >= 2) {
            specplot ( annolist[[2]] )
          }
        }, error = function(e) {
          message("Could not plot second spectrum: ", e\$message)
        })
        
        dev.off()

    writeLines(c(
        '"BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST":',
        paste0('    CluMSID: ', as.character(packageVersion('CluMSID')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms_ms_external_peaklist.csv versions.yml
    """
}

workflow BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file1.mzML, file2.mzML, peak_table.tsv ] ]

    main:
    BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST(ch_input)

    emit:
    tables   = BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST.out.tables
    plots    = BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST.out.plots
    objects  = BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST.out.objects
    versions = BIOC_CLUMSID_LC_MS_MS_EXTERNAL_PEAKLIST.out.versions
}
