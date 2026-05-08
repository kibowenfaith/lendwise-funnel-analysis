-- ============================================================
-- LendWise Loan Platform  |  Time-to-Convert Analysis
-- Project : SQL Funnel Analysis – Fintech Loan Platform
-- ============================================================
-- WHAT THIS SCRIPT DOES
-- Analyses how long each stage of the loan application takes
-- and whether processing delays cause applicants to abandon.
--   1. Average time (days) spent at each funnel stage
--   2. Full application journey duration per application
--   3. Slow vs fast applications — do fast ones convert better?
--   4. Time-to-convert by loan type
--   5. Time-to-convert by acquisition channel
--   6. Applications stuck in-progress (never completed)
-- ============================================================

USE LendWise;
GO


-- ============================================================
-- QUERY 1 : Average Days Spent at Each Funnel Stage
-- ============================================================
-- Calculates how long (in days) each application spends
-- between consecutive stages using LEAD to get the next
-- stage timestamp, then DATEDIFF to measure the gap.
-- Aggregates to get the average per stage across all apps.
-- ============================================================

WITH stage_transitions AS (
    SELECT
        application_id,
        stage,
        event_timestamp,

        -- Get the timestamp of the NEXT stage for this application
        LEAD(event_timestamp) OVER (
            PARTITION BY application_id
            ORDER BY
                CASE stage
                    WHEN 'submitted'    THEN 1
                    WHEN 'under_review' THEN 2
                    WHEN 'verified'     THEN 3
                    WHEN 'approved'     THEN 4
                    WHEN 'disbursed'    THEN 5
                END
        )                                                   AS next_stage_timestamp,

        LEAD(stage) OVER (
            PARTITION BY application_id
            ORDER BY
                CASE stage
                    WHEN 'submitted'    THEN 1
                    WHEN 'under_review' THEN 2
                    WHEN 'verified'     THEN 3
                    WHEN 'approved'     THEN 4
                    WHEN 'disbursed'    THEN 5
                END
        )                                                   AS next_stage

    FROM application_events
),

stage_durations AS (
    SELECT
        application_id,
        stage                                               AS current_stage,
        next_stage,
        DATEDIFF(HOUR, event_timestamp, next_stage_timestamp)
                                                            AS hours_in_stage,
        DATEDIFF(DAY,  event_timestamp, next_stage_timestamp)
                                                            AS days_in_stage
    FROM stage_transitions
    WHERE next_stage_timestamp IS NOT NULL   -- exclude final stage (no next)
),

-- Median must be in its own CTE — PERCENTILE_CONT cannot live
-- inside GROUP BY in SQL Server. We isolate it here and JOIN it in.
stage_medians AS (
    SELECT DISTINCT
        current_stage,
        ROUND(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CAST(days_in_stage AS FLOAT))
            OVER (PARTITION BY current_stage)
        , 1)                                                AS median_days
    FROM stage_durations
)

SELECT
    REPLACE(sd.current_stage, '_', ' ')                     AS stage,
    REPLACE(sd.next_stage,    '_', ' ')                     AS transitions_to,
    COUNT(*)                                                AS transitions_observed,

    ROUND(AVG(CAST(sd.hours_in_stage AS FLOAT)), 1)         AS avg_hours,
    ROUND(AVG(CAST(sd.days_in_stage  AS FLOAT)), 1)         AS avg_days,

    MIN(sd.days_in_stage)                                   AS min_days,
    MAX(sd.days_in_stage)                                   AS max_days,

    -- Joined in from the isolated median CTE above
    sm.median_days

FROM stage_durations  sd
JOIN stage_medians    sm ON sd.current_stage = sm.current_stage
GROUP BY
    sd.current_stage,
    sd.next_stage,
    sm.median_days
ORDER BY
    CASE sd.current_stage
        WHEN 'submitted'    THEN 1
        WHEN 'under_review' THEN 2
        WHEN 'verified'     THEN 3
        WHEN 'approved'     THEN 4
    END;
