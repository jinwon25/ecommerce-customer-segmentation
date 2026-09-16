-- ============================================================================
-- 구매 고객 활동 단계(activity ladder)
--   원천: `ecomm-extension.ecomm_analysis.customer_master`
--   엔진: BigQuery Standard SQL
--
-- 이것은 시간 순서가 있는 가입→첫 구매 funnel이 아니다.
-- 원본 Customer 테이블에는 비구매 고객이 없고, Frequency는 2019년 전체 기간의
-- COUNT(DISTINCT 거래ID)이므로 고객의 누적 거래 활동 수준을 중첩 집합으로 보여준다.
-- 같은 날 여러 거래ID가 있을 수 있어 Frequency >= 2를 곧바로 재구매로 부르지 않는다.
-- ============================================================================

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.purchase_activity_ladder` AS

WITH stage_counts AS (
  SELECT
    COUNT(*) AS all_transacting_customers,
    COUNTIF(Frequency >= 2) AS customers_with_2plus_transaction_ids,
    COUNTIF(Frequency >= 5) AS customers_with_5plus_transaction_ids,
    COUNTIF(Customer_Segment IN ('핵심 파트너 고객', '성장형 고객'))
      AS priority_segment_customers
  FROM `ecomm-extension.ecomm_analysis.customer_master`
),

activity_ladder AS (
  SELECT
    1 AS `단계`,
    '거래 고객' AS `단계명`,
    '2019년 중 거래ID가 1개 이상인 고객' AS `정의`,
    all_transacting_customers AS `고객수`
  FROM stage_counts

  UNION ALL

  SELECT
    2,
    '거래ID 2개 이상',
    '2019년 중 서로 다른 거래ID가 2개 이상인 고객',
    customers_with_2plus_transaction_ids
  FROM stage_counts

  UNION ALL

  SELECT
    3,
    '거래ID 5개 이상',
    '2019년 중 서로 다른 거래ID가 5개 이상인 고객',
    customers_with_5plus_transaction_ids
  FROM stage_counts

  UNION ALL

  SELECT
    4,
    '우선 관리 세그먼트',
    'RFM 규칙상 핵심 파트너 또는 성장형인 고객',
    priority_segment_customers
  FROM stage_counts
)

SELECT
  `단계`,
  `단계명`,
  `정의`,
  `고객수`,
  LAG(`고객수`) OVER (ORDER BY `단계`) AS `직전단계_고객수`,
  ROUND(
    SAFE_DIVIDE(`고객수`, LAG(`고객수`) OVER (ORDER BY `단계`)) * 100,
    2
  ) AS `직전단계_대비_pct`,
  ROUND(
    SAFE_DIVIDE(`고객수`, MAX(IF(`단계` = 1, `고객수`, NULL)) OVER ()) * 100,
    2
  ) AS `전체거래고객_대비_pct`
FROM activity_ladder
ORDER BY `단계`;
