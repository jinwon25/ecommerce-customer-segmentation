# data/

데이콘 이커머스 고객 세분화 분석 아이디어 경진대회(2024) 원본 데이터.

## 파일
- `Onlinesales_info.csv` — 거래 단위 로그
- `Customer_info.csv` — 고객 속성
- `Discount_info.csv` — 카테고리·월별 쿠폰 정보
- `Marketing_info.csv` — 일자별 광고 비용
- `Tax_info.csv` — 카테고리별 세율

원본 파일은 `.gitignore`로 제외되어 리포에 commit되지 않는다.

## `derived/` — 공개 가능한 집계 스냅샷

README의 의사결정용 차트를 원본 데이터나 개인 BigQuery 프로젝트 없이 다시 만들 수 있도록 집계 결과만 저장한다.

- `segment_revenue_share.csv` — 세그먼트별 고객 수·관측 매출·매출 비중
- `cohort_retention_snapshot.csv` — 첫 구매월 × 월차 구매 리텐션
- `activity_ladder_summary.csv` — 거래ID 개수 기반 고객 활동 단계
- `matched_effects.csv` — 쿠폰 사용 고객의 재구매율·상품매출 단순/매칭 차이와 bootstrap CI
- `matched_balance.csv` — 매칭 전후 공변량 standardized mean difference

모든 파일은 고객 단위 행이나 식별자를 포함하지 않는다. 원본 데이터의 독립 pandas 구현과 대조한 공개용 집계이며 테스트에서 합계·비율·관측기간 구조를 검사한다.

## 다운로드
[데이콘 — 이커머스 고객 세분화 분석 아이디어 경진대회](https://dacon.io/competitions/official/236222/data)
회원가입 후 원본 파일을 받아 본 디렉토리에 위치.
