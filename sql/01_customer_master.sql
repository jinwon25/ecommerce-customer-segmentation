-- ============================================================================
-- 고객 마스터 테이블 생성
--   결과: `ecomm-extension.ecomm_analysis.customer_master`
--   원천: `ecomm-extension.ecomm_raw.{Onlinesales, Discount, Tax}`
--
-- 거래금액 산식:
--     거래금액 = 수량 × 평균금액 × (1 - 할인율/100) × (1 + GST) + 배송료
--
-- 산식 적용 규칙 (이 쿼리의 해석):
--   1) 할인율은 `쿠폰상태` = 'Used'인 거래에만 적용한다.
--      - 'Clicked' / 'Not Used'는 노출되었으나 사용되지 않았으므로 실결제에
--        할인이 반영되지 않는다고 본다.
--      - 일괄 적용하면 비사용자 매출이 실제보다 과소 추정되어 Monetary 왜곡.
--   2) Discount 테이블은 월×카테고리 키를 제공한다. 매칭되지 않는 카테고리는
--      할인율 0%로 처리하되, 00_data_quality.sql에서 미매칭 행 수를 먼저 확인한다.
--   3) 배송료는 같은 거래ID의 상품 행에 반복되므로 상품 행마다 더하지 않는다.
--      세후·할인후 상품금액을 거래ID 단위로 합산한 뒤 MAX(배송료)를 한 번만 더한다.
--   4) `평균금액`은 단가이므로 수량을 곱한다. 할인·GST는 상품 행에 적용하고,
--      거래ID에 반복 저장된 배송료는 한 번만 더한다.
--
-- 코딩 컨벤션:
--   - 한글 컬럼은 백틱으로 감싼다. 영문/언더스코어 컬럼(GST, R_Score 등)은 미사용.
--
-- CTE 구조: transaction_lines → transactions → customer_rfm → rfm_scored → 최종
-- ============================================================================

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.customer_master` AS

WITH transaction_lines AS (
  -- 1. 거래 상품 행 단위: 할인·세율을 적용하되 배송료는 아직 더하지 않는다.
  SELECT
    s.`고객ID`,
    s.`거래ID`,
    s.`거래날짜`,
    s.`제품카테고리`,
    s.`수량`,
    s.`평균금액`,
    s.`배송료`,
    s.`쿠폰상태`,
    COALESCE(d.`할인율`, 0) AS `할인율`,
    COALESCE(t.GST, 0)      AS GST,
    s.`수량` * s.`평균금액`
      * (1 - CASE WHEN s.`쿠폰상태` = 'Used'
                  THEN COALESCE(d.`할인율`, 0) ELSE 0 END / 100)
      * (1 + COALESCE(t.GST, 0))
      AS `상품금액`
  FROM `ecomm-extension.ecomm_raw.Onlinesales` AS s
  LEFT JOIN `ecomm-extension.ecomm_raw.Discount` AS d
         ON s.`제품카테고리` = d.`제품카테고리`
        AND FORMAT_DATE('%b', s.`거래날짜`) = d.`월`
  LEFT JOIN `ecomm-extension.ecomm_raw.Tax` AS t
         ON s.`제품카테고리` = t.`제품카테고리`
),

transactions AS (
  -- 2. 거래ID 단위: 상품금액 합계 + 거래당 배송료 1회.
  SELECT
    `고객ID`,
    `거래ID`,
    `거래날짜`,
    SUM(`상품금액`) + MAX(`배송료`) AS `거래금액`
  FROM transaction_lines
  GROUP BY `고객ID`, `거래ID`, `거래날짜`
),

customer_rfm AS (
  -- 3. 고객 단위 RFM 원자료
  --    기준일 = 데이터 마지막 거래일(고정 스냅숏).
  --    Frequency는 거래ID 기준 COUNT DISTINCT(원본은 라인 단위라 한 거래가
  --    여러 행으로 분리될 수 있음).
  SELECT
    `고객ID`,
    DATE_DIFF(
      (SELECT MAX(`거래날짜`) FROM transactions),
      MAX(`거래날짜`),
      DAY
    )                              AS Recency,
    COUNT(DISTINCT `거래ID`)       AS Frequency,
    SUM(`거래금액`)                AS Monetary
  FROM transactions
  GROUP BY `고객ID`
),

rfm_scored AS (
  -- 4. PERCENT_RANK 기반 4분위 점수화
  --    NTILE은 같은 Frequency/Recency 값도 임의로 다른 점수에 배정할 수 있다.
  --    PERCENT_RANK를 사용해 동률 고객은 같은 점수를 받게 하며, 이 때문에 각
  --    점수의 고객 수는 정확히 같지 않을 수 있다.
  --    - R: 최근일수록 점수↑ → Recency DESC 순위의 뒤쪽이 높은 점수
  --    - F·M: 클수록 점수↑ → ASC 순위의 뒤쪽이 높은 점수
  SELECT
    `고객ID`,
    Recency,
    Frequency,
    Monetary,
    LEAST(4, 1 + CAST(FLOOR(PERCENT_RANK() OVER (ORDER BY Recency DESC) * 4) AS INT64))
      AS R_Score,
    LEAST(4, 1 + CAST(FLOOR(PERCENT_RANK() OVER (ORDER BY Frequency ASC) * 4) AS INT64))
      AS F_Score,
    LEAST(4, 1 + CAST(FLOOR(PERCENT_RANK() OVER (ORDER BY Monetary ASC) * 4) AS INT64))
      AS M_Score
  FROM customer_rfm
)

-- 5. 5개 핵심 세그먼트 + 기타 분류 (classify_customer_segment 이식)
--    CASE WHEN 평가 순서가 곧 if/elif 우선순위. 위 조건에 먼저 매칭되는 행은
--    아래 조건 평가에서 제외되므로 조건 순서에 따른 우선 분류가 보장된다.
SELECT
  `고객ID`,
  Recency,
  Frequency,
  Monetary,
  R_Score,
  F_Score,
  M_Score,
  CONCAT(CAST(R_Score AS STRING),
         CAST(F_Score AS STRING),
         CAST(M_Score AS STRING)) AS RFM_Score,
  CASE
    -- 핵심 파트너 고객: R/F/M 모두 4 이상
    WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4
      THEN '핵심 파트너 고객'

    -- 성장형 고객: 잠재력 높고 평균 이상 활동
    WHEN (R_Score BETWEEN 2 AND 4 AND F_Score BETWEEN 3 AND 4 AND M_Score >= 4)
      OR (R_Score BETWEEN 3 AND 4 AND F_Score BETWEEN 3 AND 4 AND M_Score BETWEEN 3 AND 4)
      THEN '성장형 고객'

    -- 유망 고객: 최근 활동은 있으나 빈도·금액은 낮음(신규/가능성 있는 라이트 유저)
    WHEN (R_Score >= 3 AND F_Score BETWEEN 1 AND 3 AND M_Score BETWEEN 1 AND 3)
      OR (R_Score >= 4 AND F_Score < 2 AND M_Score < 2)
      OR (R_Score BETWEEN 3 AND 4 AND F_Score < 2 AND M_Score < 2)
      THEN '유망 고객'

    -- 이탈 위험 고객: 활동 감소 조짐, 이탈 직전 단계
    WHEN (R_Score BETWEEN 2 AND 3 AND F_Score < 3 AND M_Score < 3)
      OR (R_Score BETWEEN 2 AND 3 AND F_Score BETWEEN 2 AND 3 AND M_Score BETWEEN 2 AND 3)
      THEN '이탈 위험 고객'

    -- 장기 비활성 고객: 거의 활동 없음 또는 과거에만 활동
    WHEN (R_Score < 3 AND F_Score BETWEEN 2 AND 4 AND M_Score BETWEEN 2 AND 4)
      OR (R_Score < 2 AND F_Score >= 4 AND M_Score >= 4)
      OR (R_Score < 2 AND F_Score < 2 AND M_Score < 2)
      THEN '장기 비활성 고객'

    ELSE '기타'
  END AS Customer_Segment
FROM rfm_scored;