GO


-- ============================================================
-- QUERY 2 : Full Journey Duration Per Application
-- ============================================================
-- For every application that was disbursed, calculates the
-- total number of days from submission to disbursement.
-- Also flags applications that took unusually long.
-- ============================================================

WITH journey AS (
    SELECT
        application_id,
        MIN(CASE WHEN stage = 'submitted'  THEN event_timestamp END) AS submitted_at,
        MAX(CASE WHEN stage = 'disbursed'  THEN event_timestamp END) AS disbursed_at
    FROM application_events
    GROUP BY application_id
    HAVING
        MIN(CASE WHEN stage = 'submitted' THEN event_timestamp END) IS NOT NULL
    AND MAX(CASE WHEN stage = 'disbursed' THEN event_timestamp END) IS NOT NULL
),

journey_with_duration AS (
    SELECT
        j.application_id,
        la.loan_type,
        la.loan_amount,
        j.submitted_at,
        j.disbursed_at,
        DATEDIFF(DAY, j.submitted_at, j.disbursed_at)       AS total_days

    FROM journey j
    JOIN loan_applications la ON j.application_id = la.application_id
)

SELECT
    application_id,
    REPLACE(loan_type, '_', ' ')                            AS loan_type,
    loan_amount,
    CAST(submitted_at AS DATE)                              AS submitted_date,
    CAST(disbursed_at AS DATE)                              AS disbursed_date,
    total_days,

    -- Categorise journey speed
    CASE
        WHEN total_days <= 7  THEN 'Fast    (≤7 days)'
        WHEN total_days <= 14 THEN 'Average (8–14 days)'
        WHEN total_days <= 21 THEN 'Slow    (15–21 days)'
        ELSE                       'Very slow (>21 days)'
    END                                                     AS journey_category,

    -- Flag outliers: more than 2x the average total days
    CASE
        WHEN total_days > 2 * AVG(total_days) OVER () THEN 'OUTLIER'
        ELSE 'Normal'
    END                                                     AS outlier_flag,

    -- Overall average for context (window function)
    ROUND(AVG(CAST(total_days AS FLOAT)) OVER (), 1)        AS overall_avg_days

FROM journey_with_duration
ORDER BY total_days DESC;
GO


-- ============================================================
-- QUERY 3 : Does Speed of Processing Affect Conversion?
-- ============================================================
-- Groups applications by how quickly they moved from
-- submitted → under_review (first internal response time).
-- Fast first response may signal better conversion rates.
-- This tests whether operational speed predicts outcomes.
-- ============================================================

WITH first_response AS (
    SELECT
        s.application_id,

        -- Time from submission to first review pickup
        DATEDIFF(HOUR,
            s.event_timestamp,
            r.event_timestamp)                              AS hours_to_first_review

    FROM application_events s
    JOIN application_events r
        ON  s.application_id = r.application_id
        AND s.stage = 'submitted'
        AND r.stage = 'under_review'
),

with_outcome AS (
    SELECT
        fr.application_id,
        fr.hours_to_first_review,

        -- Response speed tier
        CASE
            WHEN fr.hours_to_first_review <= 6  THEN '1. Same day     (≤6 hrs)'
            WHEN fr.hours_to_first_review <= 24 THEN '2. Next day     (7–24 hrs)'
            WHEN fr.hours_to_first_review <= 48 THEN '3. Two days     (25–48 hrs)'
            ELSE                                     '4. Slow         (>48 hrs)'
        END                                                 AS response_tier,

        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved

    FROM first_response fr
    JOIN application_events ae ON fr.application_id = ae.application_id
    GROUP BY fr.application_id, fr.hours_to_first_review
)

SELECT
    response_tier,
    COUNT(*)                                                AS total_applications,
    SUM(is_approved)                                        AS approved,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    ROUND(AVG(CAST(hours_to_first_review AS FLOAT)), 1)    AS avg_hours_to_review

FROM with_outcome
GROUP BY response_tier
ORDER BY response_tier;
GO


