# 이커머스 고객 세분화 분석 — 솔로 확장 프로젝트

## 프로젝트 컨텍스트

### 배경
2025년 3월 4인 팀 프로젝트로 수행한 데이콘 이커머스 고객 세분화 분석을 **단독으로 확장**하는 작업이다. 기존 프로젝트는 RFM·EDA·기초 코호트·카이제곱까지 수행했으나, SQL 중심 분석, 인과추론, A/B 테스트 설계, BI 대시보드가 빠져 있었다. 본 확장 프로젝트는 이 갭을 메우고, 동일 데이터로 분석 깊이를 한 단계 더 끌어올리는 것을 목적으로 한다.

### 분석 목표
1. 기존 Python 기반 분석을 BigQuery SQL로 재구축하며 윈도우 함수·CTE 기반 표현력 확보
2. 거래 기반 Funnel 정의 후 가장 큰 이탈 단계 식별
3. 쿠폰 사용과 리텐션의 **인과 효과**를 PSM으로 측정 (단순 상관과 비교)
4. 인과추론 결과를 바탕으로 A/B 테스트 설계서 작성
5. KPI·코호트·인과추론 결과를 통합한 Tableau 대시보드 구축
6. **(보완) GA Sample 데이터로 행동 단계 Funnel 추가 분석** — 거래 기반 funnel의 한계 보완 및 데이터 종류에 따른 funnel 정의 차이 비교

### 분석 철학 (이 프로젝트에서 지킬 것)
- **모델 성능보다 변수 설계와 방법 선택의 논리를 우선시한다.** 왜 이 방법인지, 왜 이 변수인지를 코드 주석과 분석 노트에 반드시 남긴다.
- **상관과 인과를 구분한다.** 기존 프로젝트는 카이제곱·피어슨 상관까지 갔으나, 본 확장에서는 인과 식별 가정과 selection bias 보정 논리를 명시적으로 다룬다.
- **결과는 의사결정에 연결되는 지점까지 끌고 간다.** 분석 → 발견 → 의사결정 액션 → 정량적 임팩트 추정이 한 흐름으로 이어져야 한다.

---

## 데이터 스키마

데이콘 이커머스 고객 세분화 분석 아이디어 경진대회 데이터. 2019년 1년치 거래.

### 원본 5개 테이블

**Onlinesales** — 거래 단위 로그
- `고객ID`, `거래ID`, `거래날짜`, `제품ID`, `제품카테고리`, `수량`, `평균금액`, `배송료`, `쿠폰상태`
- `쿠폰상태`는 3-way: `Used` / `Clicked` / `Not Used` ⚠️ 이분법 처리 금지

**Customer** — 고객 속성
- `고객ID`, `성별`, `고객지역`, `가입기간`(월)

**Discount** — 카테고리·월별 쿠폰 정보
- `월`, `제품카테고리`, `쿠폰코드`, `할인율` (10/20/30 세 단계)

**Marketing** — 일자별 광고 비용
- `날짜`, `오프라인비용`, `온라인비용`

**Tax** — 카테고리별 세율
- `제품카테고리`, `GST`

### Phase 5 보완 데이터: Google Analytics Sample
- **위치**: `bigquery-public-data.google_analytics_sample.ga_sessions_*`
- **기간**: 2016-08-01 ~ 2017-08-01 (Google Merchandise Store 실데이터)
- **레벨**: 세션 단위 + 히트(이벤트) 단위 중첩 구조
- **주요 필드**: `fullVisitorId`, `visitId`, `totals.transactions`, `totals.pageviews`, `hits.eCommerceAction.action_type` (1=상품 클릭, 2=상세, 3=장바구니, 5=결제 시작, 6=결제 완료)
- **차별점**: Phase 1 거래 단위 데이터에 없는 **세션·이벤트·페이지뷰**를 다룰 수 있어 행동 기반 funnel이 가능

### 거래금액 계산식
```
거래금액 = 수량 × 평균금액 × (1 - 할인율/100) × (1 + GST) + 배송료
```

### 기존 프로젝트가 식별한 5개 세그먼트
핵심 파트너 고객 / 성장형 고객 / 유망 고객 / 이탈 위험 고객 / 장기 비활성 고객

