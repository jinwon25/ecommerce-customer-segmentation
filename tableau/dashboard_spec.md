# Tableau 대시보드 설계서

본 프로젝트 Phase 1~3 분석 결과를 한 화면에서 의사결정자가 확인 가능한 형태로 통합. Tableau Public에 게시해 URL만으로 외부에서도 접근 가능하게 한다. `.twbx` 파일과 게시는 진원이가 직접 작업하며, 본 문서는 그 작업의 단계별 가이드.

## 1. 대시보드 목적

운영팀·마케팅팀이 별도 노트북 실행이나 GitHub 탐색 없이 한 URL로 다음 4가지를 확인 가능하게 한다.

- 5개 RFM 세그먼트별 매출·LTV 집중도
- 12개월 코호트 리텐션 패턴
- 거래 기반 Funnel의 핵심 이탈 지점
- 쿠폰 사용의 인과 효과 (단순 비교 vs PSM 보정)

채용 담당자 관점에서는 본 대시보드 URL이 "분석 결과를 의사결정자에게 전달하는 능력"의 직접 증거가 된다.

## 2. 대시보드 구조 — 1장 단일 레이아웃

전체 캔버스 1,440 × 900 (Tableau 기본 desktop 사이즈). 4개 영역으로 분할.

```
┌─────────────────────────────────────────────────────────────┐
│ 상단 헤더 (높이 90px, 약 10%)                                  │
│   제목 + 필터 3개 (세그먼트 / 가입월 / 지역)                     │
├─────────────────────────────────────────────────────────────┤
│ KPI 카드 (높이 135px, 약 15%)                                  │
│   [총 고객수] [총 매출] [평균 LTV] [평균 60일 재구매율]              │
├──────────────────────────┬──────────────────────────────────┤
│ 좌상 (50%) — 세그먼트 매출 │ 우상 (50%) — 코호트 리텐션 히트맵    │
│ 비중 도넛                  │                                  │
│                          │                                  │
│ ──────────────────────── │ ──────────────────────────────── │
│ 좌하 (50%) — Funnel       │ 우하 (50%) — 쿠폰 효과 비교         │
│ 전환율 막대                │ (단순 vs PSM ATT)                  │
│                          │                                  │
├─────────────────────────────────────────────────────────────┤
│ 푸터 (높이 135px, 약 15%)                                      │
│   데이터 출처·기간·주요 결과 3줄 요약·GitHub 리포 링크              │
└─────────────────────────────────────────────────────────────┘
```

### 상단 헤더 (높이 10%)

- 제목: **"이커머스 고객 세분화 대시보드 — RFM · 코호트 · 인과추론"**
- 필터 3개 (가로 정렬, 모든 차트에 연동):
  - 세그먼트 (5+1개): 핵심 파트너 / 성장형 / 유망 / 이탈 위험 / 장기 비활성 / 기타
  - 가입월 (12개): 2019-01 ~ 2019-12
  - 고객지역 (5개): California / Chicago / New Jersey / New York / Washington DC

### KPI 카드 4개 (높이 15%)

각 카드는 큰 숫자 + 작은 라벨 + 비교 메시지. 모든 데이터 소스는 `tableau/data/*.csv`.

| 카드 | 값 산출 | 데이터 소스 + 컬럼 | 표시 형식 |
|---|---|---|---|
| 총 고객 수 | `SUM([고객수])` 또는 `ALL` 행의 [고객수] | `ltv_summary_export.csv` | `1,468명` |
| 총 매출 | `SUM([고객수] * [ARPU])` (`ALL` 행 제외) | `ltv_summary_export.csv` | `$5.4M` 형태 |
| 평균 LTV (가중) | `SUM([고객수] * [LTV]) / SUM([고객수])` | `ltv_summary_export.csv` | `$7,773` |
| **PSM 보정 효과** | `outcome='60일 리텐션 (binary)' AND method='PSM ATT'` 행의 `estimate × 100` | `psm_results.csv` | `+33.3pp` |

KPI 4번의 정의 선택 이유: 단순 평균 재구매율보다 *인과추론으로 보정된 ATT*를 직접 노출하면 채용 담당자에게 분석 깊이가 더 명확하게 전달된다. 표시 단위는 percentage point (`pp`)로 통상적 binary ATT 표기를 따른다.

