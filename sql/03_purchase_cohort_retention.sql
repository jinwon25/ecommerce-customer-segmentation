-- ============================================================================
-- 첫 구매월 코호트 리텐션(long format)
--   결과: `ecomm-extension.ecomm_analysis.purchase_cohort_retention`
--   원천: `ecomm-extension.ecomm_raw.Onlinesales`
--   엔진: BigQuery Standard SQL
--
-- 정의
--   first_purchase_month: 고객의 첫 거래월(회원 가입월이 아님)
--   month_index: 첫 거래월로부터 경과한 달, m0 = 0
--   retention_pct: 코호트 고객 중 해당 월에 거래한 고유 고객 비율
--
-- 관측 종료월까지의 완전한 격자를 생성한다. 관측 가능한데 거래가 없으면 0,
-- 아직 도래하지 않은 미래 월은 행 자체가 없어 0과 미관측을 혼동하지 않는다.
-- ============================================================================

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.purchase_cohort_retention` AS

WITH first_purchase AS (
  SELECT
    `고객ID`,
    DATE_TRUNC(MIN(`거래날짜`), MONTH) AS first_purchase_month
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
  GROUP BY `고객ID`
),

observation_window AS (
  SELECT
    MAX(`거래날짜`) AS observation_end_date,
    DATE_TRUNC(MAX(`거래날짜`), MONTH) AS observation_end_month
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
),

cohort_size AS (
  SELECT
    first_purchase_month,
    COUNT(*) AS cohort_size
  FROM first_purchase
  GROUP BY first_purchase_month
),

cohort_grid AS (
  SELECT
    cs.first_purchase_month,
    cs.cohort_size,
    month_index,
    DATE_ADD(cs.first_purchase_month, INTERVAL month_index MONTH) AS activity_month,
    DATE_DIFF(ow.observation_end_month, cs.first_purchase_month, MONTH) AS max_observed_month_index,
    ow.observation_end_date
  FROM cohort_size AS cs
  CROSS JOIN observation_window AS ow
  CROSS JOIN UNNEST(
    GENERATE_ARRAY(0, DATE_DIFF(ow.observation_end_month, cs.first_purchase_month, MONTH))
  ) AS month_index
),

monthly_activity AS (
  SELECT
    fp.first_purchase_month,
    DATE_TRUNC(s.`거래날짜`, MONTH) AS activity_month,
    COUNT(DISTINCT s.`고객ID`) AS active_customers
  FROM `ecomm-extension.ecomm_raw.Onlinesales` AS s
  JOIN first_purchase AS fp USING (`고객ID`)
  GROUP BY fp.first_purchase_month, activity_month
)

SELECT
  g.first_purchase_month,
  g.cohort_size,
  g.month_index,
  g.activity_month,
  g.max_observed_month_index,
  g.observation_end_date,
  COALESCE(a.active_customers, 0) AS active_customers,
  ROUND(SAFE_DIVIDE(COALESCE(a.active_customers, 0), g.cohort_size) * 100, 2)
    AS retention_pct,
  g.activity_month < DATE_TRUNC(g.observation_end_date, MONTH)
    OR g.observation_end_date = LAST_DAY(g.observation_end_date, MONTH)
    AS is_complete_month
FROM cohort_grid AS g
LEFT JOIN monthly_activity AS a
  USING (first_purchase_month, activity_month)
ORDER BY g.first_purchase_month, g.month_index;
