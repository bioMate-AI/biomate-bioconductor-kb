# Pavian Shiny App for Galaxy IT
library(pavian)

# Get data directory from environment
data_dir <- Sys.getenv("DATA_DIR", "/import")

# Run Pavian with data directory pre-configured
pavian::runApp(
  host = "0.0.0.0",
  port = as.integer(Sys.getenv("SHINY_PORT", 3838)),
  launch.browser = FALSE,
  server_dir = data_dir
)
