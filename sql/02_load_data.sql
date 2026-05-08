-- ============================================================
-- LendWise Loan Platform  |  Load Seed Data
-- Project : SQL Funnel Analysis – Fintech Loan Platform
-- ============================================================

USE LendWise;
GO

-- ── Step 1: Set your data folder path here ───────────────────
DECLARE @base NVARCHAR(500) = N'C:\Users\KIBOWEN\OneDrive\Desktop\DATA\SQL_Projects\Lendwise_Funnel-Analysis\data';

-- ── Step 2: Load applicants ───────────────────────────────────
DECLARE @sql1 NVARCHAR(MAX) =
    N'BULK INSERT applicants FROM ''' + @base + N'\applicants.csv'' 
     WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', TABLOCK)';
EXEC sp_executesql @sql1;
PRINT 'applicants loaded.';

-- ── Step 3: Load loan_applications ───────────────────────────
DECLARE @sql2 NVARCHAR(MAX) =
    N'BULK INSERT loan_applications FROM ''' + @base + N'\loan_applications.csv''
     WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', TABLOCK)';
EXEC sp_executesql @sql2;
PRINT 'loan_applications loaded.';

-- ── Step 4: Load application_events ──────────────────────────
DECLARE @sql3 NVARCHAR(MAX) =
    N'BULK INSERT application_events FROM ''' + @base + N'\application_events.csv''
     WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', TABLOCK)';
EXEC sp_executesql @sql3;
PRINT 'application_events loaded.';

-- ── Step 5: Load credit_profiles ─────────────────────────────
DECLARE @sql4 NVARCHAR(MAX) =
    N'BULK INSERT credit_profiles FROM ''' + @base + N'\credit_profiles.csv''
     WITH (FIRSTROW=2, FIELDTERMINATOR='','', ROWTERMINATOR=''\n'', TABLOCK)';
EXEC sp_executesql @sql4;
PRINT 'credit_profiles loaded.';

-- ── Step 6: Quick row-count check ────────────────────────────
SELECT 'applicants'         AS [table], COUNT(*) AS row_count FROM applicants
UNION ALL
SELECT 'loan_applications'  AS [table], COUNT(*) AS row_count FROM loan_applications
UNION ALL
SELECT 'application_events' AS [table], COUNT(*) AS row_count FROM application_events
UNION ALL
SELECT 'credit_profiles'    AS [table], COUNT(*) AS row_count FROM credit_profiles;
GO
