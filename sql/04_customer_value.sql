-- BigQuery Standard SQL
-- 미래 LTV를 추정하지 않고 2019년 관측기간의 고객가치와 구매활동을 분리해 보고한다.
-- 결과:
--   1) ecomm_analysis.customer_value_observed
--   2) ecomm_analysis.segment_value_summary

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.customer_value_observed` AS

WITH purchase_days AS (
  SELECT DISTINCT
    `고객ID`,
    `거래날짜`
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
),

activity AS (
  SELECT
    `고객ID`,
    MIN(`거래날짜`) AS `첫구매일`,
    MAX(`거래날짜`) AS `마지막구매일`,
    COUNT(*) AS `구매일수`,
    COUNT(DISTINCT DATE_TRUNC(`거래날짜`, MONTH)) AS `활성월수`,
    DATE_DIFF(MAX(`거래날짜`), MIN(`거래날짜`), DAY) AS `첫마지막구매간격_일`
  FROM purchase_days
  GROUP BY `고객ID`
),

ipt AS (
  SELECT
    `고객ID`,
    DATE_DIFF(
      `거래날짜`,
      LAG(`거래날짜`) OVER (PARTITION BY `고객ID` ORDER BY `거래날짜`),
      DAY
    ) AS `구매일간격_일`
  FROM purchase_days
),

ipt_by_customer AS (
  SELECT
    `고객ID`,
    AVG(`구매일간격_일`) AS `평균구매일간격_일`
  FROM ipt
  WHERE `구매일간격_일` IS NOT NULL
  GROUP BY `고객ID`
)

SELECT
  cm.`고객ID`,
  cm.Customer_Segment AS `세그먼트`,
  cm.Monetary AS `관측누적매출`,
  a.`첫구매일`,
  a.`마지막구매일`,
  a.`구매일수`,
  a.`활성월수`,
  a.`첫마지막구매간격_일`,
  ROUND(SAFE_DIVIDE(cm.Monetary, a.`활성월수`), 2) AS `활성월당매출`,
  ROUND(SAFE_DIVIDE(cm.Monetary, a.`구매일수`), 2) AS `구매일당매출`,
  ROUND(i.`평균구매일간격_일`, 1) AS `평균구매일간격_일`
FROM `ecomm-extension.ecomm_analysis.customer_master` AS cm
JOIN activity AS a USING (`고객ID`)
LEFT JOIN ipt_by_customer AS i USING (`고객ID`);


CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.segment_value_summary` AS

WITH segment_rows AS (
  SELECT
    `세그먼트`,
    COUNT(*) AS `고객수`,
    ROUND(SUM(`관측누적매출`), 0) AS `총관측매출`,
    ROUND(AVG(`관측누적매출`), 0) AS `고객당평균관측매출`,
    ROUND(APPROX_QUANTILES(`관측누적매출`, 100)[OFFSET(50)], 0) AS `고객당중앙관측매출`,
    ROUND(AVG(`활성월수`), 2) AS `평균활성월수`,
    ROUND(AVG(`구매일수`), 2) AS `평균구매일수`,
    ROUND(AVG(`활성월당매출`), 0) AS `평균활성월당매출`,
    ROUND(APPROX_QUANTILES(`평균구매일간격_일`, 100)[OFFSET(50)], 1) AS `구매일간격_p50`
  FROM `ecomm-extension.ecomm_analysis.customer_value_observed`
  GROUP BY `세그먼트`
),

all_row AS (
  SELECT
    'ALL' AS `세그먼트`,
    COUNT(*) AS `고객수`,
    ROUND(SUM(`관측누적매출`), 0) AS `총관측매출`,
    ROUND(AVG(`관측누적매출`), 0) AS `고객당평균관측매출`,
    ROUND(APPROX_QUANTILES(`관측누적매출`, 100)[OFFSET(50)], 0) AS `고객당중앙관측매출`,
    ROUND(AVG(`활성월수`), 2) AS `평균활성월수`,
    ROUND(AVG(`구매일수`), 2) AS `평균구매일수`,
    ROUND(AVG(`활성월당매출`), 0) AS `평균활성월당매출`,
    ROUND(APPROX_QUANTILES(`평균구매일간격_일`, 100)[OFFSET(50)], 1) AS `구매일간격_p50`
  FROM `ecomm-extension.ecomm_analysis.customer_value_observed`
)

SELECT * FROM all_row
UNION ALL
SELECT * FROM segment_rows
ORDER BY
  CASE WHEN `세그먼트` = 'ALL' THEN 0 ELSE 1 END,
  `총관측매출` DESC;
