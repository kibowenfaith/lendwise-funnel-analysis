-- ============================================================
-- LendWise Loan Platform  |  KPI Summary View
-- Project : SQL Funnel Analysis – Fintech Loan Platform
-- ============================================================
-- WHAT THIS SCRIPT DOES
-- Creates reusable SQL VIEWs that consolidate all KPIs into
-- single queryable objects. Views are used instead of
-- repeating complex queries every time a report is refreshed.
--
-- Views created:
--   1. vw_funnel_kpi_summary     – top-level funnel health
--   2. vw_stage_dropoff          – drop-off rate per stage
--   3. vw_channel_performance    – conversion + volume by channel
--   4. vw_segment_conversion     – loan type conversion summary
--   5. vw_executive_dashboard    – single-row exec snapshot
--
-- HOW TO USE
-- After running this script, query any view like a table:
--   SELECT * FROM vw_funnel_kpi_summary;
--   SELECT * FROM vw_executive_dashboard;
-- These views can be connected directly to Power BI or Excel.
-- ============================================================

USE LendWise;
GO

-- ── Drop views if re-running ──────────────────────────────────
IF OBJECT_ID('vw_executive_dashboard',  'V') IS NOT NULL DROP VIEW vw_executive_dashboard;
IF OBJECT_ID('vw_funnel_kpi_summary',   'V') IS NOT NULL DROP VIEW vw_funnel_kpi_summary;
IF OBJECT_ID('vw_stage_dropoff',        'V') IS NOT NULL DROP VIEW vw_stage_dropoff;
IF OBJECT_ID('vw_channel_performance',  'V') IS NOT NULL DROP VIEW vw_channel_performance;
IF OBJECT_ID('vw_segment_conversion',   'V') IS NOT NULL DROP VIEW vw_segment_conversion;
GO


-- ============================================================
-- VIEW 1 : vw_funnel_kpi_summary
-- ============================================================
-- One row per funnel stage showing volume, drop-off,
-- and conversion rates. The foundation of the funnel report.
-- ============================================================
CREATE VIEW vw_funnel_kpi_summary AS

WITH stage_counts AS (
    SELECT
        stage,
        CASE stage
            WHEN 'submitted'    THEN 1
            WHEN 'under_review' THEN 2
            WHEN 'verified'     THEN 3
            WHEN 'approved'     THEN 4
            WHEN 'disbursed'    THEN 5
        END                                                 AS stage_order,
        COUNT(DISTINCT application_id)                      AS applications_reached
    FROM application_events
    GROUP BY stage
),

funnel_with_lag AS (
    SELECT
        stage_order,
        stage,
        applications_reached,
        LAG(applications_reached) OVER (ORDER BY stage_order) AS prev_stage_count,
        FIRST_VALUE(applications_reached) OVER (
            ORDER BY stage_order
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )                                                   AS top_of_funnel
    FROM stage_counts
)

SELECT
    stage_order,
    REPLACE(stage, '_', ' ')                                AS stage_name,
    applications_reached,
    COALESCE(prev_stage_count - applications_reached, 0)    AS dropped_at_stage,

    -- Stage-to-stage conversion rate
    CASE
        WHEN prev_stage_count IS NULL THEN 100.00
        ELSE ROUND(
            CAST(applications_reached AS FLOAT)
            / CAST(prev_stage_count   AS FLOAT) * 100, 1)
    END                                                     AS stage_conv_rate_pct,

    -- Overall conversion from submitted
    ROUND(
        CAST(applications_reached AS FLOAT)
        / CAST(top_of_funnel      AS FLOAT) * 100, 1)      AS overall_conv_rate_pct

FROM funnel_with_lag;
GO


-- ============================================================
-- VIEW 2 : vw_stage_dropoff
-- ============================================================
-- Focuses purely on where and how many applicants are lost.
-- Ranks stages by drop-off severity so the biggest problem
-- is always at the top when queried.
-- ============================================================
CREATE VIEW vw_stage_dropoff AS

