# 재현성 점검 결과

## 재현 가능한 범위

| 범위 | 확인 방법 | 상태 |
|---|---|---|
| 공개 집계 파일 | 고객 수·매출 비중·코호트 관측 삼각형·CI 범위 unit test | 통과 |
| README 대표 차트 5개 | `make charts`로 비식별 집계에서 재생성 | 통과 |
| Markdown 링크·Python 문법 | repository integrity test | 통과 |
| 원본→세그먼트·활동 단계·코호트 | `scripts/validate_source_data.py`로 동일 공개 데이터셋 사본과 대조 | 통과 |
| GitHub Actions | push/PR에서 테스트·Tableau 집계·차트 빌드 | workflow 구성 완료 |
| BigQuery SQL | pandas 독립 구현과 산식·집계 대조 | 의미 검증 통과, BigQuery 재실행 전 |
| 쿠폰 72쌍 매칭 | 원본→고객 모집단→결정적 최근접 매칭→CI·SMD | 로컬 전체 경로 재실행 통과 |
| Tableau | 비식별 집계 5개 자동 생성·구조 테스트 | 연결 데이터 통과, 워크북·Public URL 미구현 |

## 검증에서 발견해 수정한 문제

- 배송료가 거래ID의 상품 행마다 반복되어 기존 합계가 약 `$317,647` 과대계상됐다. 상품금액을 먼저 합산하고 거래ID당 배송료를 한 번만 더하도록 수정했다.
- RFM `NTILE`이 동일한 Frequency·Recency 고객을 임의의 서로 다른 점수에 배정할 수 있었다. `PERCENT_RANK`로 바꿔 동률 고객은 같은 점수를 받게 했다.
- 가입→첫 구매 funnel로 보이던 결과를 전체 관측기간의 거래 활동 단계로 고쳤다.
- 코호트에서 관측 가능한 무구매 월의 0과 아직 도래하지 않은 월을 구분했다.
- 매칭 결과는 전체 사용 고객 ATT가 아니라 72개 매칭 쌍의 관찰 차이로 한정했다.
- 최근접 거리가 같은 후보의 선택 순서가 구현체에 따라 달라지지 않도록 고객ID를 2차 정렬 기준으로 고정했다.

## 실행 명령

```bash
pip install -r requirements-portfolio.txt
make check
```

데이콘 원본 파일이 있을 때:

```bash
pip install -r requirements.txt
python scripts/validate_source_data.py \
  --sales data/Onlinesales_info.csv \
  --discount data/Discount_info.csv \
  --tax data/Tax_info.csv

python scripts/build_coupon_population.py \
  --sales data/Onlinesales_info.csv \
  --customers data/Customer_info.xlsx \
  --output data/coupon_population_private.csv

python scripts/run_coupon_matching.py \
  --input data/coupon_population_private.csv \
  --effects-output data/derived/matched_effects.csv \
  --balance-output data/derived/matched_balance.csv
```

BigQuery 쿼리는 **BigQuery Standard SQL 기준**이다. 프로젝트 ID `ecomm-extension`을 실행 환경에 맞게 바꾼 뒤 `sql/README.md` 순서로 실행한다.
