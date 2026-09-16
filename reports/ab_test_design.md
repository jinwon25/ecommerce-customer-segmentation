# A/B 테스트 설계 초안 — 첫 구매 후 쿠폰 발송

쿠폰 `Used`와 `Clicked only` 고객의 관찰 차이를 무작위 실험으로 검증하기 위한 사전 설계다. 기존 PSM 수치는 표본 크기 입력값으로 사용하지 않는다. 운영 적용 전 eligibility 조건으로 대조군 baseline을 먼저 측정하고 표본 크기를 확정한다.

## 1. 의사결정 질문

첫 구매 후 14일 동안 추가 구매가 없는 고객에게 할인 쿠폰을 보내면, 미발송 대비 이후 60일 재구매율과 공헌이익이 개선되는가? 10%와 30% 중 어느 수준이 더 높은 순증분 가치를 만드는가?

## 2. 실험 단위와 모집단

- **실험 단위**: 고객ID
- **진입 시점(time zero)**: 첫 구매일 + 14일
- **포함**: 진입 시점까지 두 번째 구매가 없는 신규 구매 고객
- **제외**: 직원·테스트 계정, 환불·부정거래 계정, 쿠폰 수신 거부, 실험 기간 내 다른 할인 실험 참여자
- **재진입**: 최초 배정만 인정. 동일 고객은 다시 무작위화하지 않음
- **분석 원칙**: 발송·사용 여부와 무관하게 최초 배정군으로 분석하는 ITT

Time zero 이후 60일을 모든 군에 동일하게 관측한다. 기존 관찰연구의 첫 `Used`/`Clicked` 거래일과는 다른 정의이므로 두 결과를 직접 비교하지 않는다.

## 3. 무작위 배정

| arm | 정책 | 배정 비율 |
|---|---|---:|
| control | 쿠폰 미발송 | 1/3 |
| coupon_10 | 10% 할인 쿠폰 발송 | 1/3 |
| coupon_30 | 30% 할인 쿠폰 발송 | 1/3 |

고객ID의 deterministic hash로 배정하고, 플랫폼·첫 구매월·첫 구매 금액 구간을 층화 변수로 사용한다. 배정 로직 버전과 층화 값을 exposure log에 함께 저장한다.

## 4. 가설과 지표

### 1차 지표

**60일 재구매율**: time zero 다음 날부터 60일 이내 주문을 1건 이상 완료한 고객 비율.

가족 단위 1차 비교는 두 개다.

1. `coupon_10 - control`
2. `coupon_30 - control`

두 비교의 family-wise error rate를 0.05로 유지한다. 구현이 단순해야 하면 Bonferroni로 각 비교 `α=0.025`를 쓰고, 분석 환경이 지원하면 공통 대조군을 고려하는 Dunnett 검정을 사용한다.

### 2차 지표

- 고객당 60일 순매출
- 고객당 60일 공헌이익
- 쿠폰 사용률
- `coupon_10 - coupon_30`의 재구매율·공헌이익 차이

### Guardrail

- 주문 취소·환불률
- CS 문의율
- 메시지 수신 거부율
- 쿠폰 오발급·중복 사용률

## 5. 표본 크기

현재 데이터는 운영 eligibility 모집단의 baseline을 제공하지 않는다. 아래 표는 계획 범위를 보여주는 민감도 분석이며 최종 표본 수가 아니다. Power 80%, 양측 검정, 비교별 `α=0.025`, 동일 크기 3개 arm을 가정했다.

| 대조군 baseline | 탐지할 절대 차이 | arm당 표본 | 총 표본(3-arm) |
|---:|---:|---:|---:|
| 5% | +3%p | 1,268 | 3,804 |
| 5% | +5%p | 514 | 1,542 |
| 5% | +10%p | 161 | 483 |
| 10% | +3%p | 2,142 | 6,426 |
| 10% | +5%p | 824 | 2,472 |
| 10% | +10%p | 237 | 711 |

