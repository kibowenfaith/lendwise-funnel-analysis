-- ============================================================
-- LendWise Loan Platform  |  Segmentation Analysis
-- Project : SQL Funnel Analysis – Fintech Loan Platform
-- ============================================================
-- WHAT THIS SCRIPT DOES
-- Breaks down funnel conversion by key business dimensions:
--   1. Loan type       – which products convert best?
--   2. Acquisition channel – which channels bring quality leads?
--   3. Age group       – which demographics convert best?
--   4. Credit score band – does creditworthiness predict conversion?
--   5. Employment status – how does income stability affect approval?
--   6. Combined segment – channel + loan type (cross-analysis)
-- ============================================================

USE LendWise;
GO


-- ============================================================
-- QUERY 1 : Conversion Rate by Loan Type
-- ============================================================
-- Answers: "Are some loan products easier to get approved for?"
-- Joins loan_applications to application_events to check
-- whether each application reached the 'disbursed' stage.
-- ============================================================

WITH app_outcome AS (
    SELECT
        la.application_id,
        la.loan_type,
        la.loan_amount,

        -- Flag: did this application reach disbursed?
        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed,

        -- Flag: did it reach approved (even if not disbursed)?
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved,

        -- Flag: did it reach verified?
        MAX(CASE WHEN ae.stage = 'verified'  THEN 1 ELSE 0 END) AS is_verified

    FROM loan_applications la
    JOIN application_events ae
        ON la.application_id = ae.application_id
    GROUP BY
        la.application_id,
        la.loan_type,
        la.loan_amount
)

SELECT
    REPLACE(loan_type, '_', ' ')                            AS loan_type,
    COUNT(*)                                                AS total_applications,
    SUM(is_verified)                                        AS reached_verification,
    SUM(is_approved)                                        AS reached_approval,
    SUM(is_disbursed)                                       AS total_disbursed,

    -- Conversion rate: submitted → disbursed
    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    -- Average loan amount per type
    ROUND(AVG(CAST(loan_amount AS FLOAT)), 0)               AS avg_loan_amount,

    -- Total loan value disbursed
    SUM(CASE WHEN is_disbursed = 1 THEN loan_amount ELSE 0 END)
                                                            AS total_disbursed_value

FROM app_outcome
GROUP BY loan_type
ORDER BY conv_rate_pct DESC;
GO


-- ============================================================
-- QUERY 2 : Conversion Rate by Acquisition Channel
-- ============================================================
-- Answers: "Which marketing channels bring the highest quality
-- applicants — not just the most applicants?"
-- A channel with high volume but low conversion is wasted spend.
-- ============================================================

WITH app_outcome AS (
    SELECT
        la.application_id,
        ap.acquisition_channel,
        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved
    FROM loan_applications la
    JOIN application_events ae ON la.application_id = ae.application_id
    JOIN applicants          ap ON la.applicant_id   = ap.applicant_id
    GROUP BY
        la.application_id,
        ap.acquisition_channel
)

SELECT
    REPLACE(acquisition_channel, '_', ' ')                  AS channel,
    COUNT(*)                                                AS total_applications,
    SUM(is_approved)                                        AS approved,
    SUM(is_disbursed)                                       AS disbursed,

    -- Conversion rate per channel
    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    -- Channel share of all applications (window function)
    ROUND(CAST(COUNT(*) AS FLOAT)
          / SUM(COUNT(*)) OVER () * 100, 1)                AS channel_share_pct,

    -- Rank channels by conversion rate
    RANK() OVER (ORDER BY
        CAST(SUM(is_disbursed) AS FLOAT) / CAST(COUNT(*) AS FLOAT)
        DESC)                                               AS conv_rank

FROM app_outcome
GROUP BY acquisition_channel
ORDER BY conv_rate_pct DESC;
GO


-- ============================================================
-- QUERY 3 : Conversion Rate by Age Group
-- ============================================================
-- Answers: "Do older applicants convert better than younger ones?"
-- Age groups are defined using CASE WHEN bucketing.
-- ============================================================

WITH app_outcome AS (
    SELECT
        la.application_id,
        ap.age,

        -- Bucket ages into business-meaningful groups
        CASE
            WHEN ap.age BETWEEN 18 AND 25 THEN '18–25'
            WHEN ap.age BETWEEN 26 AND 35 THEN '26–35'
            WHEN ap.age BETWEEN 36 AND 45 THEN '36–45'
            WHEN ap.age BETWEEN 46 AND 55 THEN '46–55'
            WHEN ap.age >= 56             THEN '56+'
        END                                                 AS age_group,

        -- Sort key so results order correctly (not alphabetically)
        CASE
            WHEN ap.age BETWEEN 18 AND 25 THEN 1
            WHEN ap.age BETWEEN 26 AND 35 THEN 2
            WHEN ap.age BETWEEN 36 AND 45 THEN 3
            WHEN ap.age BETWEEN 46 AND 55 THEN 4
            WHEN ap.age >= 56             THEN 5
        END                                                 AS age_sort,

        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved,
        MAX(CASE WHEN ae.stage = 'verified'  THEN 1 ELSE 0 END) AS is_verified

    FROM loan_applications la
    JOIN application_events ae ON la.application_id = ae.application_id
    JOIN applicants          ap ON la.applicant_id   = ap.applicant_id
    GROUP BY
        la.application_id,
        ap.age
)

SELECT
    age_group,
    COUNT(*)                                                AS total_applications,
    SUM(is_verified)                                        AS reached_verification,
    SUM(is_approved)                                        AS reached_approval,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    -- How this group compares to the overall average
    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)
    - ROUND(CAST(SUM(SUM(is_disbursed)) OVER () AS FLOAT)
            / CAST(SUM(COUNT(*)) OVER () AS FLOAT) * 100, 1)
                                                            AS diff_from_avg_pct