세그먼트 분류 로직은 기존 노트북의 `classify_customer_segment` 함수를 SQL CASE WHEN으로 그대로 이식한다.

---

## 환경

- **BigQuery Sandbox** (무료, 카드 불필요)
- **데이터셋 구조**:
  - `ecomm.raw` — 원본 5개 CSV 업로드
  - `ecomm.analysis` — 가공된 분석용 테이블 저장
- **Python**: 인과추론(PSM)·A/B 설계 시뮬레이션·시각화는 Python 사용
  - `pandas`, `numpy`, `statsmodels`, `causalinference` (또는 `dowhy`), `matplotlib`, `seaborn`
- **Tableau Public** — 최종 대시보드 게시

---

## 작업 Phase

Phase는 **순차 진행**한다. 각 Phase 끝에 검증 체크포인트가 있으며, 통과 전에 다음 Phase로 넘어가지 않는다.

### Phase 1 — SQL 기반 데이터 재구축 (Week 1)

**작업 범위**
1. 5개 CSV를 BigQuery `ecomm.raw`에 업로드
2. CTE 기반 통합 마스터 쿼리 작성 → `ecomm.analysis.customer_master` 테이블 생성
3. NTILE로 R/F/M 점수 산출, CASE WHEN으로 5개 세그먼트 분류
4. 거래 기반 Funnel 5단계 정의 후 전환율 산출

**검증 체크포인트**
- 세그먼트별 고객 수가 기존 노트북 결과와 ±5% 이내로 일치
- 세그먼트별 매출 비중에서 "핵심 파트너 + 성장형"이 약 70% 차지 확인
- Funnel에서 가장 큰 이탈 단계 1개 식별, 수치로 명시

**산출물**
- `sql/01_customer_master.sql`
- `sql/02_funnel.sql`
- `notebooks/01_validation.ipynb` (기존 Python 결과와의 매칭 검증)

---

### Phase 2 — 코호트·리텐션·LTV (Week 2)

**작업 범위**
1. 가입월(첫 구매월) 기준 Cohort 정의 → 월차별 리텐션 매트릭스 SQL로 작성
2. 세그먼트별 Cohort Heatmap 데이터 산출
3. LTV 추정 — 단순 LTV = ARPU × 평균 유지 기간
4. 재구매 간격(Inter-purchase Time) 분포 분석

**검증 체크포인트**
- 기존 노트북 코호트 결과와 1개월차 리텐션 수치 매칭
- "3월·6월 코호트 우수" 발견 재현
- LTV 산식과 가정을 분석 노트에 명시 (왜 단순 LTV로 시작했는지, 한계는 무엇인지)

**산출물**
- `sql/03_cohort_retention.sql`
- `sql/04_ltv.sql`
- `reports/ltv_methodology.md` — LTV 산식 선택 이유와 한계 정리

---

### Phase 3 — PSM 인과추론 (Week 3)

이 단계가 본 프로젝트의 핵심 차별점이다. 기존 프로젝트의 한계(상관관계까지만 다룸)를 정면으로 다루는 부분.

**처치/대조 정의**
- **처치군**: 쿠폰을 본 적 있고(Clicked 또는 Used) 실제 사용한 고객 (Used 거래 1건 이상)
- **대조군**: 쿠폰을 본 적 있으나(Clicked) 사용한 적 없는 고객 (Used 거래 0건)

이 정의는 "쿠폰 노출"이라는 selection 단계를 양쪽에서 동일하게 통제한다. Clicked vs Used 비교가 단순 Used vs Not Used 비교보다 selection bias가 낮은 이유를 분석 노트에 명시한다.

**공변량 (Propensity Score 추정 변수)**
모두 **처치 시점 이전**의 데이터로만 산출해야 한다. 처치 이후 변수는 leakage.

- 가입기간 (Customer)
- 성별, 고객지역 (Customer)
- 처치 이전 누적 거래수 (pre-treatment frequency)
- 처치 이전 평균 주문 금액 (pre-treatment AOV)
- 처치 이전 카테고리 다양성
- 첫 거래 월 (코호트 통제)

**비교 대상**
- 단순 카이제곱 결과 (기존 프로젝트와 동일 방법)
- PSM 매칭 후 ATT 추정
- 두 결과의 차이를 표로 정리

