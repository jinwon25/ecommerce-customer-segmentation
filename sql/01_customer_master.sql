-- ============================================================================
-- Phase 1 / Step 1. 고객 마스터 테이블 생성
--   결과: `ecomm-extension.ecomm_analysis.customer_master`
--   원천: `ecomm-extension.ecomm_raw.{Onlinesales, Discount, Tax}`
--
-- 거래금액 산식 (CLAUDE.md 명세):
--     거래금액 = 수량 × 평균금액 × (1 - 할인율/100) × (1 + GST) + 배송료
--
-- 산식 적용 규칙 (이 쿼리의 해석):
--   1) 할인율은 `쿠폰상태` = 'Used'인 거래에만 적용한다.
--      - 'Clicked' / 'Not Used'는 노출되었으나 사용되지 않았으므로 실결제에
--        할인이 반영되지 않는다고 본다.
--      - 일괄 적용하면 비사용자 매출이 실제보다 과소 추정되어 Monetary 왜곡.
--   2) Discount 테이블은 1~3월(Jan/Feb/Mar) 행만 존재한다. 4월 이후 거래는
--      LEFT JOIN 후 COALESCE로 할인율 0% 처리한다.
--   3) 노트북은 `총거래액 = 수량 × 평균금액` 단순식을 사용했으므로 본 쿼리의
--      Monetary 절대값은 노트북과 차이가 난다. 다만 NTILE(4)는 단조 변환에
--      invariant이므로 R/F/M 분위 점수와 세그먼트 분포는 ±5% 안에서 일치
--      가능한 범위라 본다(Phase 1 검증 체크포인트에서 확인).
--
-- 코딩 컨벤션:
--   - 한글 컬럼은 백틱으로 감싼다. 영문/언더스코어 컬럼(GST, R_Score 등)은 미사용.
--
-- CTE 구조: transactions → customer_rfm → rfm_scored → 최종 세그먼트
-- ============================================================================

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.customer_master` AS

WITH transactions AS (
  -- 1. 거래 라인 단위: 원본에 할인율·세율 조인, 거래금액 계산
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
      + s.`배송료` AS `거래금액`
  FROM `ecomm-extension.ecomm_raw.Onlinesales` AS s
  LEFT JOIN `ecomm-extension.ecomm_raw.Discount` AS d
         ON s.`제품카테고리` = d.`제품카테고리`
        AND FORMAT_DATE('%b', s.`거래날짜`) = d.`월`
  LEFT JOIN `ecomm-extension.ecomm_raw.Tax` AS t
         ON s.`제품카테고리` = t.`제품카테고리`
),

customer_rfm AS (
  -- 2. 고객 단위 RFM 원자료
  --    기준일 = 데이터 마지막 거래일(고정 스냅숏). 노트북 정의와 동일.
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
  -- 3. NTILE(4)로 점수화
  --    - R: 최근일수록 점수↑ → Recency 큰 값(오래된)이 1점, 작은 값이 4점
  --         pd.qcut(Recency, 4, labels=[4,3,2,1])와 동치되도록 ORDER BY DESC
  --    - F·M: 클수록 점수↑ → ORDER BY ASC. NTILE은 단조 변환에 invariant이라
  --      노트북의 log1p 변환은 SQL에서 생략해도 동일 분위가 나온다.
  SELECT
    `고객ID`,
    Recency,
    Frequency,
    Monetary,
    NTILE(4) OVER (ORDER BY Recency   DESC) AS R_Score,
    NTILE(4) OVER (ORDER BY Frequency ASC)  AS F_Score,
    NTILE(4) OVER (ORDER BY Monetary  ASC)  AS M_Score
  FROM customer_rfm
)

-- 4. 5개 세그먼트 분류 (classify_customer_segment 이식)
--    CASE WHEN 평가 순서가 곧 if/elif 우선순위. 위 조건에 먼저 매칭되는 행은
--    아래 조건 평가에서 제외되므로 노트북과 동일한 우선 분류가 보장된다.
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