FROM app_outcome
GROUP BY age_group, age_sort
ORDER BY age_sort;
GO


-- ============================================================
-- QUERY 4 : Conversion Rate by Credit Score Band
-- ============================================================
-- Answers: "Does a higher credit score actually lead to more
-- disbursements — and by how much?"
-- Joins credit_profiles to build credit tiers.
-- ============================================================

WITH app_outcome AS (
    SELECT
        la.application_id,
        cp.credit_score,

        -- Standard credit score bands used in lending
        CASE
            WHEN cp.credit_score >= 750              THEN '750–850  Excellent'
            WHEN cp.credit_score BETWEEN 700 AND 749 THEN '700–749  Good'
            WHEN cp.credit_score BETWEEN 650 AND 699 THEN '650–699  Fair'
            WHEN cp.credit_score BETWEEN 600 AND 649 THEN '600–649  Poor'
            WHEN cp.credit_score <  600              THEN '300–599  Very Poor'
        END                                                 AS credit_band,

        CASE
            WHEN cp.credit_score >= 750              THEN 1
            WHEN cp.credit_score BETWEEN 700 AND 749 THEN 2
            WHEN cp.credit_score BETWEEN 650 AND 699 THEN 3
            WHEN cp.credit_score BETWEEN 600 AND 649 THEN 4
            WHEN cp.credit_score <  600              THEN 5
        END                                                 AS band_sort,

        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved

    FROM loan_applications  la
    JOIN application_events ae ON la.application_id = ae.application_id
    JOIN applicants          ap ON la.applicant_id   = ap.applicant_id
    JOIN credit_profiles     cp ON ap.applicant_id   = cp.applicant_id
    GROUP BY
        la.application_id,
        cp.credit_score
)

SELECT
    credit_band,
    COUNT(*)                                                AS total_applications,
    SUM(is_approved)                                        AS approved,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    ROUND(AVG(CAST(credit_score AS FLOAT)), 0)             AS avg_credit_score

FROM app_outcome
GROUP BY credit_band, band_sort
ORDER BY band_sort;
GO


-- ============================================================
-- QUERY 5 : Conversion Rate by Employment Status
-- ============================================================
-- Answers: "Does employment type affect approval odds?"
-- Important for underwriting and risk policy decisions.
-- ============================================================

WITH app_outcome AS (
    SELECT
        la.application_id,
        ap.employment_status,
        ap.annual_income,
        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed,
        MAX(CASE WHEN ae.stage = 'approved'  THEN 1 ELSE 0 END) AS is_approved,
        MAX(CASE WHEN ae.stage = 'verified'  THEN 1 ELSE 0 END) AS is_verified
    FROM loan_applications  la
    JOIN application_events ae ON la.application_id = ae.application_id
    JOIN applicants          ap ON la.applicant_id   = ap.applicant_id
    GROUP BY
        la.application_id,
        ap.employment_status,
        ap.annual_income
)

SELECT
    REPLACE(employment_status, '_', ' ')                    AS employment_status,
    COUNT(*)                                                AS total_applications,
    SUM(is_verified)                                        AS verified,
    SUM(is_approved)                                        AS approved,
    SUM(is_disbursed)                                       AS disbursed,

    ROUND(CAST(SUM(is_disbursed) AS FLOAT)
          / CAST(COUNT(*) AS FLOAT) * 100, 1)              AS conv_rate_pct,

    ROUND(AVG(CAST(annual_income AS FLOAT)), 0)            AS avg_annual_income,

    -- Rank by conversion rate
    RANK() OVER (ORDER BY
        CAST(SUM(is_disbursed) AS FLOAT) / CAST(COUNT(*) AS FLOAT)
        DESC)                                               AS conv_rank

FROM app_outcome
GROUP BY employment_status
ORDER BY conv_rate_pct DESC;
GO


-- ============================================================
-- QUERY 6 : Cross-Segment — Channel × Loan Type
-- ============================================================
-- Answers: "Which channel + product combination converts best?"
-- This is the kind of granular insight that informs both
-- marketing targeting and product prioritisation decisions.
-- Only shows combinations with 5+ applications (statistically
-- meaningful) to avoid noise from tiny sample sizes.
-- ============================================================

WITH app_outcome AS (
    SELECT
        la.application_id,
        la.loan_type,
        ap.acquisition_channel,
        MAX(CASE WHEN ae.stage = 'disbursed' THEN 1 ELSE 0 END) AS is_disbursed
    FROM loan_applications  la
    JOIN application_events ae ON la.application_id = ae.application_id
    JOIN applicants          ap ON la.applicant_id   = ap.applicant_id
    GROUP BY
        la.application_id,
        la.loan_type,
        ap.acquisition_channel
),

segment_summary AS (
    SELECT
        REPLACE(acquisition_channel, '_', ' ')              AS channel,
        REPLACE(loan_type, '_', ' ')                        AS loan_type,
        COUNT(*)                                            AS total_applications,
        SUM(is_disbursed)                                   AS disbursed,
        ROUND(CAST(SUM(is_disbursed) AS FLOAT)
              / CAST(COUNT(*) AS FLOAT) * 100, 1)          AS conv_rate_pct
    FROM app_outcome
    GROUP BY acquisition_channel, loan_type
)

SELECT
    channel,
    loan_type,
    total_applications,
    disbursed,
    conv_rate_pct,

    -- Rank within each channel (best product per channel)
    RANK() OVER (
        PARTITION BY channel
        ORDER BY conv_rate_pct DESC
    )                                                       AS rank_within_channel

FROM segment_summary
WHERE total_applications >= 5          -- filter out low-sample noise
ORDER BY conv_rate_pct DESC;
GO