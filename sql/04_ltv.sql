-- ============================================================================
-- Phase 2 / Step 2. LTV + 재구매 간격(IPT) + 세그먼트별 비교
--
-- v2 수정 (검증 후):
--   1) IPT는 거래ID 단위가 아니라 *일자 단위*로 정의
--      - 본 데이터에서 같은 고객·같은 날 다중 거래ID 케이스가 93.1%
--      - 한 결제 행위가 여러 거래ID로 분할 기록되는 적재 구조
--      - 거래ID 단위 IPT는 분할 거래를 0일로 잡아 분위가 모두 0이 됨
--      - `(고객ID, 거래날짜)` DISTINCT로 일자 단위 압축 후 LAG로 산출
--      - 정의 변경 근거는 reports/phase2_ltv_notes.md
--   2) ltv_metrics / ipt_metrics를 세그먼트별 + 'ALL' UNION ALL로 명시 분리
--      - 이전 GROUPING SETS 결과의 'ALL' 행이 JOIN 단계에서 누락된 문제 차단
--      - UNION ALL은 추적·디버깅이 단순하고 결과 보장이 명확
--
-- 단순 LTV 정의:
--   LTV = ARPU × 평균 유지 기간(개월)
--     · ARPU            = 그룹의 고객당 평균 매출 (= AVG(Monetary))
--     · 평균 유지 기간  = 첫 거래일 ~ 마지막 거래일 차의 평균 (개월, /30.44 환산)
--   그룹 단위 메트릭이며 개별 고객의 미래 매출 예측치가 아니다.
--
-- 결과 테이블:
--   1) ecomm_analysis.customer_lifetime    : 고객 단위 lifetime 메트릭
--   2) ecomm_analysis.segment_ltv_summary  : 세그먼트 6개 + 'ALL' 1개 = 7행
--
-- 코딩 컨벤션: 한글 컬럼은 백틱.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 테이블 1. customer_lifetime  (일자 단위 IPT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.customer_lifetime` AS

WITH transaction_days AS (
  -- 1. 일자 단위 압축. 같은 고객의 같은 날 모든 거래(거래ID 무관)를 1행으로.
  --    적재 구조상 분할된 결제 행위를 단일 결제로 본다.
  SELECT DISTINCT
    `고객ID`,
    `거래날짜`
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
),

interpurchase AS (
  -- 2. LAG로 직전 *거래일*을 가져와 IPT(일) 산출.
  --    distinct 일자 기준이므로 IPT >= 1이 보장된다 (NULL은 첫 거래 한정).
  SELECT
    `고객ID`,
    `거래날짜`,
    DATE_DIFF(
      `거래날짜`,
      LAG(`거래날짜`) OVER (PARTITION BY `고객ID` ORDER BY `거래날짜`),
      DAY
    ) AS `재구매간격_일`
  FROM transaction_days
)

-- 3. 고객별 lifetime: 첫·마지막 거래일, 유지기간(개월), 평균 IPT
SELECT
  `고객ID`,
  MIN(`거래날짜`)                                                   AS `첫거래일`,
  MAX(`거래날짜`)                                                   AS `마지막거래일`,
  ROUND(DATE_DIFF(MAX(`거래날짜`), MIN(`거래날짜`), DAY) / 30.44, 2) AS `유지기간_월`,
  ROUND(AVG(`재구매간격_일`), 1)                                    AS `평균재구매간격_일`
FROM interpurchase
GROUP BY `고객ID`;


-- ----------------------------------------------------------------------------
-- 테이블 2. segment_ltv_summary  (세그먼트 + 'ALL' UNION ALL)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.segment_ltv_summary` AS

WITH joined AS (
  -- 1. customer_master(세그먼트·Monetary) + customer_lifetime(유지기간) JOIN
  SELECT
    cm.Customer_Segment AS `세그먼트`,
    cm.`고객ID`,
    cm.Monetary,
    cl.`유지기간_월`
  FROM `ecomm-extension.ecomm_analysis.customer_master`   AS cm
  JOIN `ecomm-extension.ecomm_analysis.customer_lifetime` AS cl USING(`고객ID`)
),

ipt_raw AS (
  -- 2. 분위 산출용 raw IPT — 일자 단위 압축 후 LAG로 계산.
  --    customer_master JOIN으로 세그먼트 매핑.
  SELECT
    cm.Customer_Segment AS `세그먼트`,
    DATE_DIFF(
      td.`거래날짜`,
      LAG(td.`거래날짜`) OVER (PARTITION BY td.`고객ID` ORDER BY td.`거래날짜`),
      DAY
    ) AS `재구매간격_일`
  FROM (
    SELECT DISTINCT `고객ID`, `거래날짜`
    FROM `ecomm-extension.ecomm_raw.Onlinesales`
  ) AS td
  JOIN `ecomm-extension.ecomm_analysis.customer_master` AS cm USING(`고객ID`)
),

ltv_metrics AS (
  -- 3. LTV 메트릭: 세그먼트별 행 + 'ALL' 행을 UNION ALL로 명시
  SELECT
    `세그먼트`,
    COUNT(*)                                     AS `고객수`,
    ROUND(AVG(Monetary), 0)                      AS `ARPU`,
    ROUND(AVG(`유지기간_월`), 2)                 AS `평균유지기간_월`,
    ROUND(AVG(Monetary) * AVG(`유지기간_월`), 0) AS `LTV`
  FROM joined
  GROUP BY `세그먼트`
  UNION ALL
  SELECT
    'ALL'                                        AS `세그먼트`,
    COUNT(*)                                     AS `고객수`,
    ROUND(AVG(Monetary), 0)                      AS `ARPU`,
    ROUND(AVG(`유지기간_월`), 2)                 AS `평균유지기간_월`,
    ROUND(AVG(Monetary) * AVG(`유지기간_월`), 0) AS `LTV`
  FROM joined
),

ipt_metrics AS (
  -- 4. IPT 평균·분위: 세그먼트별 행 + 'ALL' 행을 UNION ALL로 명시
  --    WHERE 재구매간격_일 IS NOT NULL로 1회 구매자(NULL) 자연 제외
  SELECT
    `세그먼트`,
    ROUND(AVG(`재구매간격_일`), 1)                  AS `재구매간격_평균_일`,
    APPROX_QUANTILES(`재구매간격_일`, 4)[OFFSET(1)]  AS `재구매간격_p25`,
    APPROX_QUANTILES(`재구매간격_일`, 4)[OFFSET(2)]  AS `재구매간격_p50`,
    APPROX_QUANTILES(`재구매간격_일`, 4)[OFFSET(3)]  AS `재구매간격_p75`
  FROM ipt_raw
  WHERE `재구매간격_일` IS NOT NULL
  GROUP BY `세그먼트`
  UNION ALL
  SELECT
    'ALL'                                           AS `세그먼트`,
    ROUND(AVG(`재구매간격_일`), 1)                  AS `재구매간격_평균_일`,
    APPROX_QUANTILES(`재구매간격_일`, 4)[OFFSET(1)]  AS `재구매간격_p25`,
    APPROX_QUANTILES(`재구매간격_일`, 4)[OFFSET(2)]  AS `재구매간격_p50`,
    APPROX_QUANTILES(`재구매간격_일`, 4)[OFFSET(3)]  AS `재구매간격_p75`
  FROM ipt_raw
  WHERE `재구매간격_일` IS NOT NULL
)

-- 5. 최종 JOIN: 'ALL'을 맨 위, 나머지 세그먼트는 LTV 내림차순
SELECT
  m.`세그먼트`,
  m.`고객수`,
  m.`ARPU`,
  m.`평균유지기간_월`,
  m.`LTV`,
  ipt.`재구매간격_평균_일`,
  ipt.`재구매간격_p25`,
  ipt.`재구매간격_p50`,
  ipt.`재구매간격_p75`
FROM ltv_metrics AS m
JOIN ipt_metrics AS ipt USING(`세그먼트`)
ORDER BY
  CASE WHEN m.`세그먼트` = 'ALL' THEN 0 ELSE 1 END,
  m.`LTV` DESC;
