
library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

# 1. Load Data
# Try loading parquet, if not found (since ETL didn't run), warn user.
data_path <- "data/processed/daily_summary.parquet"
if (!file.exists(data_path)) {
  stop("Processed data file not found. Please run the Python ETL pipeline first.")
}

daily_data <- read_parquet(data_path)

# 2. Calculate User Average Profile
# We assume the dataset represents 'The User'
user_profile <- daily_data %>%
  summarise(
    Steps = mean(steps, na.rm = TRUE),
    Calories = mean(calories, na.rm = TRUE),
    Sleep_Hours = mean(sleep_hours, na.rm = TRUE)
  ) %>%
  mutate(Type = "User Average")

# 3. Define Ideal Healthy Profile
ideal_profile <- data.frame(
  Steps = 10000,
  Calories = 2500,
  Sleep_Hours = 8,
  Type = "Ideal Healthy"
)

# 4. Combine and Reshape for Plotting
comparison_df <- bind_rows(user_profile, ideal_profile) %>%
  pivot_longer(cols = c(Steps, Calories, Sleep_Hours), names_to = "Metric", values_to = "Value")

# 5. Visualization: User vs Ideal
# We use 'scales = "free_y"' because Steps (10k) and Sleep (8) have very different scales
p <- ggplot(comparison_df, aes(x = Type, y = Value, fill = Type)) +
  geom_bar(stat = "identity", position = "dodge", width = 0.7) +
  facet_wrap(~Metric, scales = "free_y") +
  theme_minimal() +
  labs(
    title = "User vs. Ideal Healthy Person Comparison",
    subtitle = "Comparing average daily metrics against healthy benchmarks",
    y = "Value",
    x = ""
  ) +
  scale_fill_manual(values = c("User Average" = "#3498db", "Ideal Healthy" = "#2ecc71")) +
  theme(legend.position = "bottom")

# Save Plot
dir.create("visuals", showWarnings = FALSE)
ggsave("visuals/user_vs_ideal_comparison.png", plot = p, width = 8, height = 6)

print("Comparison plot saved to visuals/user_vs_ideal_comparison.png")
