-- ============================================================
-- LendWise Loan Platform  |  Database Schema
-- Project : SQL Funnel Analysis – Fintech Loan Platform
-- Author  : Faith Jeptoo
-- Date    : 2024
-- Tool    : SQL Server
-- ============================================================

-- ── Create database (skip if already exists) ─────────────────
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'LendWise')
BEGIN
    CREATE DATABASE LendWise;
END
GO

USE LendWise;
GO

-- ── Drop tables if re-running (safe reset) ───────────────────
IF OBJECT_ID('application_events', 'U') IS NOT NULL DROP TABLE application_events;
IF OBJECT_ID('credit_profiles',    'U') IS NOT NULL DROP TABLE credit_profiles;
IF OBJECT_ID('loan_applications',  'U') IS NOT NULL DROP TABLE loan_applications;
IF OBJECT_ID('applicants',         'U') IS NOT NULL DROP TABLE applicants;
GO

-- ============================================================
-- TABLE 1 : applicants
-- One row per person who registered on the platform.
-- ============================================================
CREATE TABLE applicants (
    applicant_id        INT             PRIMARY KEY,
    first_name          VARCHAR(50)     NOT NULL,
    last_name           VARCHAR(50)     NOT NULL,
    email               VARCHAR(100)    NOT NULL UNIQUE,
    phone               VARCHAR(20),
    age                 INT             CHECK (age BETWEEN 18 AND 100),
    city                VARCHAR(100),
    employment_status   VARCHAR(30)     CHECK (employment_status IN (
                            'employed','self_employed','unemployed','student','retired')),
    annual_income       INT,
    acquisition_channel VARCHAR(50)     CHECK (acquisition_channel IN (
                            'organic_search','paid_search','referral',
                            'social_media','email_campaign','direct')),
    registration_date   DATETIME        NOT NULL
);
GO

-- ============================================================
-- TABLE 2 : loan_applications
-- One row per loan application submitted by a registrant.
-- A single applicant may submit more than one application.
-- ============================================================
CREATE TABLE loan_applications (
    application_id      INT             PRIMARY KEY,
    applicant_id        INT             NOT NULL
                            REFERENCES applicants(applicant_id),
    loan_type           VARCHAR(30)     CHECK (loan_type IN (
                            'personal_loan','home_loan','auto_loan',
                            'business_loan','education_loan')),
    loan_amount         INT             NOT NULL CHECK (loan_amount > 0),
    loan_term_months    INT             CHECK (loan_term_months IN (12,24,36,48,60)),
    status              VARCHAR(30)     NOT NULL DEFAULT 'submitted',
    application_date    DATETIME        NOT NULL
);
GO

-- ============================================================
-- TABLE 3 : application_events
-- One row per stage transition for each application.
-- This is the core table used for funnel analysis.
-- Stages (in order):
--   submitted → under_review → verified → approved → disbursed
-- ============================================================
CREATE TABLE application_events (
    event_id            INT             PRIMARY KEY,
    application_id      INT             NOT NULL
                            REFERENCES loan_applications(application_id),
    stage               VARCHAR(30)     NOT NULL CHECK (stage IN (
                            'submitted','under_review','verified',
                            'approved','disbursed')),
    event_timestamp     DATETIME        NOT NULL,
    notes               VARCHAR(255)
);
GO

-- ============================================================
-- TABLE 4 : credit_profiles
-- One row per applicant with credit risk attributes.
-- Used to segment conversion rates by creditworthiness.
-- ============================================================
CREATE TABLE credit_profiles (
    applicant_id            INT             PRIMARY KEY
                                REFERENCES applicants(applicant_id),
    credit_score            INT             CHECK (credit_score BETWEEN 300 AND 850),
    debt_to_income_ratio    DECIMAL(5,2)    CHECK (debt_to_income_ratio BETWEEN 0 AND 1),
    existing_loans          INT             DEFAULT 0,
    previous_defaults       INT             DEFAULT 0
);
GO

-- ============================================================
-- Useful indexes for query performance
-- ============================================================
CREATE INDEX IX_loan_applications_applicant  ON loan_applications  (applicant_id);
CREATE INDEX IX_application_events_app_id    ON application_events (application_id);
CREATE INDEX IX_application_events_stage     ON application_events (stage);
CREATE INDEX IX_applicants_channel           ON applicants          (acquisition_channel);
GO

PRINT 'Schema created successfully.';
GO
