-- ============================================================================
-- Phase 2 / Step 1. 코호트 × 월차 리텐션 매트릭스
--   결과 테이블: `ecomm-extension.ecomm_analysis.cohort_retention`
--   원천: `ecomm-extension.ecomm_raw.Onlinesales`
--
-- 코호트 정의 (CLAUDE.md Phase 2 명세):
--   가입월 = 고객의 첫 거래월 (= DATE_TRUNC(첫 거래날짜, MONTH))
--   월차   = 해당 거래월 - 가입월 (월 단위 차이, 0~11)
--   리텐션 = 해당 가입월 코호트 중 월차 N개월차에 1건 이상 거래한 고객 비율 (%)
--
-- 결과 구조:
--   행 = 가입월 (2019-01-01 ~ 2019-12-01)
--   열 = m0 ~ m11 (월차)
--   값 = 리텐션(%)
--   m0는 항상 100.0 (정의상 가입월 = 첫 거래월이므로 모든 고객이 활동)
--   12월 코호트는 m0만 값이 있고 m1~m11은 NULL (관측 기간 종료)
--
-- 검증 포인트:
--   - "3월·6월 코호트 우수" 패턴이 매트릭스에서 재현되는가
--     (해당 행의 m1, m2, ... 값이 인접 코호트보다 높게 나타나는지)
--   - 1개월차(m1) 평균 리텐션이 노트북의 "10% 미만" 결과와 매칭되는가
--
-- 코딩 컨벤션: 한글 컬럼은 백틱.
-- ============================================================================

CREATE OR REPLACE TABLE `ecomm-extension.ecomm_analysis.cohort_retention` AS

WITH first_purchase AS (
  -- 1. 고객별 가입월 = 첫 거래월
  SELECT
    `고객ID`,
    DATE_TRUNC(MIN(`거래날짜`), MONTH) AS `가입월`
  FROM `ecomm-extension.ecomm_raw.Onlinesales`
  GROUP BY `고객ID`
),

activity AS (
  -- 2. 각 거래에 가입월·월차 부착
  --    한 고객이 같은 월에 여러 번 거래해도 다음 CTE의 COUNT(DISTINCT)로 1회만 카운트
  SELECT
    s.`고객ID`,
    fp.`가입월`,
    DATE_DIFF(DATE_TRUNC(s.`거래날짜`, MONTH), fp.`가입월`, MONTH) AS `월차`
  FROM `ecomm-extension.ecomm_raw.Onlinesales` AS s
  JOIN first_purchase AS fp USING(`고객ID`)
),

cohort_size AS (
  -- 3. 가입월별 가입자 수 (리텐션의 분모)
  SELECT
    `가입월`,
    COUNT(*) AS `가입자수`
  FROM first_purchase
  GROUP BY `가입월`
),

retention_long AS (
  -- 4. 가입월 × 월차별 활동 고객 수와 리텐션 비율 (long format)
  SELECT
    a.`가입월`,
    cs.`가입자수`,
    a.`월차`,
    COUNT(DISTINCT a.`고객ID`) AS `활동고객수`,
    ROUND(COUNT(DISTINCT a.`고객ID`) / cs.`가입자수` * 100, 1) AS `리텐션_pct`
  FROM activity AS a
  JOIN cohort_size AS cs USING(`가입월`)
  GROUP BY a.`가입월`, cs.`가입자수`, a.`월차`
)

-- 5. PIVOT: 가입월 행 × 월차 열 매트릭스 (한 쿼리, 한 행에 코호트 전체 리텐션 곡선)
--    가입자수도 함께 노출하여 코호트 크기 가중 해석이 가능하도록 한다.
SELECT *
FROM (
  SELECT `가입월`, `가입자수`, `월차`, `리텐션_pct`
  FROM retention_long
)
PIVOT (
  MAX(`리텐션_pct`) FOR `월차` IN (
    0  AS m0,  1  AS m1,  2  AS m2,  3  AS m3,
    4  AS m4,  5  AS m5,  6  AS m6,  7  AS m7,
    8  AS m8,  9  AS m9,  10 AS m10, 11 AS m11
  )
)
ORDER BY `가입월`;
