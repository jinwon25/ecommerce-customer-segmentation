# 시각화 인덱스

## README 대표 차트

| 파일 | 보여주는 관계 | 읽을 때 주의할 점 |
|---|---|---|
| `segment_revenue_concentration.png` | 세그먼트별 관측 매출 비중 | Monetary가 RFM 변수라 독립적 성과 검증이 아님 |
| `cohort_retention_heatmap.png` | 첫 구매월 × 월차 구매 리텐션 | 가입 코호트가 아니라 첫 구매 코호트 |
| `purchase_activity_ladder.png` | 전체 기간 거래ID 개수에 따른 고객 활동 단계 | 획득 funnel·시간순 행동 funnel이 아님 |
| `matched_outcome_differences.png` | 쿠폰 사용 고객의 60일 재구매율·상품매출 차이와 95% CI | 잔여 공변량 불균형으로 인과효과 해석 금지 |

네 개의 대표 차트는 `python scripts/build_portfolio_charts.py`로 재생성한다. 입력값은 `data/derived/`의 비식별 집계 스냅샷이다.

## 진단·보조 차트

- `psm_love_plot.png` — 매칭 전후 공변량 SMD
