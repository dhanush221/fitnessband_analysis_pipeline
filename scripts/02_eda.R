# 02_eda.R
# Exploratory plots and basic summaries. Saves figures to /figures.

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(ggplot2)
  library(scales)
  library(lubridate)
  library(glue)
})

project_root <- getwd()
processed_dir <- file.path(project_root, "data", "processed")
figures_dir <- file.path(project_root, "visuals")
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)

# Load data
daily_activity <- readr::read_rds(file.path(processed_dir, "daily_activity.rds"))
hourly_steps <- readr::read_rds(file.path(processed_dir, "hourly_steps.rds"))
minute_sleep <- readr::read_rds(file.path(processed_dir, "minute_sleep.rds"))

# 1) Daily Steps distribution
p_steps <- ggplot(daily_activity, aes(x = TotalSteps)) +
  geom_histogram(binwidth = 1000, fill = "#3498db", color = "white") +
  labs(title = "Distribution of Daily Steps", x = "Total Steps", y = "Frequency") +
  theme_minimal()

ggsave(filename = file.path(figures_dir, "steps_hist.png"), plot = p_steps, width = 8, height = 5)

# 2) Hourly heatmap
hourly_patterns <- hourly_steps %>%
  mutate(Hour = lubridate::hour(ActivityHour), Weekday = lubridate::wday(ActivityHour, label = TRUE)) %>%
  group_by(Weekday, Hour) %>%
  summarise(Avg_Steps = mean(StepTotal, na.rm = TRUE), .groups = "drop")

p_heatmap <- ggplot(hourly_patterns, aes(x = Hour, y = Weekday, fill = Avg_Steps)) +
  geom_tile() +
  scale_fill_gradient(low = "white", high = "#e74c3c") +
  labs(title = "Average Hourly Steps Heatmap") +
  scale_x_continuous(breaks = seq(0, 23, 2)) +
  theme_minimal()

ggsave(filename = file.path(figures_dir, "hourly_heatmap.png"), plot = p_heatmap, width = 10, height = 4)

# 3) Sleep distribution
daily_sleep <- minute_sleep %>%
  mutate(Date = as.Date(date)) %>%
  group_by(Id, Date) %>%
  summarise(Sleep_Minutes = n(), Sleep_Hours = n() / 60, .groups = "drop")

p_sleep <- ggplot(daily_sleep, aes(x = Sleep_Hours)) +
  geom_histogram(binwidth = 0.5, fill = "#8e44ad", color = "white") +
  geom_vline(xintercept = 7, linetype = "dashed", color = "red") +
  labs(title = "Distribution of Sleep Duration", x = "Sleep (Hours)") +
  theme_minimal()

ggsave(filename = file.path(figures_dir, "sleep_hist.png"), plot = p_sleep, width = 8, height = 5)

# 4) Correlation: Steps vs Sleep
# Join daily activity and minute sleep (aggregated)
# Note: In a real run we might need to handle dates more carefully if they differ, but we'll use the loaded DFs
daily_sleep_agg <- minute_sleep %>%
  mutate(Date = as.Date(date)) %>%
  group_by(Id, Date) %>%
  summarise(Sleep_Hours = n() / 60, .groups = "drop")

merged_data <- inner_join(daily_activity, daily_sleep_agg, by = c("Id", "ActivityDate" = "Date"))

p_corr <- ggplot(merged_data, aes(x = TotalSteps, y = Sleep_Hours)) +
  geom_point(alpha = 0.6, color = "#2c3e50") +
  geom_smooth(method = "lm", color = "#e67e22") +
  labs(title = "Correlation: Daily Steps vs Sleep Duration", x = "Daily Steps", y = "Sleep Hours") +
  theme_minimal()

ggsave(filename = file.path(figures_dir, "correlation_steps_sleep.png"), plot = p_corr, width = 8, height = 6)

message(glue::glue("Saved figures to {figures_dir}"))