```python
from math import ceil
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize

p_control = 0.05
mde = 0.05
effect = proportion_effectsize(p_control + mde, p_control)

n_per_arm = ceil(
    NormalIndPower().solve_power(
        effect_size=effect,
        power=0.80,
        alpha=0.025,
        ratio=1,
        alternative="two-sided",
    )
)
print(n_per_arm, n_per_arm * 3)
```

최종 표본 크기는 실험 직전 4~8주 운영 데이터에서 eligibility 고객의 baseline과 일일 유입량을 측정한 뒤 결정한다. 예상 모집 기간은 `총 표본 / 일일 eligible 고객 수`로 계산하고, 이후 모든 고객의 60일 outcome window가 닫힐 때까지 기다린다.

## 6. 분석 계획

### Primary ITT

- 각 arm의 재구매율, 절대 차이(%p), risk ratio, 95% CI 보고
- 1차 비교는 사전에 정한 다중 비교 보정 적용
- 층화 변수로 조정한 logistic regression을 보조 분석으로 보고
- 누락 outcome은 원인별로 집계하고, 주문 시스템 장애가 아니라면 ITT 분모에서 임의 제외하지 않음

### 매출·공헌이익

- 평균 차이와 customer-level bootstrap 95% CI 보고
- 0이 많고 우측 꼬리가 길어도 비즈니스 의사결정 대상이 평균이므로 평균 차이를 주 지표로 유지
- Mann–Whitney 검정은 분포 차이 보조 진단으로만 사용

### 이질적 효과

플랫폼·첫 구매 금액·첫 구매 카테고리는 사전 정의된 탐색 subgroup이다. subgroup 결과에는 interaction CI를 함께 보고하며, 표본 크기가 부족하면 정책 결론을 내리지 않는다.

## 7. 중단과 의사결정

- 기본은 **고정 표본·고정 기간** 설계다. 결과를 반복 확인해 유의하면 멈추는 방식은 사용하지 않는다.
- 결제·쿠폰 시스템 장애, 오발송, guardrail의 중대한 악화는 통계적 유의성과 무관하게 운영 중단 사유다.
- 효능 조기 중단이 꼭 필요하면 실험 시작 전에 group-sequential boundary와 분석 시점을 별도로 확정한다.

출시 판단은 재구매율 하나가 아니라 공헌이익과 guardrail을 함께 본다.

| 결과 | 판단 |
|---|---|
| 재구매율↑, 공헌이익↑, guardrail 정상 | 해당 arm 출시 후보 |
| 재구매율↑, 공헌이익↓ | 할인 비용·대상·만료기간 재설계 |
| 재구매율 차이 없음 | 전면 발송 중단 또는 더 정밀한 타깃 실험 |
| guardrail 악화 | 효과와 무관하게 중단·원인 조사 |

## 8. 필수 로깅

| 영역 | 필드 예시 |
|---|---|
| assignment | customer_id, experiment_id, variant, assigned_at, hash_version, strata |
| delivery | coupon_id, sent_at, delivered_at, failure_reason |
| redemption | redeemed_at, order_id, discount_amount |
| outcome | order_at, net_revenue, contribution_margin, refund_at |
| guardrail | cs_ticket_at, opt_out_at, fraud_flag |

배정 테이블은 append-only로 유지하고, 분석 쿼리에서 assignment 이후 이벤트만 사용한다. 실험 시작 전 A/A 테스트 또는 sample-ratio-mismatch 점검으로 배정·로깅 이상을 확인한다.

## 9. 아직 필요한 운영 입력

- eligibility 고객의 실제 60일 baseline
- 일일 eligible 고객 수와 시즌 변동
- 할인 비용을 반영한 공헌이익 정의
- 다른 캠페인과의 중복 노출 정책
- 쿠폰 전달 실패·미사용을 포함한 ITT 데이터 연결률

이 값이 채워져야 설계가 운영 승인 가능한 최종안이 된다.