-- ============================================================
-- QUERY 4 : Time-to-Convert by Loan Type
-- ============================================================
-- Answers: "Does it take longer to disburse a home loan than
-- a personal loan? And does that affect conversion?"
-- Combines journey duration with loan type segmentation.
-- ============================================================

WITH journey AS (
    SELECT
        ae.application_id,
        la.loan_type,
        DATEDIFF(DAY,
            MIN(CASE WHEN ae.stage = 'submitted' THEN ae.event_timestamp END),
            MAX(CASE WHEN ae.stage = 'disbursed' THEN ae.event_timestamp END)
        )                                                   AS total_days_to_disburse,

        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed

    FROM application_events ae
    JOIN loan_applications  la ON ae.application_id = la.application_id
    GROUP BY ae.application_id, la.loan_type
)

SELECT
    REPLACE(loan_type, '_', ' ')                            AS loan_type,
    COUNT(*)                                                AS total_applications,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    -- Average days only for applications that were disbursed
    ROUND(AVG(CASE WHEN is_disbursed = 1
              THEN CAST(total_days_to_disburse AS FLOAT)
              END), 1)                                      AS avg_days_to_disburse,

    MIN(CASE WHEN is_disbursed = 1 THEN total_days_to_disburse END)
                                                            AS fastest_days,
    MAX(CASE WHEN is_disbursed = 1 THEN total_days_to_disburse END)
                                                            AS slowest_days

FROM journey
GROUP BY loan_type
ORDER BY avg_days_to_disburse DESC;
GO


-- ============================================================
-- QUERY 5 : Abandoned Applications — Stuck In-Progress
-- ============================================================
-- Identifies applications that started the funnel but never
-- reached disbursement, and shows their last known stage.
-- These are lost opportunities — the business should know
-- exactly where in the funnel they went silent.
-- ============================================================

WITH last_stage AS (
    SELECT
        application_id,
        stage                                               AS last_stage,
        event_timestamp                                     AS last_activity,

        -- Rank stages so we can pick the furthest reached
        CASE stage
            WHEN 'submitted'    THEN 1
            WHEN 'under_review' THEN 2
            WHEN 'verified'     THEN 3
            WHEN 'approved'     THEN 4
            WHEN 'disbursed'    THEN 5
        END                                                 AS stage_rank,

        ROW_NUMBER() OVER (
            PARTITION BY application_id
            ORDER BY
                CASE stage
                    WHEN 'submitted'    THEN 1
                    WHEN 'under_review' THEN 2
                    WHEN 'verified'     THEN 3
                    WHEN 'approved'     THEN 4
                    WHEN 'disbursed'    THEN 5
                END DESC
        )                                                   AS rn

    FROM application_events
),

furthest_stage AS (
    SELECT application_id, last_stage, last_activity, stage_rank
    FROM last_stage
    WHERE rn = 1
),

abandoned AS (
    SELECT
        fs.application_id,
        la.loan_type,
        la.loan_amount,
        fs.last_stage,
        fs.last_activity,
        fs.stage_rank,

        -- Days since last activity (how long they have been stuck)
        DATEDIFF(DAY, fs.last_activity, '2024-01-01')       AS days_since_last_activity

    FROM furthest_stage fs
    JOIN loan_applications la ON fs.application_id = la.application_id
    WHERE fs.last_stage != 'disbursed'   -- exclude completed applications
)

SELECT
    REPLACE(last_stage, '_', ' ')                           AS stuck_at_stage,
    COUNT(*)                                                AS abandoned_applications,
    ROUND(AVG(CAST(days_since_last_activity AS FLOAT)), 0)  AS avg_days_inactive,
    ROUND(AVG(CAST(loan_amount AS FLOAT)), 0)               AS avg_loan_amount,
    SUM(loan_amount)                                        AS total_revenue_at_risk

FROM abandoned
GROUP BY last_stage, stage_rank
ORDER BY stage_rank;
GO