**추가 분석 (보너스)**
할인율 10/20/30 dose-response 분석. 사용 효과가 선형인지, 임계점이 있는지.

**검증 체크포인트**
- Propensity Score 분포가 두 그룹에서 충분히 겹침 (common support 확인)
- 매칭 후 공변량 균형 (SMD < 0.1)
- 단순 비교와 PSM 결과의 차이를 한 문장으로 요약 가능

**산출물**
- `notebooks/phase3_psm.ipynb`
- `reports/psm_methodology.md` — PSM 가정, 한계, 단순 비교와의 차이

---

### Phase 4 — A/B 테스트 설계 + 대시보드 (Week 4)

**A/B 테스트 설계서**

Phase 3에서 도출된 쿠폰 효과를 근거로 가설을 세운다. 예:
> "첫 구매 후 30일 내 자동 쿠폰 발송 시, 60일 리텐션이 X%p 상승한다."

설계서 구성:
- 가설 (귀무 / 대립)
- 처치 / 대조 정의
- 1차 지표 (60일 리텐션), 2차 지표 (1인당 매출, ROI)
- MDE, 표본 크기 산출 (power=0.8, α=0.05)
- 분석 방법 (검정 통계량 선택 이유 포함)
- Stopping rule, 부정적 시나리오 대응

**Tableau 대시보드**
- 세그먼트별 매출·리텐션 KPI
- Cohort Retention Heatmap
- 쿠폰 효과 (단순 비교 vs PSM 보정 비교)
- Funnel 전환율
- Tableau Public 게시

**검증 체크포인트**
- A/B 설계서가 그대로 실험팀에 전달 가능한 수준 (가설·지표·분석법 누락 없음)
- 대시보드가 의사결정자 관점에서 액션 아이템 3개 이상 도출 가능

**산출물**
- `reports/ab_test_design.md`
- `tableau/dashboard.twbx` + Public URL
- `README.md` 최종 정리 (프로젝트 전체 요약)

---

### Phase 5 — GA Sample 행동 단계 Funnel 비교 분석 (Week 5)

이 단계는 Phase 1~4의 보완이다. 데이콘 데이터는 거래 단위만 제공해 행동 funnel을 만들 수 없었고, 이를 보완하기 위해 GA Sample(세션·이벤트 로그)로 별도 funnel을 만들어 두 결과를 비교한다. 이 비교 자체가 핵심 인사이트가 된다.

**작업 범위**
1. BigQuery 공개 데이터셋 `bigquery-public-data.google_analytics_sample` 활용 (업로드 불필요)
2. UNNEST로 hits 배열 전개 → 세션·유저 단위 행동 funnel 정의
   - Stage 1: 방문 (세션 시작)
   - Stage 2: 상품 페이지뷰 (action_type=2)
   - Stage 3: 장바구니 담기 (action_type=3)
   - Stage 4: 결제 시작 (action_type=5)
   - Stage 5: 결제 완료 (action_type=6)
3. 단계별 전환율과 가장 큰 이탈 지점 식별
4. **Phase 1의 거래 기반 funnel과 비교표 작성** — 무엇이 다르고, 왜 다른지

**핵심 비교 포인트** (분석 노트에 반드시 포함)
- 거래 기반 funnel은 "구매한 사람들의 생애 단계"만 보여줌. 구매 이전 단계(검색·이탈)는 보이지 않음
- 행동 funnel은 "구매에 도달하지 못한 사람들"까지 포착 가능
- 두 funnel의 이탈 지점이 다른 이유 → 데이터 종류가 의사결정 범위를 결정한다는 메타 인사이트

**검증 체크포인트**
- 5단계 funnel 전환율이 산업 벤치마크(이커머스 평균 결제 전환율 2~3%)와 같은 자릿수
- Phase 1 거래 funnel과의 비교표 1장 완성
- "데이터 종류에 따라 funnel이 어떻게 달라지는가" 한 단락 분석 노트 작성

**산출물**
- `sql/05_behavioral_funnel.sql`
- `reports/funnel_comparison.md` — 두 funnel 비교 + 메타 인사이트

