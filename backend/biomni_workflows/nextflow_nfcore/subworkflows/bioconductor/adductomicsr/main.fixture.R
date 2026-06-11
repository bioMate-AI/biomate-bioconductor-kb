library(adductomicsR)

# 1. mzXML files
# The vignette uses ExperimentHub to download mzXML files, but we must run offline.
# We will check if any companion packages ship mzXML files, otherwise create minimal valid synthetic mzXML files.
mzxml_content <- '<?xml version="1.0" encoding="ISO-8859-1"?>
<mzXML xmlns="http://sashimi.sourceforge.net/schema_revision/mzXML_3.2"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://sashimi.sourceforge.net/schema_revision/mzXML_3.2 http://sashimi.sourceforge.net/schema_revision/mzXML_3.2/mzXML_idx_3.2.xsd">
  <msRun scanCount="0" startTime="PT0S" endTime="PT0S">
  </msRun>
</mzXML>'

real_mzxmls <- c(
    list.files(system.file("extdata", package="adductData"), pattern="\\.mzXML$", full.names=TRUE),
    list.files(system.file("extdata", package="adductomicsR"), pattern="\\.mzXML$", full.names=TRUE)
)

if (length(real_mzxmls) > 0) {
    file.copy(real_mzxmls, ".")
} else {
    writeLines(mzxml_content, "ORB35017.mzXML")
    writeLines(mzxml_content, "ORB35022.mzXML")
}

# 2. runOrder.csv
run_order_file <- system.file("extdata", "runOrder.csv", package = "adductomicsR")
if (file.exists(run_order_file)) {
    file.copy(run_order_file, "runOrder.csv")
} else {
    write.csv(data.frame(File = c("ORB35017.mzXML", "ORB35022.mzXML"), Order = 1:2), "runOrder.csv", row.names = FALSE)
}

# 3. allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv
all_results_file <- system.file("extdata", "allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv", package = "adductomicsR")
if (file.exists(all_results_file)) {
    file.copy(all_results_file, "allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv")
} else {
    write.csv(data.frame(Adduct = "Test", Mass = 100), "allResults_ALVLIAFAQYLQQCPFEDHVK_example.csv", row.names = FALSE)
}

# 4. exampletargTable2.csv
targ_table_file <- system.file("extdata", "exampletargTable2.csv", package = "adductomicsR")
if (file.exists(targ_table_file)) {
    file.copy(targ_table_file, "exampletargTable2.csv")
} else {
    write.csv(data.frame(Adduct = "Test", Mass = 100), "exampletargTable2.csv", row.names = FALSE)
}

# 5. adductQuantResults.Rda
# Create a dummy object of class adductQuantif to satisfy the load() call
object <- list()
class(object) <- "adductQuantif"
save(object, file = "adductQuantResults.Rda")