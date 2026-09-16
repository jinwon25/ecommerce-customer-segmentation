-- BigQuery Standard SQL
-- 쿠폰 사용 고객과 Clicked-only 고객의 관찰 비교용 분석 테이블.
-- `처치`는 무작위 배정이 아니라 실제 사용 행동이므로 이 테이블만으로
-- 쿠폰의 인과효과를 식별할 수 없다.

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.coupon_observational_population` AS

WITH observation_window AS (
  SELECT DATE_SUB(MAX(`거래날짜`), INTERVAL 61 DAY) AS latest_index_date
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
),

first_used AS (
  SELECT `고객ID`, MIN(`거래날짜`) AS `기준일`, 1 AS `쿠폰사용군`
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
  WHERE `쿠폰상태` = 'Used'
  GROUP BY `고객ID`
),

clicked_only AS (
  SELECT s.`고객ID`, MIN(s.`거래날짜`) AS `기준일`, 0 AS `쿠폰사용군`
  FROM `ecomm-extension.ecomm_raw.Onlinesales` AS s
  LEFT JOIN first_used AS u USING (`고객ID`)
  WHERE s.`쿠폰상태` = 'Clicked'
    AND u.`고객ID` IS NULL
  GROUP BY s.`고객ID`
),

indexed_population AS (
  SELECT * FROM first_used
  UNION ALL
  SELECT * FROM clicked_only
),

eligible_population AS (
  SELECT p.*
  FROM indexed_population AS p
  CROSS JOIN observation_window AS w
  WHERE p.`기준일` <= w.latest_index_date
),

first_purchase AS (
  SELECT
    `고객ID`,
    EXTRACT(MONTH FROM MIN(`거래날짜`)) AS `첫구매월`
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
  GROUP BY `고객ID`
),

pre_period AS (
  SELECT
    p.`고객ID`,
    COUNT(DISTINCT s.`거래ID`) AS pre_frequency,
    COUNT(DISTINCT s.`거래날짜`) AS pre_purchase_days,
    AVG(s.`수량` * s.`평균금액`) AS pre_line_value,
    COUNT(DISTINCT s.`제품카테고리`) AS pre_category_diversity
  FROM eligible_population AS p
  JOIN `ecomm-extension.ecomm_raw.Onlinesales` AS s
    ON s.`고객ID` = p.`고객ID`
   AND s.`거래날짜` < p.`기준일`
  GROUP BY p.`고객ID`
),

outcomes AS (
  SELECT
    p.`고객ID`,
    CAST(COUNT(DISTINCT s.`거래ID`) > 0 AS INT64) AS repurchase_60d,
    COALESCE(SUM(s.`수량` * s.`평균금액`), 0) AS product_revenue_60d
  FROM eligible_population AS p
  LEFT JOIN `ecomm-extension.ecomm_raw.Onlinesales` AS s
    ON s.`고객ID` = p.`고객ID`
   AND s.`거래날짜` > p.`기준일`
   AND s.`거래날짜` <= DATE_ADD(p.`기준일`, INTERVAL 60 DAY)
  GROUP BY p.`고객ID`
)

SELECT
  p.`고객ID` AS customer_id,
  p.`기준일` AS index_date,
  p.`쿠폰사용군` AS coupon_used,
  c.`성별` AS gender,
  c.`고객지역` AS region,
  c.`가입기간` AS tenure_months,
  fp.`첫구매월` AS first_purchase_month,
  COALESCE(pre.pre_frequency, 0) AS pre_frequency,
  COALESCE(pre.pre_purchase_days, 0) AS pre_purchase_days,
  COALESCE(pre.pre_line_value, 0) AS pre_line_value,
  COALESCE(pre.pre_category_diversity, 0) AS pre_category_diversity,
  CAST(COALESCE(pre.pre_purchase_days, 0) >= 2 AS INT64) AS pre_purchase_days_2plus,
  CAST(pre.`고객ID` IS NULL AS INT64) AS new_customer,
  o.repurchase_60d,
  o.product_revenue_60d
FROM eligible_population AS p
LEFT JOIN `ecomm-extension.ecomm_raw.Customer` AS c USING (`고객ID`)
LEFT JOIN first_purchase AS fp USING (`고객ID`)
LEFT JOIN pre_period AS pre USING (`고객ID`)
LEFT JOIN outcomes AS o USING (`고객ID`);
