#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VennDetail — venn_detail_analysis
// Perform multi-set intersection analysis, visualize overlaps using multiple plot formats, and extract annotated subset details.
// Input: list_of_vectors, annotation_list
// Container: quay.io/biocontainers/bioconductor-venndetail:1.26.0--r45hdfd78af_0
// R packages: VennDetail
// Bioconductor: 3.20 | R: 4.4
// Requires: VennDetail
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create the Venn object using venndetail
//  * 2. [Visualization & Output] Generate traditional, Venn-Pie, and UpSet plots using plot
//  * 3. [Core Analysis] List subset names using detail
//  * 4. [Core Analysis] Extract specific subsets using getSet
//  * 5. [Visualization & Output] Export all subsets in long or wide format using result
//  * 6. [Input & Preparation] Create customized Venn-Pie diagrams using vennpie
//  * 7. [Core Analysis] Combine subset details with user annotation datasets using getFeature
//  * 8. [Visualization & Output] Generate a bar-plot of subset sizes using dplot

nextflow.enable.dsl = 2

process BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("VennDetail")
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
            
        # Load required library
        library(VennDetail)
        
        # Helper function to robustly read RDS files with or without extension
        read_input <- function(filename) {
          if (file.exists(filename)) {
            return(readRDS(filename))
          } else if (file.exists(paste0(filename, ".rds"))) {
            return(readRDS(paste0(filename, ".rds")))
          } else {
            stop(paste("Required input file", filename, "not found in the working directory."))
          }
        }
        
        # Read user inputs
        list_of_vectors <- read_input("list_of_vectors")
        annotation_list <- read_input("annotation_list")
        
        # Ensure inputs are named to avoid missing names in VennDetail
        if (is.null(names(list_of_vectors))) {
          names(list_of_vectors) <- paste0("Set", seq_along(list_of_vectors))
        }
        if (is.null(names(annotation_list)) && length(annotation_list) > 0) {
          names(annotation_list) <- names(list_of_vectors)[seq_along(annotation_list)]
        }
        
        # 1. Create the Venn object using venndetail
        ven <- venndetail(list_of_vectors)
        saveRDS(ven, "ven_object.rds")
        
        # 2. Generate traditional, Venn-Pie, and UpSet plots using plot
        pdf("plot_traditional.pdf")
        print(plot(ven))
        dev.off()
        
        pdf("plot_vennpie.pdf")
        print(plot(ven, type = "vennpie"))
        dev.off()
        
        pdf("plot_upset.pdf")
        print(plot(ven, type = "upset"))
        dev.off()
        
        # 3. List subset names using detail
        ven_detail <- detail(ven)
        write.csv(data.frame(Subset = names(ven_detail), Size = as.numeric(ven_detail)), 
                  "detail_summary.csv", row.names = FALSE)
        
        # 4. Extract specific subsets using getSet
        tryCatch({
          avail_subsets <- names(ven_detail)
          subsets_to_get <- c()
          if ("Shared" %in% avail_subsets) subsets_to_get <- c(subsets_to_get, "Shared")
          if (length(avail_subsets) > 0) subsets_to_get <- c(subsets_to_get, avail_subsets[1])
          subsets_to_get <- unique(subsets_to_get)
          
          set_res <- getSet(ven, subset = subsets_to_get)
          write.csv(head(set_res, 10), "getSet_shared_SCN_head10.csv", row.names = FALSE)
          write.csv(set_res, "getSet_shared_SCN_all.csv", row.names = FALSE)
        }, error = function(e) {
          warning("Could not extract subsets: ", e\$message)
        })
        
        # 5. Export all subsets in long or wide format using result
        res_long <- result(ven)
        write.csv(res_long, "result_long.csv", row.names = FALSE)
        
        res_wide <- result(ven, wide = TRUE)
        write.csv(res_wide, "result_wide.csv", row.names = FALSE)
        
        # 6. Create customized Venn-Pie diagrams using vennpie
        pdf("vennpie_any1.pdf")
        tryCatch({
          print(vennpie(ven, any = 1, revcolor = "lightgrey"))
        }, error = function(e) {
          warning("vennpie any=1 failed: ", e\$message)
        })
        dev.off()
        
        pdf("vennpie_log.pdf")
        tryCatch({
          print(vennpie(ven, log = TRUE))
        }, error = function(e) {
          warning("vennpie log=TRUE failed: ", e\$message)
        })
        dev.off()
        
        # Extract up to 5 sets from user input to avoid fabricating data
        num_sets <- min(length(list_of_vectors), 5)
        venn_input <- list_of_vectors[1:num_sets]
        
        venn <- venndetail(venn_input)
        saveRDS(venn, "venn_5set_object.rds")
        
        pdf("vennpie_min4.pdf")
        tryCatch({
          min_val <- min(4, num_sets)
          print(vennpie(venn, min = min_val))
        }, error = function(e) {
          warning("vennpie min failed: ", e\$message)
        })
        dev.off()
        
        # 7. Combine subset details with user annotation datasets using getFeature
        tryCatch({
          avail_subsets <- names(detail(ven))
          target_subset <- if ("Shared" %in% avail_subsets) "Shared" else avail_subsets[1]
          feat_res <- getFeature(ven, subset = target_subset, rlist = annotation_list)
          write.csv(feat_res, "getFeature_shared.csv", row.names = FALSE)
        }, error = function(e) {
          warning("getFeature failed: ", e\$message)
        })
        
        # 8. Generate a bar-plot of subset sizes using dplot
        pdf("dplot_subsets.pdf")
        tryCatch({
          print(dplot(ven, order = TRUE, textsize = 4))
        }, error = function(e) {
          warning("dplot failed: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS":',
        paste0('    VennDetail: ', as.character(packageVersion('VennDetail')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_venn_detail_analysis.csv versions.yml
    """
}

workflow BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list_of_vectors, annotation_list ] ]

    main:
    BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS.out.tables
    plots    = BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS.out.plots
    objects  = BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS.out.objects
    versions = BIOC_VENNDETAIL_VENN_DETAIL_ANALYSIS.out.versions
}
