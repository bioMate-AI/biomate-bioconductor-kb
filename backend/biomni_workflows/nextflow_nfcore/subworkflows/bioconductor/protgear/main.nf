#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: protGear — protein_microarray_preprocessing
// Pre-process raw protein microarray data (.gpr/.txt) through background correction, replicate CV filtering, tag subtraction, and normalization.
// Input: .gpr or .txt files, .csv files, TAG_antigens.csv
// Container: quay.io/biocontainers/bioconductor-protgear:1.10.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, gridExtra, pheatmap, plyr, protGear, purrr, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define array parameters using array_vars()
//  * 2. [Visualization & Output] Visualize slide spatial structure using visualize_slide() and visualize_slide_2d()
//  * 3. [Input & Preparation] Read raw array files using read_array_files()
//  * 4. [Visualization & Output] Extract background values using extract_bg() and plot them using plot_FB() and plot_bg()
//  * 5. [Core Analysis] Perform background correction and merge sample IDs using merge_sampleID()
//  * 6. [Visualization & Output] (Optional) Inspect buffer spots using buffer_spots() and plot_buffer()
//  * 7. [Visualization & Output] Estimate replicate CVs using cv_estimation() and summarize them using cv_by_sample_estimation()
//  * 8. [Core Analysis] Select best replicates using best_CV_estimation()
//  * 9. [Core Analysis] (Optional) Subtract purification tags using tag_subtract()
//  * 10. [Core Analysis] Normalize the data matrix using matrix_normalise()

nextflow.enable.dsl = 2

process BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
            library(protGear)
            library(plyr)
            library(dplyr)
            library(tidyr)
            library(purrr)
            library(ggplot2)
            library(gridExtra)
            library(pheatmap)
            
            # ==========================================
            # 1. PREPARE LOCAL DIRECTORY STRUCTURE
            # ==========================================
            
            # Find raw files and sample ID files in the current working directory
            raw_files <- list.files(".", pattern = "\\\\.(gpr|txt)\$", ignore.case = TRUE, full.names = TRUE)
            sample_files <- list.files(".", pattern = "\\\\.csv\$", ignore.case = TRUE, full.names = TRUE)
            sample_files <- sample_files[!grepl("TAG_antigens.csv", sample_files, ignore.case = TRUE)]
            
            if (length(raw_files) == 0) {
              stop("No .gpr or .txt files found in the working directory.")
            }
            if (length(sample_files) == 0) {
              stop("No sample ID .csv files found in the working directory.")
            }
            
            # Create structured directories as expected by array_vars()
            dir.create("array_data/machine1", recursive = TRUE, showWarnings = FALSE)
            dir.create("array_sampleID/machine1", recursive = TRUE, showWarnings = FALSE)
            dir.create("array_sampleID", recursive = TRUE, showWarnings = FALSE)
            
            file.copy(raw_files, "array_data/machine1/", overwrite = TRUE)
            file.copy(sample_files, "array_sampleID/machine1/", overwrite = TRUE)
            file.copy(sample_files, "array_sampleID/", overwrite = TRUE)
            
            # ==========================================
            # 2. DEFINE ARRAY PARAMETERS
            # ==========================================
            
            # Dynamically determine totsamples and blockspersample from the first sample ID file
            first_sample_file <- read.csv(sample_files[1])
            if (ncol(first_sample_file) >= 2) {
              totsamples_dyn <- length(unique(first_sample_file[[2]]))
              blockspersample_dyn <- round(nrow(first_sample_file) / totsamples_dyn)
              if (blockspersample_dyn < 1) blockspersample_dyn <- 1
            } else {
              totsamples_dyn <- 21
              blockspersample_dyn <- 2
            }
            
            genepix_vars <- array_vars(channel="635" ,
                                       chip_path = "array_data/",
                                       totsamples = totsamples_dyn,
                                       blockspersample = blockspersample_dyn,
                                       sampleID_path = "array_sampleID/",
                                       mig_prefix = "_first",
                                       machine = 1,
                                       date_process = "0520")
            
            # ==========================================
            # 3. VISUALIZE SLIDE SPATIAL STRUCTURE
            # ==========================================
            
            first_raw_file <- list.files("array_data/machine1", pattern="\\\\.txt\$|\\\\.gpr\$", full.names=TRUE)[1]
            
            pdf("slide_visualization.pdf")
            visualize_slide(infile=first_raw_file,
                            MFI_var ='F635 Median' )
            
            visualize_slide_2d(infile =first_raw_file, 
                               MFI_var ='B635 Median' )
            dev.off()
            
            # ==========================================
            # 4. READ RAW ARRAY FILES
            # ==========================================
            
            filenames <- list.files(file.path(genepix_vars\$paths[[1]]), 
                                    pattern="*.txt\$|*.gpr\$", full.names=FALSE)
            
            data_path <- paste0(genepix_vars\$paths[[1]],"/") 
            data_files <- purrr::map(.x = filenames, 
                                     .f = read_array_files,
                                     data_path=data_path ,
                                     genepix_vars=genepix_vars)
            data_files <- set_names(data_files, purrr::map(filenames, name_of_files))
            
            # ==========================================
            # 5. EXTRACT BACKGROUND VALUES
            # ==========================================
            
            dfs <- names(data_files) 
            allData_bg <- purrr::map(.x=dfs, .f=extract_bg,data_files=data_files,genepix_vars)
            allData_bg <- set_names(allData_bg, purrr::map(filenames, name_of_files))
            allData_bg <- plyr::ldply(allData_bg)
            
            write.csv(allData_bg, "allData_bg.csv", row.names = FALSE)
            
            pdf("background_plots.pdf")
            p1 <- plot_FB(allData_bg,antigen_name="antigen",
                          bg_MFI="BG_Median",FG_MFI="FBG_Median",log=FALSE)
            print(p1)
            
            p2 <- plot_bg(df=allData_bg, x_axis="Block",bg_MFI="BG_Median",
                    log_mfi=TRUE) 
            print(p2)
            dev.off()
            
            # ==========================================
            # 6. BACKGROUND CORRECTION & MERGE SAMPLE IDS
            # ==========================================
            
            sample_ID_merged_dfs <- purrr::map(.x=dfs, .f=merge_sampleID ,data_files=data_files , 
                                         genepix_vars, method="subtract_local")
            sample_ID_merged_dfs <- set_names(sample_ID_merged_dfs, purrr::map(filenames, name_of_files))
            
            # ==========================================
            # 7. INSPECT BUFFER SPOTS (OPTIONAL)
            # ==========================================
            
            tryCatch({
              buffer_transp <- purrr::map(.x=sample_ID_merged_dfs, .f=buffer_spots ,  buffer_spot="buffer")
              buffer_transp <- set_names(buffer_transp, purrr::map(filenames, name_of_files))
              buffers <- plyr::ldply(buffer_transp)
              write.csv(buffers, "buffers.csv", row.names = FALSE)
              
              pdf("buffer_plot.pdf")
              plot_buffer(buffers,buffer_names="antigen",buffer_mfi="FMedianBG_correct",slide_id=".id")
              dev.off()
            }, error = function(e) {
              message("Buffer spots processing skipped or failed: ", e\$message)
            })
            
            # ==========================================
            # 8. ESTIMATE REPLICATE CVS
            # ==========================================
            
            # Dynamically determine lab_replicates based on the most common replicate count per antigen per sample
            reps_counts <- sample_ID_merged_dfs[[1]] %>% 
              group_by(sampleID, antigen) %>% 
              summarise(n = n(), .groups = "drop")
            lab_replicates_dyn <- as.numeric(names(sort(table(reps_counts\$n), decreasing = TRUE)[1]))
            if (is.na(lab_replicates_dyn) || lab_replicates_dyn < 1) {
              lab_replicates_dyn <- 3
            }
            
            dataCV <- purrr::map(.x=sample_ID_merged_dfs, .f=cv_estimation ,lab_replicates=lab_replicates_dyn  ,
                                 cv_cut_off=20,
                                 sampleID_var='sampleID', antigen_var='antigen' ,replicate_var='replicate' ,
                                 mfi_var='FMedianBG_correct')
            dataCV <- set_names(dataCV, purrr::map(filenames, name_of_files))
            
            dataCV_sample <- purrr::map(.x=dataCV, .f=protGear::cv_by_sample_estimation , cv_variable="cvCat_all",
                                        lab_replicates=lab_replicates_dyn)
            dataCV_sample <- set_names(dataCV_sample, purrr::map(filenames, name_of_files))
            all_cv_sample <- plyr::ldply(dataCV_sample)
            
            write.csv(all_cv_sample, "all_cv_sample.csv", row.names = FALSE)
            
            # ==========================================
            # 9. SELECT BEST REPLICATES
            # ==========================================
            
            dataCV_best2 <- purrr::map(.x=dataCV, .f=best_CV_estimation , slide_id="iden",lab_replicates=lab_replicates_dyn,
                                       cv_cut_off=20)
            dataCV_best2 <- set_names(dataCV_best2, purrr::map(filenames, name_of_files))
            
            # ==========================================
            # 10. SUBTRACT PURIFICATION TAGS (OPTIONAL)
            # ==========================================
            
            if (file.exists("TAG_antigens.csv")) {
              tag_file <- read.csv("TAG_antigens.csv")
              
              # Dynamically extract tag_antigens from the TAG_name column
              if ("TAG_name" %in% colnames(tag_file)) {
                tag_antigens <- unique(as.character(tag_file\$TAG_name))
                tag_antigens <- tag_antigens[!tag_antigens %in% c("NO_TAG", "", NA)]
              } else {
                tag_antigens <- c("CD4TAG" , "GST", "MBP")
              }
              
              batch_vars <- list(machine="m1", day="0520")
            
              dataCV_tag <- purrr::map(.x=dataCV_best2, .f=tag_subtract , 
                                       tag_antigens=tag_antigens, mean_best_CV_var="mean_best_CV",tag_file=tag_file,
                                       antigen_var='antigen',
                                       batch_vars=batch_vars)
              dataCV_tag <- set_names(dataCV_tag, purrr::map(filenames, name_of_files))
              dataCV_tag <- plyr::ldply(dataCV_tag)
            } else {
              message("TAG_antigens.csv not found. Skipping tag subtraction step.")
              dataCV_tag <- plyr::ldply(dataCV_best2)
              # Ensure downstream compatibility by copying mean_best_CV to mean_best_CV_tag
              dataCV_tag\$mean_best_CV_tag <- dataCV_tag\$mean_best_CV
            }
            
            write.csv(dataCV_tag, "dataCV_processed.csv", row.names = FALSE)
            
            # ==========================================
            # 11. NORMALIZE THE DATA MATRIX
            # ==========================================
            
            df_to_normalise <-  dataCV_tag  %>%  ungroup() %>%  
              dplyr::select(slide=.id,sampleID,sample_array_ID,antigen,mean_best_CV) %>%  
              group_by(sampleID, slide)
            df_to_normalise\$sample_index <- group_indices(.data =df_to_normalise )
            
            to_normalise <- df_to_normalise %>%
             ungroup() %>% dplyr::select(-slide,-sampleID,-sample_array_ID) %>% 
              dplyr::select(antigen, sample_index, everything()) %>%  
              gather(variable, value, -(antigen:sample_index)) %>%
              unite(temp, antigen ) %>%  dplyr::select(-variable) %>%
              spread(temp, value) %>% 
              as.data.frame(.)
            
            row.names(to_normalise) <- to_normalise\$sample_index
            
            matrix_antigen <-  to_normalise %>% 
               dplyr::select(-sample_index) %>% 
              as.matrix(.)
            
            # Dynamically select an antigen present in the dataset for filtering array_matrix
            available_antigens <- unique(df_to_normalise\$antigen)
            target_antigen <- if ("AMA1" %in% available_antigens) "AMA1" else available_antigens[1]
            
            array_matrix <- df_to_normalise %>% 
              filter(antigen==target_antigen) %>% 
              ungroup() %>% 
               dplyr::select(sample_array_ID,sample_index,slide)
            
            # Dynamically adjust control antigens to avoid errors if they are missing
            control_antigens <- c("CommercialHumanIgG","CD4TAG")
            control_antigens <- control_antigens[control_antigens %in% colnames(matrix_antigen)]
            if (length(control_antigens) == 0) {
              control_antigens <- colnames(matrix_antigen)[1]
            }
            
            normlise_df <- matrix_normalise(matrix_antigen, method = "vsn", array_matrix=array_matrix,
                                   return_plot = TRUE,control_antigens=control_antigens)
            
            # Save normalization results
            saveRDS(normlise_df, "normlise_df.rds")
            write.csv(normlise_df\$matrix_antigen_normalised, "normalized_data.csv")
            
            pdf("normalization_plots.pdf")
            if (!is.null(normlise_df\$plot_normalisation)) {
              print(normlise_df\$plot_normalisation)
            }
            dev.off()
            
            # Clean up temporary directories
            unlink("array_data", recursive = TRUE)
            unlink("array_sampleID", recursive = TRUE)
            
            message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING":',
        paste0('    protGear: ', as.character(packageVersion('protGear')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_microarray_preprocessing.csv versions.yml
    """
}

workflow BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ .gpr or .txt files, .csv files, TAG_antigens.csv ] ]

    main:
    BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING.out.tables
    plots    = BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING.out.plots
    objects  = BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING.out.objects
    versions = BIOC_PROTGEAR_PROTEIN_MICROARRAY_PREPROCESSING.out.versions
}
