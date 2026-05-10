# SQL Funnel Analysis - Fintech Loan Platform

**Type of Analysis:** Funnel Analysis · Segmentation · Time-to-Convert  
**Industry:** Fintech / Financial Services  

---

## Executive Summary

LendWise, a fictional digital lending platform, was experiencing significant drop-off across its five-stage loan application funnel - but had no visibility into *where* applicants were being lost, *which segments* were most affected, or *how long* each stage was taking.

This project analyses a full year (2023) of simulated application event data across 500 registered users and 413 loan applications. Using SQL Server, the analysis uncovers the exact stages where conversion breaks down, which acquisition channels and loan products perform best, and how processing speed directly impacts disbursement rates.

**Key findings:**

- Only **37.3%** of submitted applications result in a disbursement - meaning nearly **2 in 3 applicants are lost** somewhere in the funnel
- The `verified → approved` stage is the single biggest bottleneck, with a **39.4% drop-off rate** (108 applications lost)
- Applications reviewed within 6 hours convert at **47.2%** vs applications that wait over 48 hours which drop significantly lower - confirming that operational speed is a direct conversion lever
- **$26,576,409** in loan value is sitting in incomplete applications - representing recoverable pipeline revenue
- Paid search brings the highest quality leads at **44.2% conversion**, while email campaigns convert at only **26.8%** - suggesting a marketing budget reallocation opportunity

**Business impact:** Addressing the verification-to-approval bottleneck and standardising same-day first response could realistically recover 8 - 12 percentage points of end-to-end conversion, translating to millions in additional disbursed loan value annually.

**Possible next steps:** Integrate credit score and income data into an approval prediction model, build a real-time Power BI dashboard connected to the KPI views, and run A/B tests on faster review SLAs for high-credit-score applicants.

---

## Business Problem

### Background

Digital lending platforms live and die by their application funnel. Unlike traditional banks, fintech lenders compete on speed and simplicity - applicants who experience friction at any stage will abandon and apply elsewhere within minutes.

LendWise's Head of Growth raised the following concerns going into 2024 planning:

> *"We know our disbursement numbers, but we have no idea where we're losing people. Is it the verification step? Is it our approval process? Are certain loan types harder to get through? And are some of our marketing channels bringing applicants who aren't serious?"*

Without answers to these questions, the business was making budget and operations decisions blind.

### The Problem This Project Solves

This analysis answers four core business questions:

1. **Where exactly is the funnel leaking?** - At which stage do we lose the most applicants, and by how much?
2. **Who converts and who doesn't?** - Do certain loan types, age groups, or acquisition channels perform better?
3. **Does speed matter?** - Is there a measurable relationship between how fast we respond to applicants and whether they convert?
4. **How much revenue is at risk?** - What is the monetary value of applications currently stuck in the pipeline?

### Data Overview

This is a simulated case study. All data was synthetically generated to reflect realistic fintech lending patterns. No real customer data was used.

| Table | Rows | Description |
|---|---|---|
| `applicants` | 500 | Registered users with demographics and acquisition channel |
| `loan_applications` | 413 | Submitted applications with loan type and amount |
| `application_events` | 1,386 | Timestamped stage transitions per application |
| `credit_profiles` | 500 | Credit scores, debt-to-income ratios, default history |

### The Loan Application Funnel

Every application moves through five stages. An applicant can drop off at any point:

```
[Registration] → [Submitted] → [Under Review] → [Verified] → [Approved] → [Disbursed]
```

The goal is to understand the volume and conversion rate at each transition.

---

## Methodology

The analysis was structured in four layers, each building on the previous:

**1. Funnel Analysis** - Measured how many applications reached each stage, the drop-off count and percentage at each transition, and the overall end-to-end conversion rate. Identified the single biggest bottleneck stage.

**2. Segmentation Analysis** - Broke down conversion rates across five dimensions: loan type, acquisition channel, age group, credit score band, and employment status. Also performed a cross-segment analysis combining channel and loan type to find the highest-performing combinations.

**3. Time-to-Convert Analysis** - Calculated the average number of days applications spend at each stage using timestamp differences. Tested whether faster initial response times correlate with higher conversion rates. Identified applications stuck in the pipeline and quantified their revenue value.

**4. KPI Summary Views** - Consolidated all key metrics into five reusable SQL VIEWs, including an executive dashboard view that produces a single-row snapshot of funnel health - designed to connect directly to a reporting tool.

