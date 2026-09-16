# Tableau 데이터 소스

이 폴더의 CSV는 고객 식별자를 포함하지 않는 공개 집계다. `make tableau-data`로 `data/derived/`에서 다시 생성한다.

| 파일 | 시트 |
|---|---|
| `segment_revenue_share.csv` | 세그먼트 매출 집중도 |
| `cohort_retention_long.csv` | 첫 구매월 코호트 히트맵 |
| `activity_ladder_summary.csv` | 거래 활동 단계 |
| `matched_effects.csv` | 쿠폰 관찰 차이 forest plot |
| `matched_balance.csv` | 매칭 전후 SMD |

파일별 집계 단위가 다르므로 Tableau에서 물리적 join이나 전역 필터를 적용하지 않고 독립 데이터 소스로 연결한다.
