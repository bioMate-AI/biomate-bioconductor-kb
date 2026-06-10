library(OMICsPCA)
library(OMICsPCAdata)
library(MultiAssayExperiment)

# Load all datasets from OMICsPCAdata
datalist <- data(package = "OMICsPCAdata")
datanames <- datalist$results[, "Item"]
datanames <- gsub(" .*$", "", datanames)

if (length(datanames) > 0) {
    data(list = datanames, package = "OMICsPCAdata")
}

# Fallback for multi_assay if not loaded from data()
if (!exists("multi_assay")) {
    anno <- system.file("extdata/annotation2/TSS_groups.bed", package = "OMICsPCAdata")
    list_file <- system.file("extdata/annotation2/TSS_list", package = "OMICsPCAdata")
    fact <- system.file("extdata/factors2/demofactor", package = "OMICsPCAdata")
    
    all_cells <- prepare_dataset(factdir = fact, annofile = anno, annolist = list_file)
    assaylist <- list("demofactor" = all_cells)
    multi_assay <- MultiAssayExperiment(experiments = assaylist)
}

saveRDS(multi_assay, "multi_assay.rds")

# Fallback for groupinfo if not loaded from data()
if (!exists("groupinfo")) {
    groupinfo <- data.frame(
        Group = rep(c("Group1", "Group2"), length.out = nrow(multi_assay[[1]]))
    )
    rownames(groupinfo) <- rownames(multi_assay[[1]])
}

saveRDS(groupinfo, "groupinfo.rds")