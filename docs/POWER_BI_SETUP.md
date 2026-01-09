# Power BI Setup & Day Simulation Guide

This guide explains how to connect Power BI to your compiled dataset and how to use the **Day Simulation** feature to watch your dashboard update over time.

## 1. Prerequisites

- **Docker Desktop** is running.
- **Power BI Desktop** is installed.
- Database is up:
  ```powershell
  docker compose up -d
  ```

## 2. Connect Power BI to Database

1.  Open **Power BI Desktop**.
2.  Click **Get Data** -> **More...**
3.  Search for **PostgreSQL database** and select it.
4.  Enter connection details:
    - **Server**: `localhost`
    - **Database**: `fitdb`
    - **Data Connectivity mode**: **DirectQuery** (Important for seeing live updates!)
5.  Click **OK**.
6.  When prompted for credentials:
    - **User**: `fituser`
    - **Password**: `fitpass`
7.  In the Navigator:
    - Expand `fitdb` -> `fit`.
    - Select **`vw_analysis_master`** (This is the pre-joined view created for you).
    - Click **Load**.

## 3. Creating Visuals

You can now drag fields from `fit vw_analysis_master` to create charts:
- **X-Axis**: `date`
- **Y-Axis**: `total_steps`, `sleep_hours`
- **Legend/Category**: `id`

## 4. The "Day-by-Day" Simulation

Your data pipeline supports a "Simulation Mode" where you can release data one day at a time, allowing you to watch your Power BI dashboard "evolve."

**How to run it:**

1.  Open your terminal to the project folder.
2.  Run the simulation script:
    ```powershell
    .\scripts\simulate_day.ps1
    ```
3.  **Check Power BI**: Click the **"Refresh"** button in the Home ribbon (or if using DirectQuery, just interact with the report).
4.  **Repeat**: Run the script again to advance to the next day.

**Note**: To restart the simulation from the beginning, delete the `data/processed` folder and `etl/state.json`, then run the script again.

## 5. Advanced Visuals: Sleep Tier & Comparisons

To visualize the **Comparison to Ideal** and **Sleep Tier**:

1.  **Load New Tables**:
    - Click **Transform Data** or right-click the database connection.
    - Select **`scored_comparison`** and **`composite_health_score`** (or `recommendations`).
    - Load them.

2.  **Comparison Bar Chart (User vs Ideal)**:
    - **Visual**: Clustered Bar Chart.
    - **X-Axis**: `value` (from `scored_comparison`).
    - **Y-Axis**: `metric`.
    - **Legend**: `type` (e.g., "User Average" vs "Ideal Standard").
    - *Insight*: See directly how your average stacks up against the recommended 8 hours of sleep or 10k steps.

3.  **Sleep Tier Card**:
    - **Visual**: Card or Multi-row Card.
    - **Fields**: `tier` from `composite_health_score`.
    - *Note*: This tier updates as the simulation runs!
