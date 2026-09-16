.PHONY: charts tableau-data notebook test check

MPLCONFIGDIR ?= /tmp/ecommerce-customer-segmentation-mpl
LOKY_MAX_CPU_COUNT ?= 1

charts:
	mkdir -p $(MPLCONFIGDIR)
	MPLBACKEND=Agg MPLCONFIGDIR=$(MPLCONFIGDIR) XDG_CACHE_HOME=$(MPLCONFIGDIR) python scripts/build_portfolio_charts.py

tableau-data:
	python scripts/build_tableau_data.py

notebook:
	jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=120 notebooks/analysis_workbook.ipynb

test:
	LOKY_MAX_CPU_COUNT=$(LOKY_MAX_CPU_COUNT) python -m unittest discover -s tests -p 'test_*.py' -v

check: tableau-data notebook test charts
