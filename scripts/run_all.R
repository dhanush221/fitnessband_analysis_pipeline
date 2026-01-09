# run_all.R
# Simple script to run the pipeline top-to-bottom

scripts <- list(
  "scripts/01_data_loading.R",
  "scripts/02_eda.R",
  "scripts/03_scoring_model.R",
  "scripts/04_recommendations.R"
)

for (s in scripts) {
  message("Running: ", s)
  source(s)
}
message("Pipeline finished. Check /outputs and /figures.")