---

## Skills & Tools Used

### SQL Server

| Feature | Used For |
|---|---|
| `WITH` (CTEs) | Breaking complex logic into readable, layered steps |
| Window Functions (`LAG`, `LEAD`, `RANK`, `FIRST_VALUE`, `ROW_NUMBER`) | Stage-to-stage comparisons, rankings, funnel anchoring |
| `PERCENTILE_CONT` | Median days calculation per funnel stage |
| `DATEDIFF` | Measuring time between stage transitions |
| `CASE WHEN` bucketing | Age groups, credit score bands, journey speed tiers |
| Multi-table `JOIN` | Linking events, applications, applicants, and credit profiles |
| `GROUP BY` + `HAVING` | Filtering aggregated groups (e.g. only completed journeys) |
| `UNION ALL` | Appending benchmark rows to monthly trend output |
| `CREATE VIEW` | Building reusable KPI objects for reporting tools |
| `BULK INSERT` | Loading CSV seed data into SQL Server |
| `CROSS JOIN` | Combining single-row summary CTEs in the executive view |

---

## Results & Business Recommendations

### 1. Funnel Overview

| Stage | Applications | Dropped | Stage Conv% | Overall% |
|---|---|---|---|---|
| Submitted | 413 | - | 100% | 100% |
| Under Review | 379 | 34 | 91.8% | 91.8% |
| Verified | 274 | 105 | 72.3% | 66.3% |
| **Approved** | **166** | **108** | **60.6%** | **40.2%** |
| Disbursed | 154 | 12 | 92.8% | 37.3% |

**Finding:** The funnel loses 62.7% of all applications before disbursement. Two stages account for the majority of losses: `verified → approved` (108 lost, 39.4% drop) and `under_review → verified` (105 lost, 27.7% drop). The final step from approved to disbursed is actually the healthiest at 92.8% - once approved, applicants almost always receive their funds.

**Recommendation:** Prioritise a review of the underwriting and approval criteria. The fact that 108 applicants cleared verification but were not approved suggests either overly strict approval thresholds or inconsistent underwriter decisions. A policy review targeting this stage could recover the most applications.

---

### 2. Acquisition Channel Performance

| Channel | Applications | Conv% | Volume Share | vs Average |
|---|---|---|---|---|
| Paid Search | 86 | **44.2%** | 20.8% | +6.9% |
| Organic Search | 106 | 42.5% | 25.7% | +5.2% |
| Referral | 74 | 39.2% | 17.9% | +1.9% |
| Direct | 29 | 34.5% | 7.0% | −2.8% |
| Social Media | 62 | 32.3% | 15.0% | −5.0% |
| Email Campaign | 56 | **26.8%** | 13.6% | **−10.5%** |

**Finding:** Email campaigns bring 13.6% of all applications but convert at the lowest rate - 10.5 percentage points below the overall average. Paid search and organic search consistently outperform all other channels on quality.

**Recommendation:** Reallocate email campaign budget toward paid and organic search. If email campaigns cannot be improved (through better targeting or lead qualification), they represent the lowest return on marketing spend. Referral is underutilised at only 17.9% of volume with strong conversion - a referral incentive programme could be high value.

---

### 3. Loan Type Conversion

| Loan Type | Applications | Conv% | Avg Loan Amount | Total Disbursed Value |
|---|---|---|---|---|
| Education Loan | 36 | **41.7%** | $18,994 | $285,870 |
| Personal Loan | 151 | 39.7% | $27,679 | $1,660,740 |
| Home Loan | 101 | 38.6% | $282,289 | $11,009,271 |
| Auto Loan | 73 | 32.9% | $32,717 | $785,208 |
| Business Loan | 52 | **30.8%** | $109,593 | $1,144,241 |

**Finding:** Business loans have both the lowest conversion rate (30.8%) and the second highest average loan amount ($109,593). These represent high-value applications being lost at a disproportionate rate - the gap between their potential revenue contribution and their actual conversion is the largest of any product.

**Recommendation:** Investigate whether business loan applicants face disproportionate rejection at the approval stage. A dedicated business loan underwriting track with tailored criteria could improve conversion without relaxing risk standards.

---

### 4. Time-to-Convert Analysis

**Average days at each stage:**

