# 03_scoring_model.R
# Compute comparison to ideal benchmarks and composite health score

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(glue)
  library(ggplot2)
})

project_root <- getwd()
processed_dir <- file.path(project_root, "data", "processed")
outputs_dir <- file.path(project_root, "outputs")
visuals_dir <- file.path(project_root, "visuals")
if (!dir.exists(outputs_dir)) dir.create(outputs_dir, recursive = TRUE)
if (!dir.exists(visuals_dir)) dir.create(visuals_dir, recursive = TRUE)

daily_activity <- readr::read_rds(file.path(processed_dir, "daily_activity.rds"))
minute_sleep <- readr::read_rds(file.path(processed_dir, "minute_sleep.rds"))

# Build daily sleep summary
daily_sleep <- minute_sleep %>%
  mutate(Date = as.Date(date)) %>%
  group_by(Id, Date) %>%
  summarise(Sleep_Minutes = n(), Sleep_Hours = n() / 60, .groups = "drop")

# User averages
user_activity_profile <- daily_activity %>%
  summarise(
    Steps = mean(TotalSteps, na.rm = TRUE),
    Calories = mean(Calories, na.rm = TRUE),
    Distance_km = mean(TotalDistance, na.rm = TRUE),
    Very_Active_Min = mean(VeryActiveMinutes, na.rm = TRUE),
    Fairly_Active_Min = mean(FairlyActiveMinutes, na.rm = TRUE),
    Sedentary_Min = mean(SedentaryMinutes, na.rm = TRUE)
  )

user_sleep_profile <- daily_sleep %>% summarise(Sleep_Hours = mean(Sleep_Hours, na.rm = TRUE))

user_profile <- bind_cols(user_activity_profile, user_sleep_profile) %>% mutate(Type = "User Average")

ideal_profile <- tibble(
  Steps = 10000,
  Calories = 2500,
  Distance_km = 7.5,
  Very_Active_Min = 30,
  Fairly_Active_Min = 30,
  Sedentary_Min = 600,
  Sleep_Hours = 8,
  Type = "Ideal Standard"
)

comparison <- bind_rows(user_profile, ideal_profile) %>% pivot_longer(cols = -Type, names_to = "Metric", values_to = "Value")

# Comparison Plot
p_comp <- ggplot(comparison, aes(x = Type, y = Value, fill = Type)) +
  geom_bar(stat = "identity", position = "dodge", width = 0.7) +
  facet_wrap(~Metric, scales = "free_y") +
  theme_minimal() +
  labs(title = "User vs. Ideal Benchmark", y = "Value", x = "") +
  scale_fill_manual(values = c("User Average" = "#3498db", "Ideal Standard" = "#2ecc71"))

ggsave(filename = file.path(visuals_dir, "user_vs_ideal.png"), plot = p_comp, width = 10, height = 6)

scored_comparison <- comparison %>%
  pivot_wider(names_from = Type, values_from = Value) %>%
  mutate(Performance_Percent = round((`User Average` / `Ideal Standard`) * 100, 1))

composite_health_score <- scored_comparison %>%
  mutate(
    Normalized_Score = case_when(
      Metric == "Steps" ~ pmin((`User Average` / `Ideal Standard`) * 100, 100),
      Metric == "Distance_km" ~ pmin((`User Average` / `Ideal Standard`) * 100, 100),
      Metric == "Very_Active_Min" ~ pmin((`User Average` / `Ideal Standard`) * 100, 100),
      Metric == "Fairly_Active_Min" ~ pmin((`User Average` / `Ideal Standard`) * 100, 100),
      Metric == "Calories" ~ pmin((`User Average` / `Ideal Standard`) * 100, 100),
      Metric == "Sleep_Hours" ~ pmin((`User Average` / `Ideal Standard`) * 100, 100),
      Metric == "Sedentary_Min" ~ pmin((`Ideal Standard` / `User Average`) * 100, 100),
      TRUE ~ NA_real_
    ),
    Weight = case_when(
      Metric == "Steps" ~ 0.18,
      Metric == "Distance_km" ~ 0.07,
      Metric == "Very_Active_Min" ~ 0.15,
      Metric == "Fairly_Active_Min" ~ 0.10,
      Metric == "Sedentary_Min" ~ 0.25,
      Metric == "Calories" ~ 0.10,
      Metric == "Sleep_Hours" ~ 0.15,
      TRUE ~ NA_real_
    ),
    Weighted_Score = Normalized_Score * Weight
  )

final_health_score <- composite_health_score %>%
  summarise(Composite_Health_Score = round(sum(Weighted_Score, na.rm = TRUE), 1)) %>%
  mutate(
    Tier = case_when(
      Composite_Health_Score >= 80 ~ "High Performance",
      Composite_Health_Score >= 60 ~ "Maintenance",
      TRUE ~ "Recovery Needed"
    )
  )

# Save outputs
# Save outputs
readr::write_csv(final_health_score, file.path(outputs_dir, "composite_health_score.csv"))
readr::write_csv(comparison, file.path(outputs_dir, "scored_comparison.csv"))

message(glue::glue("Saved composite score to {outputs_dir}/composite_health_score.csv"))

# Optionally persist to PostgreSQL if env vars provided
if (tolower(Sys.getenv('WRITE_TO_DB', 'false')) %in% c('1','true','yes')) {
  message('WRITE_TO_DB enabled – writing composite score to Postgres')
  if (!requireNamespace('DBI', quietly = TRUE)) install.packages('DBI')
  if (!requireNamespace('RPostgres', quietly = TRUE)) install.packages('RPostgres')
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv('PG_HOST', 'localhost'),
    port = as.integer(Sys.getenv('PG_PORT', 5432)),
    dbname = Sys.getenv('PG_DB', 'fitdb'),
    user = Sys.getenv('PG_USER', 'fituser'),
    password = Sys.getenv('PG_PASSWORD', 'fitpass')
  )
  DBI::dbExecute(con, readr::read_file('sql/create_tables.sql'))
  DBI::dbWriteTable(con, Id(schema = 'fit', table = 'composite_health_score'), final_health_score, append = TRUE)
  DBI::dbWriteTable(con, Id(schema = 'fit', table = 'recommendations'), recommendations, append = TRUE)
  DBI::dbDisconnect(con)
  message('Composite score and recommendations written to Postgres')
} else {
  message('WRITE_TO_DB not enabled; set WRITE_TO_DB=true in your .env to enable DB writes')
}
