# SQL 실행 순서

모든 쿼리는 **BigQuery Standard SQL 기준**이다. 프로젝트 ID `ecomm-extension`과 데이터셋 이름은 실행 환경에 맞게 바꾼다.

1. `00_data_quality.sql` — 키 중복, 필수값, 기간, 조인 row inflation 확인
2. `01_customer_master.sql` — 거래금액과 RFM 고객 마스터 생성
3. `02_purchase_activity_ladder.sql` — 전체 기간 거래ID 개수 기반 활동 단계 집계
4. `03_purchase_cohort_retention.sql` — 첫 구매월 × 월차 구매 리텐션(long format)
5. `04_customer_value.sql` — 관측 누적매출·활성월·구매일·IPT를 분리한 현재 고객가치 지표
6. `05_coupon_observational_population.sql` — 쿠폰 관찰 비교용 사전 공변량·60일 outcome 생성

BigQuery 인증이 없는 환경에서는 `scripts/build_coupon_population.py`가 05번과 같은 고객 모집단 정의를 pandas로 구현한다. 생성되는 고객 단위 CSV는 커밋하지 않고 `scripts/run_coupon_matching.py`의 로컬 입력으로만 사용한다.

## 해석 가드레일

- 활동 단계는 가입→결제 행동 funnel이 아니다. 원본 `Customer`에 비구매 고객이 없다.
- `Frequency = COUNT(DISTINCT 거래ID)`이며 구매일수와 다르다.
- 배송료는 상품 행마다 반복되므로 거래ID당 한 번만 합산한다.
- 현재 코호트 컬럼은 `first_purchase_month`로 명시한다. 관측 가능한 무구매 월은 0, 미래의 미관측 월은 행 없음으로 구분한다.
- 12개월 관측 데이터에서는 미래 LTV를 추정하지 않고 누적매출·활성월·구매일수·IPT를 분리해 보고한다.
- 쿠폰 `Used`는 무작위 배정이 아니라 사용 행동이므로 05번 결과만으로 인과효과를 보고하지 않는다.