WITH stage_counts AS (
    SELECT
        stage,
        CASE stage
            WHEN 'submitted'    THEN 1
            WHEN 'under_review' THEN 2
            WHEN 'verified'     THEN 3
            WHEN 'approved'     THEN 4
            WHEN 'disbursed'    THEN 5
        END                                                 AS stage_order,
        COUNT(DISTINCT application_id)                      AS applications_reached
    FROM application_events
    GROUP BY stage
),

with_lag AS (
    SELECT
        stage_order,
        stage,
        applications_reached,
        LAG(applications_reached) OVER (ORDER BY stage_order) AS prev_count
    FROM stage_counts
)

SELECT
    stage_order,
    REPLACE(stage, '_', ' ')                                AS stage_name,
    prev_count                                              AS entered_stage,
    applications_reached                                    AS passed_stage,
    (prev_count - applications_reached)                     AS lost_applicants,
    ROUND(
        CAST(prev_count - applications_reached AS FLOAT)
        / CAST(prev_count AS FLOAT) * 100, 1)              AS pct_lost,
    RANK() OVER (
        ORDER BY (prev_count - applications_reached) DESC
    )                                                       AS severity_rank
FROM with_lag
WHERE prev_count IS NOT NULL;
GO


-- ============================================================
-- VIEW 3 : vw_channel_performance
-- ============================================================
-- Summarises each acquisition channel's contribution:
-- volume, conversion rate, and quality of leads.
-- Useful for marketing budget allocation decisions.
-- ============================================================
CREATE VIEW vw_channel_performance AS

WITH app_outcome AS (
    SELECT
        la.application_id,
        ap.acquisition_channel,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved,
        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed
    FROM loan_applications  la
    JOIN application_events ae ON la.application_id = ae.application_id
    JOIN applicants          ap ON la.applicant_id   = ap.applicant_id
    GROUP BY la.application_id, ap.acquisition_channel
)

SELECT
    REPLACE(acquisition_channel, '_', ' ')                  AS channel,
    COUNT(*)                                                AS total_applications,
    SUM(is_approved)                                        AS approved,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    -- Share of total application volume
    ROUND(CAST(COUNT(*) AS FLOAT)
          / SUM(COUNT(*)) OVER () * 100, 1)                AS volume_share_pct,

    -- Channel quality score: conversion vs overall average
    ROUND(
        CAST(SUM(is_disbursed) AS FLOAT) / CAST(COUNT(*) AS FLOAT) * 100
        - SUM(CAST(SUM(is_disbursed) AS FLOAT)) OVER ()
          / SUM(CAST(COUNT(*) AS FLOAT)) OVER () * 100
    , 1)                                                    AS conv_vs_avg_pct,

    RANK() OVER (
        ORDER BY CAST(SUM(is_disbursed) AS FLOAT)
                 / CAST(COUNT(*) AS FLOAT) DESC
    )                                                       AS quality_rank

FROM app_outcome
GROUP BY acquisition_channel;
GO


-- ============================================================
-- VIEW 4 : vw_segment_conversion
-- ============================================================
-- Conversion rates broken down by loan type, with avg loan
-- amount and total disbursed value.
-- Ready for use in a product performance dashboard.
-- ============================================================
CREATE VIEW vw_segment_conversion AS

WITH app_outcome AS (
    SELECT
        la.application_id,
        la.loan_type,
        la.loan_amount,
        MAX(CASE WHEN ae.stage = 'verified'  THEN 1 ELSE 0 END) AS is_verified,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved,
        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed
    FROM loan_applications  la
    JOIN application_events ae ON la.application_id = ae.application_id
    GROUP BY la.application_id, la.loan_type, la.loan_amount
)

SELECT
    REPLACE(loan_type, '_', ' ')                            AS loan_type,
    COUNT(*)                                                AS total_applications,
    SUM(is_verified)                                        AS verified,
    SUM(is_approved)                                        AS approved,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    ROUND(AVG(CAST(loan_amount AS FLOAT)), 0)               AS avg_loan_amount,

    SUM(CASE WHEN is_disbursed = 1
             THEN loan_amount ELSE 0 END)                   AS total_value_disbursed,

    RANK() OVER (
        ORDER BY CAST(SUM(is_disbursed) AS FLOAT)
                 / CAST(COUNT(*) AS FLOAT) DESC
    )                                                       AS conv_rank