평균 LTV의 *가중 평균* 식 (`SUM(고객수 × LTV) / SUM(고객수)`)을 쓰는 이유: 단순 `AVG(LTV)`는 세그먼트별 고객 수 차이를 무시해 작은 세그먼트(예: 기타 n=49)에 과대 가중. 가중 평균이 1,468명 전체의 LTV 평균을 정확히 산출한다.

### 메인 차트 4개 (높이 60%, 2×2 그리드)

**좌상 — 세그먼트별 매출 비중 (Donut chart)**
- 데이터: `ltv_summary_export.csv` (Calculated field로 매출 derive — customer_master 원본 export 회피로 데이콘 라이선스 부담 0)
- Calculated field 생성: **Analysis → Create Calculated Field → 이름 `매출_세그먼트별` → 수식 `[고객수] * [ARPU]`**
  - 식 근거: `ARPU = AVG(Monetary)`는 누적 평균이므로 `고객수 × ARPU` = 세그먼트별 누적 총매출. `[고객수] * [LTV]`는 미래 가치 추정이라 도넛(현재 비중) 부적합.
- 'ALL' 행은 필터로 제외 (도넛은 세그먼트 비중이라 ALL 미포함)
- 강조: 핵심 파트너 (#E07B5B) + 성장형 (#4A90D9) 두 조각을 도넛 외곽으로 살짝 빼서 (`Tableau Show me → Donut`) 시각적 분리
- 라벨: 각 세그먼트명 + 비중(%) + `[매출_세그먼트별]`
- 중앙 텍스트: "핵심+성장형 = 68.2%" (Phase 2 발견)

**우상 — 코호트 리텐션 히트맵**
- 데이터: `cohort_retention_export.csv` (가입월 × 월차 long format)
- x축: 월차 (m0~m11), y축: 가입월 (2019-01 ~ 2019-12)
- 색상: 빨강(낮음) → 노랑 → 초록(높음), `Sequential Red-Green` 팔레트
- 셀 텍스트: 리텐션 %
- 우측 보조 막대: 각 코호트 가입자수 (Tableau의 dual axis 또는 side bar)
- 강조: 1월 코호트 m5~m7 셀에 네이비 테두리 (수동 annotation)

**좌하 — Funnel 전환율 (가로 막대)**
- 데이터: `funnel_export.csv` (`sql/02_funnel.sql` 결과 그대로)
- 5개 stage 가로 막대 (위→아래: 가입 → 첫구매 → 재구매 → 충성 → 핵심)
- 각 막대 옆에 도달 인원 + 단계 전환율 % 라벨
- Stage 2→3 (재구매) 막대는 #E07B5B (Phase 1 핵심 발견 강조)
- 나머지 막대는 #4A90D9

**우하 — 쿠폰 효과 비교 (점·CI 비교 차트)**
- 데이터: `psm_results.csv` (단순 차이 / PSM ATT × 60일 리텐션 / 60일 매출)
- y축: 방법 (단순 차이 / PSM ATT), x축: ATT 추정치
- 점 + 95% CI 가로 막대 (forest plot 형태)
- 60일 리텐션 / 60일 매출 두 패널 (Tableau의 columns에 outcome 분할)
- 0 기준선 수직 점선 (Reference line)

### 푸터 (높이 15%)

3줄 텍스트 + 1개 링크:
- 데이터 출처: 데이콘 이커머스 고객 세분화 분석 데이터 (2019년 1년치, 거래 52,924건, 고객 1,468명)
- 주요 결과: ① 핵심+성장형 매출 68.2% ② 첫구매→재구매 8.51% 이탈 ③ 쿠폰 PSM ATT +33.3%p
- 상세 분석: [github.com/jinwon25/ecommerce-customer-segmentation/tree/main/reports](https://github.com/jinwon25/ecommerce-customer-segmentation/tree/main/reports)

## 3. 데이터 소스 — CSV Export 4개

BigQuery 콘솔에서 각 쿼리 실행 → 결과 화면 우측 **"Save Results → CSV (local file)"** 로 다운로드. 파일 위치: `tableau/data/`.

데이콘 원본 데이터 재배포 회피를 위해 `customer_master`의 *개별 고객 행* CSV는 commit하지 않는다. 도넛·KPI는 모두 `segment_ltv_summary`에서 derive (Calculated field 사용).

### 3.1 `cohort_retention_export.csv` — Long format (히트맵)

`cohort_retention` 테이블은 PIVOT 결과라 wide format. Tableau 히트맵에는 long format이 더 자연스러워 다시 unpivot.

```sql
SELECT
  `가입월`,
  `가입자수`,
  `월차`,
  `리텐션_pct`
FROM (
  SELECT
    `가입월`,
    `가입자수`,
    m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11
  FROM `ecomm-extension.ecomm_analysis.cohort_retention`
)
UNPIVOT (
  `리텐션_pct` FOR `월차` IN (
    m0  AS '0',  m1  AS '1',  m2  AS '2',  m3  AS '3',
    m4  AS '4',  m5  AS '5',  m6  AS '6',  m7  AS '7',
    m8  AS '8',  m9  AS '9',  m10 AS '10', m11 AS '11'
  )
)
ORDER BY `가입월`, CAST(`월차` AS INT64);
```

### 3.2 `funnel_export.csv` — Funnel 결과

```sql
-- sql/02_funnel.sql의 결과를 그대로 export.
-- 별도 테이블 저장은 안 되어 있어 동일 쿼리를 콘솔에서 실행 후 export.
-- (또는 02_funnel.sql 결과를 ecomm_analysis.funnel_results 테이블로 한 번 저장 후 SELECT)
SELECT * FROM `ecomm-extension.ecomm_analysis.funnel_results`
ORDER BY `단계`;
```

> **운영 메모**: 02_funnel.sql이 `CREATE OR REPLACE TABLE`로 시작하지 않으므로 결과를 한 번 테이블로 저장한 후 export. 또는 콘솔에서 SQL 결과를 직접 다운로드.

### 3.3 `psm_results.csv` — 쿠폰 효과 비교 (Phase 3)

Phase 3 노트북 셀 12의 `comparison` 변수를 그대로 CSV로 export. BigQuery 테이블이 아닌 노트북 변수라 Python에서 `comparison.to_csv('tableau/data/psm_export.csv', index=False)` 한 줄로 저장. 또는 다음 데이터를 수동 입력:

| outcome | method | n_treat | n_ctrl | estimate | ci_lower | ci_upper |
|---|---|---|---|---|---|---|
| 60일 리텐션 (binary) | 단순 차이 | 1208 | 72 | 0.2555 | 0.2014 | 0.3024 |
| 60일 리텐션 (binary) | PSM ATT | 72 | 72 | 0.3333 | 0.2083 | 0.4444 |
| 60일 매출 (continuous) | 단순 차이 | 1208 | 72 | 487.46 | 403.33 | 601.84 |
| 60일 매출 (continuous) | PSM ATT | 72 | 72 | 947.32 | 300.34 | 1985.72 |

### 3.4 `ltv_summary_export.csv` — 세그먼트 LTV 요약

```sql
SELECT * FROM `ecomm-extension.ecomm_analysis.segment_ltv_summary`
ORDER BY
  CASE WHEN `세그먼트` = 'ALL' THEN 0 ELSE 1 END,
  LTV DESC;
```

KPI 카드 3종(총 고객수·총 매출·평균 LTV)과 시트 1 도넛(매출_세그먼트별 Calculated field)의 메인 소스.

## 4. Tableau 작업 가이드 — 진원이 직접 단계

### Step 1 — 환경 세팅 (예상 30분)

1. [Tableau Public](https://public.tableau.com) 무료 계정 가입 (이메일 + 비밀번호)
2. [Tableau Desktop Public Edition](https://public.tableau.com/en-us/s/download) 다운로드 (Windows 무료)
3. 설치 후 로그인
4. 한글 폰트 — Tableau는 시스템 폰트를 사용. NanumGothic 시스템 설치 상태면 자동 인식. 미설치 시:
   - [네이버 나눔글꼴 다운로드](https://hangeul.naver.com/font)
   - 압축 해제 후 `NanumGothic.ttf`를 `C:\Windows\Fonts\` 에 복사
   - Tableau 재시작

### Step 2 — 데이터 로드 (예상 30분)

1. Tableau 시작 → **Connect → To a File → Text file**
2. `tableau/data/ltv_summary_export.csv` 선택 (도넛·KPI의 메인 소스)
3. 좌측 데이터 패널에 테이블 추가
4. 나머지 3개 CSV (`cohort_retention_export`, `funnel_export`, `psm_results`)도 동일 방식으로 import
5. **데이터 관계**: 4개 모두 독립 테이블로 사용. 시트마다 한 소스만 참조하므로 Relationships 정의 불필요. 필터(세그먼트·가입월·고객지역)는 시트별로 따로 적용 후 대시보드에서 연동.

### Step 3 — 시트 4개 작성 (예상 2시간)

#### 시트 1: 세그먼트 매출 도넛

1. 새 워크시트 → 이름 "세그먼트 매출 비중", 데이터 소스 = `ltv_summary_export`
2. **Analysis → Create Calculated Field**:
   - 이름: `매출_세그먼트별`
   - 수식: `[고객수] * [ARPU]`
3. 필터: `세그먼트 ≠ 'ALL'` (도넛은 세그먼트 비중)
4. `세그먼트` → Color
5. `SUM([매출_세그먼트별])` → Angle
6. Mark type → **Pie**
7. 도넛 효과: dual axis로 작은 원을 중앙에 배치 (Tableau 표준 트릭, 검색어 "Tableau donut chart")
8. 라벨: `세그먼트` + `[매출_세그먼트별]` + 비중%
9. 색상: 5절 색상 팔레트 참조해 세그먼트별 RGB 수동 지정

#### 시트 2: 코호트 히트맵

1. 새 워크시트 → 이름 "코호트 리텐션"
2. `cohort_retention_export.월차` (CAST INT) → Columns
3. `cohort_retention_export.가입월` → Rows (월 단위 그룹)
4. `리텐션_pct` → Color
5. Mark type → **Square**
6. 색상 팔레트: Color Edit → **Red-Green Diverging** (Reversed 체크해서 빨강이 낮음 / 초록이 높음)
7. Range: 0 ~ 30 (Phase 2 히트맵과 일치)
8. NULL 셀: Color → Special values → 회색
9. 셀 텍스트: 리텐션 %
10. (선택) 1월 코호트 m5~m7 강조: Annotation으로 박스 그리기 → 색 #1F4E8C (네이비)

#### 시트 3: Funnel 막대

1. 새 워크시트 → 이름 "Funnel 전환율"
2. `funnel_export.단계명` → Rows
3. `SUM(도달인원)` → Columns
4. Mark type → **Bar**
5. 정렬: `단계` 오름차순 (가입 위, 핵심 고객 아래)
6. 라벨: `도달인원` + `단계전환율_pct`
7. 색상: Stage 2→3 (재구매) 행만 #E07B5B, 나머지 #4A90D9 — Calculated field로:
   ```
   IF [단계명] = '재구매' THEN '강조' ELSE '기본' END
   ```
   를 Color에 두고 두 색상 수동 지정

#### 시트 4: 쿠폰 효과 비교

1. 새 워크시트 → 이름 "쿠폰 효과 (PSM)"
2. `psm_export.outcome` → Columns
3. `psm_export.method` → Rows
4. `estimate` → 점, `ci_lower`, `ci_upper` → 가로 막대 (Reference band)
5. Mark type 조합: 점 + line (forest plot 패턴, 검색어 "Tableau forest plot")
6. Reference line: x = 0 (검정 점선)
7. 색상: method별 — 단순 차이 (회색 #999), PSM ATT (주황 #E07B5B)

### Step 4 — 대시보드 통합 (예상 1시간)

1. **New Dashboard** → 사이즈 1,440 × 900 (Desktop)
2. 시트 4개를 2×2 grid로 드래그
3. 상단에 Text object → 제목 입력
4. KPI 카드 4개: 새 시트 4개 추가 (각 1개의 숫자만 표시, "BANs" 형태)
5. 필터 추가: 세그먼트·가입월·고객지역 각각 우클릭 → Apply to All Worksheets
6. 하단 푸터: Text object 4개 (출처·기간·결과·링크)

### Step 5 — Tableau Public 게시 (예상 30분)

1. File → **Save to Tableau Public As...**
2. 로그인 → 워크북 이름 "이커머스 고객 세분화 대시보드"
3. 저장 완료 시 자동으로 브라우저에서 게시 URL 열림 (예: `public.tableau.com/views/이커머스고객세분화/dashboard1`)
4. URL 복사 → README.md 의 적절한 위치에 추가 (예: `## Tableau Public`)

## 5. 디자인 가이드 — Phase 2·3 시각화와 통일

### 색상 팔레트

`SEG_COLORS` (Phase 2 노트북에서 그대로 사용) → Tableau RGB:

| 세그먼트 | Hex | RGB | Tableau 입력값 |
|---|---|---|---|
| 핵심 파트너 고객 | `#E07B5B` | 224, 123, 91 | 224, 123, 91 |
| 성장형 고객 | `#4A90D9` | 74, 144, 217 | 74, 144, 217 |
| 유망 고객 | `#88B04B` | 136, 176, 75 | 136, 176, 75 |
| 이탈 위험 고객 | `#F1C40F` | 241, 196, 15 | 241, 196, 15 |
| 장기 비활성 고객 | `#7F8C8D` | 127, 140, 141 | 127, 140, 141 |
| 기타 | `#BDC3C7` | 189, 195, 199 | 189, 195, 199 |

Tableau에서 수동 색상 입력: **Color → Edit Colors → 세그먼트 더블클릭 → RGB 입력**.

### 공통 디자인 토큰

- 배경: 흰색 `#FFFFFF`
- 그리드·박스 테두리: `#F8F9FA` (Phase 2 카드와 동일)
- 강조 색: `#E07B5B` (재구매 이탈 / PSM ATT)
- 폰트:
  - 영문: Arial (Tableau 기본 호환)
  - 한글: NanumGothic (시스템 폰트 설치 전제)
- 폰트 사이즈:
  - 제목: 18pt bold
  - 차트 타이틀: 14pt bold
  - 본문 라벨: 11pt
  - KPI 카드 숫자: 32pt bold

## 6. 진원이 직접 작업 — 예상 시간

| 단계 | 예상 시간 |
|---|---|
| Step 1 — 환경 세팅 | 30분 |
| Step 2 — CSV import + 관계 정의 | 30분 |
| Step 3 — 시트 4개 작성 | 2시간 |
| Step 4 — 대시보드 통합 + 필터 | 1시간 |
| Step 5 — Tableau Public 게시 + URL 추가 | 30분 |
| 디자인 미세 조정 (색상·정렬·여백) | 1시간 |
| **합계** | **약 5시간** |

Tableau 처음이면 +1~2시간 (시트 4의 forest plot이 가장 까다로움 — 검색어 "Tableau forest plot dual axis" 참고).

## 7. 자소서·이력서 활용

본 대시보드 URL의 활용 지점:
- 자소서 "분석 결과를 의사결정자에게 전달한 경험" 항목의 직접 증거
- 이력서 프로젝트 섹션의 산출물 링크
- LinkedIn 프로필 Featured 섹션
- 면접 시 "GitHub과 별개로 한 화면에서 결과 확인 가능한가" 질문에 즉답

채용 담당자가 Tableau Public URL을 클릭하면 30초 안에 본 프로젝트의 핵심 4가지(세그먼트·코호트·Funnel·인과추론)를 동시에 본다. 노트북 실행 없이도 분석가의 결과 전달 능력을 평가 가능한 형태.

## 8. 한계와 다음 단계

- 본 대시보드는 *정적 데이터* (2019년 1년치) 기반. 운영 데이터 연동 시 BigQuery → Tableau 직접 연결로 자동 갱신 가능 (Tableau Desktop 유료 버전, 본 프로젝트 범위 밖).
- Phase 5 GA Sample 행동 funnel을 별도 시트로 추가하면 거래 단위 ↔ 행동 단위 비교가 한 화면에 들어옴. Phase 5 완료 후 본 대시보드 v2로 갱신.