| Stage Transition | Avg Days | Median Days |
|---|---|---|
| Submitted → Under Review | 1.1 | 1.1 |
| Under Review → Verified | 2.2 | 2.2 |
| Verified → Approved | 1.6 | 1.5 |
| Approved → Disbursed | **2.9** | 2.9 |

**Average total journey (submitted to disbursed): 7.4 days**

**Finding:** The `approved → disbursed` step takes the longest at 2.9 days average. For an applicant who has already waited through the entire process, a 3-day wait for funds after approval creates unnecessary friction and risk of abandonment.

---

**Does first response speed predict conversion?**

| First Response Time | Applications | Conv% |
|---|---|---|
| Same day (≤6 hrs) | 36 | **47.2%** |
| Next day (7–24 hrs) | 140 | 43.6% |
| Two days (25–48 hrs) | 203 | 37.4% |

**Finding:** There is a clear and consistent relationship between how quickly an application enters review and whether it ultimately converts. Applications picked up same-day convert at 47.2% - nearly 10 percentage points higher than those that wait over 48 hours.

**Recommendation:** Implement a same-day review SLA for all incoming applications, prioritising high credit score applicants. Given that same-day response is associated with a 9.8 percentage point conversion lift, even a partial improvement in response time across the full application volume would meaningfully increase disbursements.

---

### 5. Revenue at Risk — Incomplete Pipeline

| Stuck At Stage | Applications | Revenue at Risk |
|---|---|---|
| Submitted | 34 | $2,357,514 |
| Under Review | 105 | $10,464,701 |
| **Verified** | **108** | **$12,820,261** |
| Approved | 12 | $933,933 |
| **Total** | **259** | **$26,576,409** |

**Finding:** $26.6 million in loan value is sitting in applications that never reached disbursement. The largest single pool - $12.8M - is stuck at the verified stage, meaning these applicants successfully passed document verification but were never moved to an approval decision. This is the clearest operational opportunity in the dataset.

**Recommendation:** Conduct a manual review of all 108 applications stuck at the verified stage. Many may be recoverable with a follow-up action from the underwriting team. Establish an automated alert for any verified application that has not moved to an approval decision within 5 business days.

---

## Next Steps

**If given more time and data, the following analyses would strengthen this project:**

1. **Power BI dashboard** - Connect the five KPI views (`vw_funnel_kpi_summary`, `vw_executive_dashboard`, etc.) directly to Power BI to create a live, interactive funnel dashboard that refreshes automatically as new applications come in.

2. **Cohort analysis** - Track applicant cohorts by registration month to understand whether conversion rates are improving over time, and whether process changes in a given month had a measurable impact downstream.

3. **Approval prediction model** - Use credit score, debt-to-income ratio, employment status, and loan amount to build a logistic regression model (in Python) that predicts approval probability. This would allow LendWise to pre-qualify applicants and reduce wasted processing time.

4. **A/B test design** - Design a formal experiment to test the impact of a same-day SLA policy on conversion rate, using a control group (standard processing) and a treatment group (guaranteed 6-hour first review).

5. **Rejection reason analysis** - In a real dataset, rejection reasons would be logged. Analysing the most common rejection reasons at each stage would make the approval bottleneck finding far more actionable.

**Project limitations:**

- Data is synthetically generated - real-world patterns may differ, particularly around credit score distributions and approval logic
- Drop-off reasons are not captured - we can see *where* applicants are lost but not *why*
- No external market data - channel quality comparisons assume consistent lead intent across all channels, which may not hold in practice
- Single-year snapshot - seasonality effects cannot be fully confirmed without multi-year data

---

## Repository Structure

```
lendwise-funnel-analysis/
│
├── data/
│   ├── applicants.csv
│   ├── loan_applications.csv
│   ├── application_events.csv
│   └── credit_profiles.csv
│
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 03_funnel_analysis.sql
│   ├── 04_segmentation.sql
│   ├── 05_time_to_convert.sql 
│   └── 06_kpi_summary_views.sql
│
└── README.md
```

Run scripts `03` through `06` in order to execute the full analysis

---

## Author

**Faith Jeptoo**
Data Analyst | Excel · Python · SQL · Data Visualisation
[LinkedIn](https://linkedin.com/in/jeptoofaithkibowen) · [Portfolio](https://faithkibowen-data.com) · [GitHub](https://github.com/kibowenfaith)