**주의사항**
- Phase 5는 별개 프로젝트가 아니라 **본 프로젝트의 부록**으로 포지셔닝한다. GitHub README와 자소서에서도 "데이콘 확장 프로젝트의 funnel 비교 분석"으로 묶어 서술
- 데이터셋이 다르므로 두 funnel의 절대 수치를 직접 비교하지 말고, "어떤 단계가 보이고/보이지 않는가"의 구조적 차이에 집중

---

## 코딩 컨벤션

### SQL
- CTE 사용. 서브쿼리 중첩 지양
- 모든 컬럼명은 원본 한글 그대로 유지 (BigQuery 한글 컬럼 지원)
- **한글 컬럼은 항상 백틱으로 감싼다.** BigQuery 식별자 규칙상 한글 자체는 허용되지만, 별칭 뒤 점 표기(`s.고객ID`)에서 파서가 토큰 분리를 실패하거나 한글 키워드 충돌 가능성이 있어 백틱이 가장 안전한 기본값이다.
  - 별칭과 함께 참조: `` s.`고객ID` ``, `` d.`할인율` ``
  - 별칭 없어도 동일: `` `거래금액` ``, `` `쿠폰상태` ``
  - 새 컬럼 별칭이 한글이면 `` AS `거래금액` `` 형태
  - 영문/숫자/언더스코어만으로 구성된 식별자(예: `GST`, `R_Score`, `Recency`)는 백틱 불필요
- 윈도우 함수, NTILE, CASE WHEN 적극 활용 (Python 대비 SQL 표현력을 보여주는 지점)
- 각 CTE 상단에 `-- 1. ...` 형태로 단계 주석

### Python
- 함수형 스타일. 한 셀에 한 가지 작업
- DataFrame 변수명은 의미 명시 (`df_temp` 금지, `customer_pre_treatment` 같은 이름)
- 통계 검정·모델링 결과는 반드시 가정과 한계를 주석으로

### 분석 노트 (md 파일)
진원이 자소서 스타일을 그대로 적용한다.

**금지**
- "~하고 싶습니다", "~할 예정입니다" 류 선언형 종결
- "당연하게도", "물론" 같은 자명함을 강조하는 표현
- "~로서" 어색한 자격 구문
- 한 문장에 `~고, ~고, ~고` 3연속 연결
- 분석의 자명함을 그대로 적는 문장 (예: "공개된 피로도 지표가 없어")

**지향**
- 변수 설계와 방법 선택 이유 중심
- "왜 단순 비교가 아니라 PSM인가" 같은 분석적 깊이가 드러나는 표현
- 결과 → 해석 → 의사결정 액션의 연결을 한 흐름으로 서술
- 임팩트는 정량적으로 (퍼센트, 절대값)

---

## Phase 시작 시 사용할 프롬프트 (Claude Code에 직접 입력)

### Phase 1 시작
```
CLAUDE.md를 읽고 Phase 1 작업을 시작해줘.

먼저 sql/ 디렉토리에 01_customer_master.sql을 작성해.
요구사항:
1. CLAUDE.md의 데이터 스키마와 거래금액 계산식 그대로 사용
2. CTE 4단계 구조: transactions → customer_rfm → rfm_scored → 최종
3. NTILE(4)로 R/F/M 점수, CASE WHEN으로 5개 세그먼트 분류
4. 세그먼트 분류 로직은 기존 노트북의 classify_customer_segment 함수를 그대로 이식

작성 후 쿼리의 각 CTE가 어떤 역할을 하는지 한 줄씩 요약해줘.
```

### Phase 2 시작
```
Phase 1 검증이 끝났다. 이제 Phase 2 (코호트·리텐션·LTV) 시작해줘.

sql/03_cohort_retention.sql 먼저 작성해.
- 가입월 = 첫 거래월로 정의
- 월차별 리텐션을 SQL 한 쿼리로 (피벗 구조)
- 결과는 코호트 × 월차 매트릭스
- 기존 노트북의 "3월·6월 코호트 우수" 패턴이 재현되는지 확인할 수 있어야 함
```

