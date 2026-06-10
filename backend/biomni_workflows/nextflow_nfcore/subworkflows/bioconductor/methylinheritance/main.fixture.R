library(methylInheritance)
library(methylKit)

# Load the multigenerational dataset provided by the package
data(demoForTransgenerationalAnalysis)

# The dataset is a list of methylRawList objects, one per generation.
# Generation 1 (F1) is at index 1, Generation 2 (F2) is at index 2.
# Based on getTreatment(), controls (0) are at indices 1-6, cases (1) are at indices 7-12.

# Extract data frames for the required files and write them as tab-separated text files
# F1 Control 01
f1_ctrl <- getData(demoForTransgenerationalAnalysis[[1]][[1]])
write.table(f1_ctrl, file = "F1_control_01.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# F1 Case 01
f1_case <- getData(demoForTransgenerationalAnalysis[[1]][[7]])
write.table(f1_case, file = "F1_case_01.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# F2 Control 01
f2_ctrl <- getData(demoForTransgenerationalAnalysis[[2]][[1]])
write.table(f2_ctrl, file = "F2_control_01.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# F2 Case 01
f2_case <- getData(demoForTransgenerationalAnalysis[[2]][[7]])
write.table(f2_case, file = "F2_case_01.txt", sep = "\t", quote = FALSE, row.names = FALSE)