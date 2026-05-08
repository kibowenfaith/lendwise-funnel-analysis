-- ============================================================
-- LendWise Loan Platform  |  Funnel Analysis
-- Project : SQL Funnel Analysis – Fintech Loan Platform
-- ============================================================
-- WHAT THIS SCRIPT DOES
-- Analyses the 5-stage loan application funnel to identify:
--   1. Volume and drop-off rate at each stage
--   2. Overall funnel conversion rate
--   3. The single biggest drop-off point
--   4. Monthly funnel trends across 2023
--   5. Stage-by-stage conversion heatmap by month
-- ============================================================

USE LendWise;
GO


-- ============================================================
-- QUERY 1 : Overall Funnel – Volume & Drop-off Per Stage
-- ============================================================
-- Uses a CTE to count how many applications reached each stage,
-- then calculates:
--   • drop_off_count  : how many were lost at this stage
--   • stage_conv_rate : % who passed THIS stage (vs previous)
--   • overall_conv    : % of all submitted apps that reached here
-- ============================================================

WITH funnel_stages AS (

    SELECT
        stage,

        -- Define the display order of stages
        CASE stage
            WHEN 'submitted'    THEN 1
            WHEN 'under_review' THEN 2
            WHEN 'verified'     THEN 3
            WHEN 'approved'     THEN 4
            WHEN 'disbursed'    THEN 5
        END AS stage_order,

        COUNT(DISTINCT application_id) AS applications_reached

    FROM application_events
    GROUP BY stage
),

