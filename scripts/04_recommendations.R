# 04_recommendations.R
# Read composite score and produce behavioral recommendations

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(glue)
})

project_root <- getwd()
outputs_dir <- file.path(project_root, "outputs")
if (!dir.exists(outputs_dir)) dir.create(outputs_dir, recursive = TRUE)

final_health_score <- readr::read_csv(file.path(outputs_dir, "composite_health_score.csv"))

recommendations <- final_health_score %>%
  mutate(
    Recommendation = case_when(
      Tier == "High Performance" ~ "Excellent overall activity and recovery balance. Maintain current routine, ensure adequate sleep consistency, and avoid prolonged sedentary periods.",
      Tier == "Maintenance" ~ "Activity levels are moderate but below optimal. Increase daily step count, reduce sedentary time, and aim for more very active minutes to improve health resilience.",
      Tier == "Recovery Needed" ~ "Low activity levels and/or excessive sedentary time detected. Prioritize gradual movement, structured sleep schedules, and short active breaks throughout the day.",
      TRUE ~ "No recommendation available"
    )
  )

# Save
readr::write_csv(recommendations, file.path(outputs_dir, "behavioral_recommendations.csv"))
message(glue::glue("Saved recommendations to {outputs_dir}/behavioral_recommendations.csv"))
