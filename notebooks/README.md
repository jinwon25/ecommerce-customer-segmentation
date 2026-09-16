# 분석 노트북

`analysis_workbook.ipynb`는 현재 공개 집계에서 README의 핵심 수치와 관계를 다시 계산하는 실행 가능한 워크북이다. `make notebook`으로 전체 셀을 다시 실행한다.

원본 고객 단위 데이터는 저장소에 포함하지 않는다. 원본 대조와 쿠폰 모집단 생성·매칭은 각각 다음 스크립트가 담당한다.

- `scripts/validate_source_data.py`
- `scripts/build_coupon_population.py`
- `scripts/run_coupon_matching.py`

과거 단계별 실험 노트북은 현재 정의와 충돌해 공개본에서 제외했다. 초기 팀 분석의 흐름과 발표 맥락은 `reports/team_project_presentation.pdf`에 보존한다.