funnel_ordered AS (

    SELECT
        stage_order,
        stage,
        applications_reached,

        -- Previous stage count using LAG window function
        LAG(applications_reached) OVER (ORDER BY stage_order) AS prev_stage_count,

        -- Total at top of funnel (submitted) for overall conversion
        FIRST_VALUE(applications_reached) OVER (ORDER BY stage_order
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS top_of_funnel

    FROM funnel_stages
)

SELECT
    stage_order,

    -- Clean stage name for display
    REPLACE(stage, '_', ' ')                                        AS stage_name,

    applications_reached,

    -- How many dropped off at this stage
    COALESCE(prev_stage_count - applications_reached, 0)            AS drop_off_count,

    -- Stage-to-stage conversion rate (e.g. submitted → under_review)
    CASE
        WHEN prev_stage_count IS NULL THEN 100.00
        ELSE ROUND(
            CAST(applications_reached AS FLOAT)
            / CAST(prev_stage_count   AS FLOAT) * 100, 1)
    END                                                             AS stage_conv_rate_pct,

    -- Overall conversion from top of funnel
    ROUND(
        CAST(applications_reached AS FLOAT)
        / CAST(top_of_funnel      AS FLOAT) * 100, 1)              AS overall_conv_rate_pct

FROM funnel_ordered
ORDER BY stage_order;
GO


-- ============================================================
-- QUERY 2 : Biggest Drop-off Stage
-- ============================================================
-- Pinpoints the single stage with the highest volume loss.
-- This is the answer to the exec question:
-- "Where should we focus our improvement efforts first?"
-- ============================================================

WITH funnel_stages AS (
    SELECT
        stage,
        CASE stage
            WHEN 'submitted'    THEN 1
            WHEN 'under_review' THEN 2
            WHEN 'verified'     THEN 3
            WHEN 'approved'     THEN 4
            WHEN 'disbursed'    THEN 5
        END AS stage_order,
        COUNT(DISTINCT application_id) AS applications_reached
    FROM application_events
    GROUP BY stage
),

with_lag AS (
    SELECT
        stage_order,
        stage,
        applications_reached,
        LAG(applications_reached) OVER (ORDER BY stage_order) AS prev_count
    FROM funnel_stages
),

drop_offs AS (
    SELECT
        stage_order,
        REPLACE(stage, '_', ' ')        AS stage_name,
        applications_reached,
        prev_count,
        (prev_count - applications_reached) AS lost_applicants,
        ROUND(
            CAST(prev_count - applications_reached AS FLOAT)
            / CAST(prev_count AS FLOAT) * 100, 1)             AS pct_lost
    FROM with_lag
    WHERE prev_count IS NOT NULL
)

SELECT TOP 1
    stage_name                          AS biggest_drop_off_stage,
    prev_count                          AS entered_stage,
    applications_reached                AS passed_stage,
    lost_applicants,
    pct_lost                            AS pct_of_stage_lost,
    'PRIORITY ACTION REQUIRED'          AS flag
FROM drop_offs
ORDER BY lost_applicants DESC;
GO


-- ============================================================
-- QUERY 3 : Full Funnel Summary (Single Row KPI Output)
-- ============================================================
-- Produces one summary row useful for an executive report or
-- dashboard card. Shows top-level funnel health at a glance.
-- ============================================================

WITH stage_counts AS (
    SELECT
        COUNT(DISTINCT CASE WHEN stage = 'submitted'    THEN application_id END) AS submitted,
        COUNT(DISTINCT CASE WHEN stage = 'under_review' THEN application_id END) AS under_review,
        COUNT(DISTINCT CASE WHEN stage = 'verified'     THEN application_id END) AS verified,
        COUNT(DISTINCT CASE WHEN stage = 'approved'     THEN application_id END) AS approved,
        COUNT(DISTINCT CASE WHEN stage = 'disbursed'    THEN application_id END) AS disbursed
    FROM application_events
)

SELECT
    submitted                                           AS total_applications,
    under_review,
    verified,
    approved,
    disbursed                                           AS total_disbursed,

    -- End-to-end conversion: submitted → disbursed
    ROUND(CAST(disbursed  AS FLOAT) / CAST(submitted AS FLOAT) * 100, 1)
                                                        AS end_to_end_conv_pct,

    -- Lost applications (never disbursed)
    submitted - disbursed                               AS total_lost,

    ROUND(CAST(submitted - disbursed AS FLOAT)
          / CAST(submitted AS FLOAT) * 100, 1)         AS pct_lost_overall

FROM stage_counts;
GO


-- ============================================================
-- QUERY 4 : Monthly Funnel Volume Trend (2023)
-- ============================================================
-- Shows how funnel volume changed month-by-month.
-- Useful for spotting seasonal patterns or campaign effects.
-- Includes a full-year average benchmark row at the bottom
-- so any monthly anomaly can be compared against it directly.
-- e.g. Sep 2023 (18.8%) is clearly below the 37.4% average.
-- ============================================================

WITH monthly_submitted AS (
    SELECT
        YEAR(event_timestamp)               AS yr,
        MONTH(event_timestamp)              AS mth,
        FORMAT(event_timestamp, 'MMM yyyy') AS month_label,
        COUNT(DISTINCT application_id)      AS applications_submitted
    FROM application_events
    WHERE stage = 'submitted'
    GROUP BY
        YEAR(event_timestamp),
        MONTH(event_timestamp),
        FORMAT(event_timestamp, 'MMM yyyy')
),

monthly_disbursed AS (
    SELECT
        YEAR(event_timestamp)               AS yr,
        MONTH(event_timestamp)              AS mth,
        COUNT(DISTINCT application_id)      AS applications_disbursed
    FROM application_events
    WHERE stage = 'disbursed'
    GROUP BY
        YEAR(event_timestamp),
        MONTH(event_timestamp)
),

monthly_combined AS (
    SELECT
        s.yr,
        s.mth,
        s.month_label,
        s.applications_submitted,
        COALESCE(d.applications_disbursed, 0)               AS applications_disbursed,

        -- Month-over-month change in submissions
        s.applications_submitted
            - LAG(s.applications_submitted)
              OVER (ORDER BY s.yr, s.mth)                   AS mom_change,

        -- Rolling 3-month average submissions
        ROUND(AVG(CAST(s.applications_submitted AS FLOAT))
            OVER (ORDER BY s.yr, s.mth
                  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
                                                            AS rolling_3m_avg,

        -- Monthly conversion rate
        ROUND(
            CAST(COALESCE(d.applications_disbursed, 0) AS FLOAT)
            / CAST(s.applications_submitted AS FLOAT) * 100, 1)
                                                            AS monthly_conv_pct

    FROM monthly_submitted  s
    LEFT JOIN monthly_disbursed d
        ON s.yr  = d.yr
       AND s.mth = d.mth

    -- 2023 only (excludes the partial Jan 2024 edge row)
    WHERE s.yr = 2023
)

-- ── Monthly rows ──────────────────────────────────────────────
SELECT
    month_label                             AS period,
    applications_submitted,
    applications_disbursed,
    mom_change,
    rolling_3m_avg,
    monthly_conv_pct,
    0                                       AS sort_order   -- monthly rows first
FROM monthly_combined

UNION ALL

-- ── Full-year average row (benchmark) ────────────────────────
-- Computed directly from the monthly rows above.
-- This is the source of any "average" referenced in analysis.
SELECT
    'Full-year avg (2023)'                  AS period,
    NULL, NULL, NULL, NULL,
    ROUND(AVG(monthly_conv_pct), 1)         AS monthly_conv_pct,
    1                                       AS sort_order   -- benchmark row last
FROM monthly_combined

ORDER BY
    sort_order,
    period;
GO


-- ============================================================
-- QUERY 5 : Stage Conversion Heatmap by Month
-- ============================================================
-- For each month, shows how many applications reached each
-- stage. Helps answer: "Did our verification bottleneck get
-- worse in Q3 compared to Q1?"
-- ============================================================

SELECT
    FORMAT(event_timestamp, 'MMM yyyy')                 AS month_label,
    MONTH(event_timestamp)                              AS mth_num,

    COUNT(DISTINCT CASE WHEN stage = 'submitted'    THEN application_id END) AS submitted,
    COUNT(DISTINCT CASE WHEN stage = 'under_review' THEN application_id END) AS under_review,
    COUNT(DISTINCT CASE WHEN stage = 'verified'     THEN application_id END) AS verified,
    COUNT(DISTINCT CASE WHEN stage = 'approved'     THEN application_id END) AS approved,
    COUNT(DISTINCT CASE WHEN stage = 'disbursed'    THEN application_id END) AS disbursed,

    -- Monthly end-to-end conversion
    ROUND(
        CAST(COUNT(DISTINCT CASE WHEN stage = 'disbursed' THEN application_id END) AS FLOAT)
        / NULLIF(COUNT(DISTINCT CASE WHEN stage = 'submitted' THEN application_id END), 0)
        * 100, 1)                                       AS monthly_end_to_end_pct

FROM application_events
GROUP BY
    FORMAT(event_timestamp, 'MMM yyyy'),
    MONTH(event_timestamp),
    YEAR(event_timestamp)
ORDER BY
    YEAR(event_timestamp),
    MONTH(event_timestamp);
GO