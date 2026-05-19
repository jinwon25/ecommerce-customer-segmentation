-- ============================================================================
-- Phase 1 / Step 2. 거래 기반 5단계 Funnel
--   원천: `ecomm-extension.ecomm_analysis.customer_master`
--
-- Funnel 정의 (CLAUDE.md Phase 1 명세):
--   Stage 1 — 가입       : customer_master 전체 행
--   Stage 2 — 첫 구매    : Frequency >= 1
--   Stage 3 — 재구매     : Frequency >= 2
--   Stage 4 — 충성       : Frequency >= 5
--   Stage 5 — 핵심 고객  : Customer_Segment IN ('핵심 파트너 고객','성장형 고객')
--
-- 주의: customer_master 는 거래가 1건 이상인 고객만 포함하므로 정의상
--       Stage 1 == Stage 2 (1→2 전환율 100%). 원본 Customer 테이블의 비거래
--       가입자까지 포함한 "진짜 가입→첫구매" 전환율을 보려면 Stage 1을
--       ecomm_raw.Customer 로 재정의해야 한다. 본 쿼리는 명세 그대로 작성하고,
--       이 한계는 phase1 분석 노트에 명시한다.
--
-- 출력: 단계별 도달 인원, 단계 전환율, 이탈 인원·률, 누적 전환율, 최대 이탈 마커
-- 코딩 컨벤션: 한글 컬럼은 백틱.
-- ============================================================================

WITH stage_counts AS (
  -- 1. 한 행으로 각 stage 도달 인원 집계 (테이블 1회 스캔)
  SELECT
    COUNT(*)                                                          AS stage1,
    COUNTIF(Frequency >= 1)                                           AS stage2,
    COUNTIF(Frequency >= 2)                                           AS stage3,
    COUNTIF(Frequency >= 5)                                           AS stage4,
    COUNTIF(Customer_Segment IN ('핵심 파트너 고객', '성장형 고객'))  AS stage5
  FROM `ecomm-extension.ecomm_analysis.customer_master`
),

funnel_long AS (
  -- 2. wide → long 변환. 직전 단계 인원을 같은 행에 두어 전환율 계산이 단순해진다.
  SELECT 1 AS `단계`, '가입'       AS `단계명`, stage1 AS `도달인원`, CAST(NULL AS INT64) AS `직전인원` FROM stage_counts
  UNION ALL
  SELECT 2,           '첫 구매',                stage2,                stage1                            FROM stage_counts
  UNION ALL
  SELECT 3,           '재구매',                 stage3,                stage2                            FROM stage_counts
  UNION ALL
  SELECT 4,           '충성',                   stage4,                stage3                            FROM stage_counts
  UNION ALL
  SELECT 5,           '핵심 고객',              stage5,                stage4                            FROM stage_counts
),

funnel_metrics AS (
  -- 3. 단계 전환율·이탈률·누적 전환율 계산
  --    단계전환율 = 도달 / 직전,  이탈률 = (직전 - 도달) / 직전
  --    누적전환율 = 도달 / Stage1 도달  (분모는 OVER ()로 전체 최대값 = Stage 1)
  SELECT
    `단계`,
    `단계명`,
    `도달인원`,
    `직전인원` - `도달인원`                                          AS `이탈인원`,
    ROUND(SAFE_DIVIDE(`도달인원`, `직전인원`) * 100, 2)              AS `단계전환율_pct`,
    ROUND(SAFE_DIVIDE(`직전인원` - `도달인원`, `직전인원`) * 100, 2) AS `이탈률_pct`,
    ROUND(`도달인원` / MAX(`도달인원`) OVER () * 100, 2)             AS `누적전환율_pct`
  FROM funnel_long
)

-- 4. 가장 큰 이탈 지점 1줄 코멘트
--    이탈률이 NULL이 아닌 단계 중 최댓값을 가진 행에 마커 부여.
--    동률이 발생하면 둘 다 표시(데이터 정직성).
SELECT
  `단계`,
  `단계명`,
  `도달인원`,
  `이탈인원`,
  `단계전환율_pct`,
  `이탈률_pct`,
  `누적전환율_pct`,
  CASE
    WHEN `이탈률_pct` IS NOT NULL
     AND `이탈률_pct` = MAX(`이탈률_pct`) OVER ()
      THEN '◀ 가장 큰 이탈 지점'
    ELSE ''
  END AS `비고`
FROM funnel_metrics
ORDER BY `단계`;
