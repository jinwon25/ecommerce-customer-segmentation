"""Build Tableau-ready, aggregate-only CSV files from public snapshots."""

from __future__ import annotations

from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "derived"
OUTPUT = ROOT / "tableau" / "data"


def build_tableau_data() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    direct_files = [
        "segment_revenue_share.csv",
        "activity_ladder_summary.csv",
        "matched_effects.csv",
        "matched_balance.csv",
    ]
    for name in direct_files:
        pd.read_csv(SOURCE / name).to_csv(OUTPUT / name, index=False)

    cohort = pd.read_csv(SOURCE / "cohort_retention_snapshot.csv")
    month_columns = [column for column in cohort if column.startswith("m")]
    cohort_long = cohort.melt(
        id_vars=["first_purchase_month", "cohort_size"],
        value_vars=month_columns,
        var_name="month_label",
        value_name="retention_pct",
    )
    cohort_long["month_index"] = cohort_long["month_label"].str[1:].astype(int)
    cohort_long = cohort_long.dropna(subset=["retention_pct"]).drop(
        columns="month_label"
    )
    cohort_long["is_baseline"] = cohort_long["month_index"].eq(0)
    cohort_long.sort_values(
        ["first_purchase_month", "month_index"]
    ).to_csv(OUTPUT / "cohort_retention_long.csv", index=False)

    print(f"Built 5 aggregate Tableau sources in {OUTPUT}")


if __name__ == "__main__":
    build_tableau_data()