FROM app_outcome
GROUP BY loan_type;
GO


-- ============================================================
-- VIEW 5 : vw_executive_dashboard
-- ============================================================
-- Single-row snapshot of the entire funnel.
-- This is what goes on page 1 of an executive report —
-- the 6 numbers a Head of Growth or CFO wants to see
-- at a glance without reading a full analysis.
-- ============================================================
CREATE VIEW vw_executive_dashboard AS

WITH stage_counts AS (
    SELECT
        COUNT(DISTINCT CASE WHEN stage = 'submitted'    THEN application_id END) AS submitted,
        COUNT(DISTINCT CASE WHEN stage = 'under_review' THEN application_id END) AS under_review,
        COUNT(DISTINCT CASE WHEN stage = 'verified'     THEN application_id END) AS verified,
        COUNT(DISTINCT CASE WHEN stage = 'approved'     THEN application_id END) AS approved,
        COUNT(DISTINCT CASE WHEN stage = 'disbursed'    THEN application_id END) AS disbursed
    FROM application_events
),

-- Step 1: calculate each application's individual journey duration
journey_per_app AS (
    SELECT
        application_id,
        DATEDIFF(DAY,
            MIN(CASE WHEN stage = 'submitted' THEN event_timestamp END),
            MAX(CASE WHEN stage = 'disbursed' THEN event_timestamp END)
        )                                                   AS days_to_disburse
    FROM application_events
    GROUP BY application_id
    HAVING
        MIN(CASE WHEN stage = 'submitted' THEN event_timestamp END) IS NOT NULL
    AND MAX(CASE WHEN stage = 'disbursed' THEN event_timestamp END) IS NOT NULL
),

-- Step 2: average across all completed journeys separately
-- This avoids nesting AVG inside AVG which SQL Server forbids
journey_avg AS (
    SELECT
        ROUND(AVG(CAST(days_to_disburse AS FLOAT)), 1)     AS avg_days_to_disburse
    FROM journey_per_app
),

revenue AS (
    SELECT
        SUM(CASE WHEN ae_check.is_disbursed = 1 THEN la.loan_amount ELSE 0 END)
                                                            AS total_disbursed_value,
        SUM(CASE WHEN ae_check.is_disbursed = 0 THEN la.loan_amount ELSE 0 END)
                                                            AS pipeline_at_risk
    FROM loan_applications la
    JOIN (
        SELECT
            application_id,
            MAX(CASE WHEN stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed
        FROM application_events
        GROUP BY application_id
    ) ae_check ON la.application_id = ae_check.application_id
)

SELECT
    -- Volume KPIs
    sc.submitted                                            AS total_applications,
    sc.disbursed                                            AS total_disbursed,
    sc.submitted - sc.disbursed                             AS total_lost,

    -- Conversion KPIs
    ROUND(CAST(sc.disbursed  AS FLOAT)
          / CAST(sc.submitted AS FLOAT) * 100, 1)          AS end_to_end_conv_pct,
    ROUND(CAST(sc.submitted - sc.disbursed AS FLOAT)
          / CAST(sc.submitted AS FLOAT) * 100, 1)          AS overall_dropoff_pct,

    -- Speed KPI (pre-computed cleanly in journey_avg CTE)
    ja.avg_days_to_disburse,

    -- Revenue KPIs
    r.total_disbursed_value,
    r.pipeline_at_risk

FROM stage_counts sc
CROSS JOIN journey_avg ja
CROSS JOIN revenue     r;
GO


-- ============================================================
-- VERIFICATION : Query all views to confirm they work
-- ============================================================

SELECT * FROM vw_funnel_kpi_summary   ORDER BY stage_order;
GO

SELECT * FROM vw_stage_dropoff        ORDER BY severity_rank;
GO

SELECT * FROM vw_channel_performance  ORDER BY quality_rank;
GO

SELECT * FROM vw_segment_conversion   ORDER BY conv_rank;
GO

SELECT * FROM vw_executive_dashboard;
GO

PRINT 'All views created and verified successfully.';
GO