### Phase 3 시작
```
Phase 3 (PSM 인과추론) 시작.

notebooks/phase3_psm.ipynb 작성해.
- 처치/대조 정의는 CLAUDE.md에 명시된 그대로 (Clicked vs Used)
- 공변량도 CLAUDE.md 목록 사용, 모두 처치 시점 이전 데이터로 산출
- Propensity Score는 로지스틱 회귀
- 매칭 방법은 1:1 nearest neighbor (caliper=0.2 SD)
- 매칭 후 공변량 균형 (SMD) 표로 출력
- 단순 비교 결과와 PSM ATT를 한 표에 정리

분석 노트(reports/psm_methodology.md)에 PSM 가정 3가지(SUTVA, Ignorability, Common Support)가 이 데이터에서 어느 정도 충족되는지 명시.
```

### Phase 4 시작
```
Phase 4 (A/B 설계 + 대시보드) 시작.

먼저 reports/ab_test_design.md 작성.
가설은 Phase 3의 PSM 추정치를 baseline으로 사용:
- baseline 효과 크기 = Phase 3 ATT 결과
- MDE = baseline의 80% (보수적 설계)
- power=0.8, α=0.05
- 표본 크기 산출 코드 포함

Tableau 대시보드는 .twb 파일로 작성 가이드(레이아웃·필터·계산필드)만 markdown으로 정리.
```

### Phase 5 시작
```
Phase 5 (GA Sample 행동 단계 Funnel 비교) 시작.

sql/05_behavioral_funnel.sql 작성해.
- 데이터: bigquery-public-data.google_analytics_sample.ga_sessions_*
- 기간은 _TABLE_SUFFIX BETWEEN '20170101' AND '20170731' 정도로 제한 (쿼리 비용 절약)
- UNNEST(hits)로 이벤트 단계 전개
- action_type 기준 5단계 funnel (방문/상품뷰/장바구니/결제시작/결제완료)
- 유저 단위(fullVisitorId)로 각 단계 도달 여부 집계
- 단계별 전환율과 누적 전환율 둘 다 산출

쿼리 후 reports/funnel_comparison.md 작성:
- Phase 1 거래 기반 funnel 결과와 비교표 1개
- 두 funnel이 보여주는 이탈 지점이 다른 이유 분석
- "데이터 종류가 분석 범위를 결정한다"는 메타 인사이트 한 단락
- 절대 수치 비교 금지, 구조적 차이에 집중
```

---

## 면접 대비 — 이 프로젝트로 답할 수 있는 질문

이 섹션은 분석 마무리 단계에서 README에 정리할 내용의 초안이다.

**Q. SQL 활용 경험을 구체적으로 말해달라.**
→ 본 프로젝트에서 RFM 점수화·세그먼트 분류·코호트 리텐션·LTV를 모두 BigQuery SQL로 작성. 윈도우 함수(NTILE), CTE 다층 구조, FORMAT_DATE 등을 활용해 Python 100줄 분량을 SQL 한 쿼리로 표현. GitHub에 SQL 파일 공개.

**Q. A/B 테스트 경험은?**
→ PSM 인과추론으로 도출한 쿠폰 효과를 baseline으로 설계서 작성. MDE·표본 크기·1·2차 지표·stopping rule까지 포함.

**Q. 상관과 인과를 어떻게 구분하는가?**
→ 본 프로젝트가 직접 다룬 주제. 팀 프로젝트에서 카이제곱으로 "쿠폰-리텐션 상관"을 확인했으나, 쿠폰 사용 자체가 활성 고객에게 더 자주 노출되는 selection bias가 있다고 판단. PSM으로 보정한 결과 단순 비교 대비 효과 크기가 X% 차이.

**Q. 대시보드 경험은?**
→ Tableau Public에 게시한 본 프로젝트 대시보드. 코호트 히트맵, Funnel 전환율, PSM 보정 전후 비교 시각화. URL 공유 가능.

**Q. Funnel 분석 경험은?**
→ 두 가지 형태의 funnel을 다뤘다. 거래 단위 데이터로는 "가입→첫구매→재구매→충성" 생애 단계 funnel을, GA Sample 세션 로그로는 "방문→상품뷰→장바구니→결제" 행동 단계 funnel을 각각 SQL로 구성. 두 funnel의 이탈 지점이 다른 이유를 분석하며 "데이터 종류가 의사결정 가능 범위를 결정한다"는 관점을 정리.
