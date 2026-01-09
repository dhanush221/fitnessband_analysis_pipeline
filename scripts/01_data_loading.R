# 01_data_loading.R
# Load and preprocess raw Fitabase CSVs and save processed RDS files

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(lubridate)
  library(glue)
})

# Paths
project_root <- getwd()
message(glue::glue("Project root resolved to: {project_root}"))
# Prefer project-relative data folder, fall back to here::here()
data_raw_dir <- file.path(project_root, "data", "raw", "Fitabase Data 3.12.16-4.11.16")
if (!dir.exists(data_raw_dir)) {
  data_raw_dir <- here::here("data", "raw", "Fitabase Data 3.12.16-4.11.16")
}
processed_dir <- file.path(project_root, "data", "processed")
if (!dir.exists(processed_dir)) dir.create(processed_dir, recursive = TRUE)

# Helper: check file exists
check_file <- function(path) {
  if (!file.exists(path)) stop(glue::glue("Required file not found: {path}"))
}

# Files
daily_file <- file.path(data_raw_dir, "dailyActivity_merged.csv")
hourly_file <- file.path(data_raw_dir, "hourlySteps_merged.csv")
minute_sleep_file <- file.path(data_raw_dir, "minuteSleep_merged.csv")
weight_file <- file.path(data_raw_dir, "weightLogInfo_merged.csv")

check_file(daily_file)
check_file(hourly_file)
check_file(minute_sleep_file)
check_file(weight_file)

# Read & parse
daily_activity <- readr::read_csv(daily_file, show_col_types = FALSE) %>%
  mutate(ActivityDate = as.Date(ActivityDate, "%m/%d/%Y"))

hourly_steps <- readr::read_csv(hourly_file, show_col_types = FALSE) %>%
  mutate(ActivityHour = as.POSIXct(ActivityHour, format = "%m/%d/%Y %I:%M:%S %p", tz = "UTC"))

minute_sleep <- readr::read_csv(minute_sleep_file, show_col_types = FALSE) %>%
  mutate(date = as.POSIXct(date, format = "%m/%d/%Y %I:%M:%S %p", tz = "UTC"))

weight_log <- readr::read_csv(weight_file, show_col_types = FALSE)

# Save processed objects for downstream scripts
readr::write_rds(daily_activity, file.path(processed_dir, "daily_activity.rds"))
readr::write_rds(hourly_steps, file.path(processed_dir, "hourly_steps.rds"))
readr::write_rds(minute_sleep, file.path(processed_dir, "minute_sleep.rds"))
readr::write_rds(weight_log, file.path(processed_dir, "weight_log.rds"))

message(glue::glue("Saved processed data to {processed_dir}"))
message(glue::glue("Daily: {nrow(daily_activity)} rows, Hourly: {nrow(hourly_steps)} rows, Minute Sleep: {nrow(minute_sleep)} rows"))

# Save session info for reproducibility
readr::write_lines(capture.output(sessionInfo()), file.path(processed_dir, "sessionInfo.txt"))
