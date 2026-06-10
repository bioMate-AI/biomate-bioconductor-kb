suppressPackageStartupMessages({
  library(gDR)
  library(gDRimport)
})

expected_files <- c(
  "manifest.xlsx", 
  "Template_7daytreated.xlsx", 
  "Template_Untreated.xlsx", 
  "RawData_day0.xlsx", 
  "RawData_day7.xlsx"
)

# Attempt to use the vignette's exact data retrieval method
tryCatch({
  td <- get_test_data()
  
  m_path <- manifest_path(td)
  if (length(m_path) > 0 && file.exists(m_path[1])) {
    file.copy(m_path[1], basename(m_path[1]), overwrite = TRUE)
  }
  
  t_paths <- template_path(td)
  for (p in t_paths) {
    if (file.exists(p)) file.copy(p, basename(p), overwrite = TRUE)
  }
  
  r_paths <- result_path(td)
  for (p in r_paths) {
    if (file.exists(p)) file.copy(p, basename(p), overwrite = TRUE)
  }
}, error = function(e) NULL)

# Fallback: search for the files directly in the package's extdata directory
for (ef in expected_files) {
  if (!file.exists(ef)) {
    found <- list.files(
      system.file("extdata", package = "gDRimport"), 
      pattern = paste0("^", ef, "$"), 
      recursive = TRUE, 
      full.names = TRUE
    )
    if (length(found) > 0) {
      file.copy(found[1], ef, overwrite = TRUE)
    }
  }
}