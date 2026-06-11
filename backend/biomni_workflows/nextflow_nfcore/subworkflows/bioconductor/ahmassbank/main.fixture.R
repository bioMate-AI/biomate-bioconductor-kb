# Generate synthetic intensity.csv
intensity_data <- data.frame(
  feature_id = c("mz1", "mz2", "mz3"),
  sample_1 = c(100.5, 200.1, 50.2),
  sample_2 = c(110.2, 190.5, 60.1),
  sample_3 = c(95.4, 210.3, 45.8)
)
write.csv(intensity_data, "intensity.csv", row.names = FALSE)

# Generate synthetic coldata.csv
coldata_data <- data.frame(
  sample_id = c("sample_1", "sample_2", "sample_3"),
  group = c("Control", "Treatment", "Control")
)
write.csv(coldata_data, "coldata.csv", row.names = FALSE)