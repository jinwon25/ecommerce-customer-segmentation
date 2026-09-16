-- BigQuery Standard SQL
-- 원본 5개 테이블을 업로드한 직후 실행하는 데이터 품질 점검.
-- 결과가 FAIL이면 01_customer_master.sql 실행 전에 원인부터 확인한다.

WITH
sales AS (
  SELECT *
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
),
customers AS (
  SELECT *
  FROM `ecomm-extension.ecomm_raw.Customer`
),
discounts AS (
  SELECT *
  FROM `ecomm-extension.ecomm_raw.Discount`
),
tax AS (
  SELECT *
  FROM `ecomm-extension.ecomm_raw.Tax`
),
joined AS (
  SELECT
    s.`고객ID`,
    s.`거래ID`,
    d.`할인율`,
    t.GST
  FROM sales AS s
  LEFT JOIN discounts AS d
    ON s.`제품카테고리` = d.`제품카테고리`
   AND FORMAT_DATE('%b', s.`거래날짜`) = d.`월`
  LEFT JOIN tax AS t
    ON s.`제품카테고리` = t.`제품카테고리`
),
transaction_quality AS (
  SELECT
    `거래ID`,
    COUNT(*) AS line_count,
    COUNT(DISTINCT `고객ID`) AS customer_count,
    COUNT(DISTINCT `거래날짜`) AS transaction_date_count,
    COUNT(DISTINCT `배송료`) AS delivery_fee_count
  FROM sales
  GROUP BY `거래ID`
),
checks AS (
  SELECT
    1 AS check_order,
    'sales_row_count' AS check_name,
    CAST(COUNT(*) AS STRING) AS observed,
    '> 0' AS expected,
    IF(COUNT(*) > 0, 'PASS', 'FAIL') AS status
  FROM sales

  UNION ALL

  SELECT
    2,
    'sales_date_range',
    CONCAT(CAST(MIN(`거래날짜`) AS STRING), ' ~ ', CAST(MAX(`거래날짜`) AS STRING)),
    '2019-01-01 ~ 2019-12-31',
    IF(MIN(`거래날짜`) = DATE '2019-01-01'
       AND MAX(`거래날짜`) = DATE '2019-12-31', 'PASS', 'CHECK')
  FROM sales

  UNION ALL

  SELECT
    3,
    'null_required_fields',
    CAST(COUNTIF(`고객ID` IS NULL OR `거래ID` IS NULL OR `거래날짜` IS NULL) AS STRING),
    '0',
    IF(COUNTIF(`고객ID` IS NULL OR `거래ID` IS NULL OR `거래날짜` IS NULL) = 0, 'PASS', 'FAIL')
  FROM sales

  UNION ALL

  SELECT
    4,
    'invalid_coupon_status',
    CAST(COUNTIF(`쿠폰상태` NOT IN ('Used', 'Clicked', 'Not Used') OR `쿠폰상태` IS NULL) AS STRING),
    '0',
    IF(COUNTIF(`쿠폰상태` NOT IN ('Used', 'Clicked', 'Not Used') OR `쿠폰상태` IS NULL) = 0, 'PASS', 'FAIL')
  FROM sales

  UNION ALL

  SELECT
    5,
    'duplicate_customer_keys',
    CAST(COUNT(*) AS STRING),
    '0',
    IF(COUNT(*) = 0, 'PASS', 'FAIL')
  FROM (
    SELECT `고객ID`
    FROM customers
    GROUP BY `고객ID`
    HAVING COUNT(*) > 1
  )

  UNION ALL

  SELECT
    6,
    'duplicate_tax_keys',
    CAST(COUNT(*) AS STRING),
    '0',
    IF(COUNT(*) = 0, 'PASS', 'FAIL')
  FROM (
    SELECT `제품카테고리`
    FROM tax
    GROUP BY `제품카테고리`
    HAVING COUNT(*) > 1
  )

  UNION ALL

  SELECT
    7,
    'duplicate_discount_keys',
    CAST(COUNT(*) AS STRING),
    '0',
    IF(COUNT(*) = 0, 'PASS', 'FAIL')
  FROM (
    SELECT `월`, `제품카테고리`
    FROM discounts
    GROUP BY `월`, `제품카테고리`
    HAVING COUNT(*) > 1
  )

  UNION ALL

  SELECT
    8,
    'join_row_count',
    CAST((SELECT COUNT(*) FROM joined) AS STRING),
    CAST((SELECT COUNT(*) FROM sales) AS STRING),
    IF((SELECT COUNT(*) FROM joined) = (SELECT COUNT(*) FROM sales), 'PASS', 'FAIL')

  UNION ALL

  SELECT
    9,
    'missing_tax_after_join',
    CAST(COUNTIF(GST IS NULL) AS STRING),
    '0',
    IF(COUNTIF(GST IS NULL) = 0, 'PASS', 'FAIL')
  FROM joined

  UNION ALL

  SELECT
    10,
    'rows_without_discount_match',
    CAST(COUNTIF(`할인율` IS NULL) AS STRING),
    'informational: unmatched rows use a 0% discount in customer_master',
    'INFO'
  FROM joined

  UNION ALL

  SELECT
    11,
    'invalid_numeric_fields',
    CAST(COUNTIF(
      `수량` IS NULL OR `수량` <= 0
      OR `평균금액` IS NULL OR `평균금액` < 0
      OR `배송료` IS NULL OR `배송료` < 0
    ) AS STRING),
    '0',
    IF(COUNTIF(
      `수량` IS NULL OR `수량` <= 0
      OR `평균금액` IS NULL OR `평균금액` < 0
      OR `배송료` IS NULL OR `배송료` < 0
    ) = 0, 'PASS', 'FAIL')
  FROM sales

  UNION ALL

  SELECT
    12,
    'transaction_key_conflicts',
    CAST(COUNTIF(customer_count != 1 OR transaction_date_count != 1) AS STRING),
    '0: each transaction ID belongs to one customer and one date',
    IF(COUNTIF(customer_count != 1 OR transaction_date_count != 1) = 0, 'PASS', 'FAIL')
  FROM transaction_quality

  UNION ALL

  SELECT
    13,
    'inconsistent_delivery_fee_within_transaction',
    CAST(COUNTIF(delivery_fee_count != 1) AS STRING),
    '0: delivery fee is repeated consistently across product lines',
    IF(COUNTIF(delivery_fee_count != 1) = 0, 'PASS', 'FAIL')
  FROM transaction_quality

  UNION ALL

  SELECT
    14,
    'multi_line_transactions',
    CAST(COUNTIF(line_count > 1) AS STRING),
    'informational: confirms why transaction-level aggregation is required',
    'INFO'
  FROM transaction_quality

  UNION ALL

  SELECT
    15,
    'sales_customers_missing_from_customer_table',
    CAST(COUNT(*) AS STRING),
    '0',
    IF(COUNT(*) = 0, 'PASS', 'FAIL')
  FROM (
    SELECT DISTINCT s.`고객ID`
    FROM sales AS s
    LEFT JOIN customers AS c USING (`고객ID`)
    WHERE c.`고객ID` IS NULL
  )

  UNION ALL

  SELECT
    16,
    'customers_without_sales',
    CAST(COUNT(*) AS STRING),
    'informational: nonzero would make acquisition conversion measurable',
    'INFO'
  FROM (
    SELECT c.`고객ID`
    FROM customers AS c
    LEFT JOIN (SELECT DISTINCT `고객ID` FROM sales) AS s USING (`고객ID`)
    WHERE s.`고객ID` IS NULL
  )
)

SELECT check_name, observed, expected, status
FROM checks
ORDER BY check_order;
