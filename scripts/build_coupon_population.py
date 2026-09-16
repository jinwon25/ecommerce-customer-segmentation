"""Build the customer-level coupon observational population from source data.

This is the local pandas equivalent of sql/05_coupon_observational_population.sql.
The customer-level output contains identifiers, so keep it local and do not commit it.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


COLUMN_ALIASES = {
    "고객ID": "customer_id",
    "CustomerID": "customer_id",
    "거래ID": "transaction_id",
    "Transaction_ID": "transaction_id",
    "거래날짜": "transaction_date",
    "Transaction_Date": "transaction_date",
    "제품카테고리": "product_category",
    "Product_Category": "product_category",
    "수량": "quantity",
    "Quantity": "quantity",
    "평균금액": "unit_price",
    "Avg_Price": "unit_price",
    "쿠폰상태": "coupon_status",
    "Coupon_Status": "coupon_status",
    "성별": "gender",
    "Gender": "gender",
    "고객지역": "region",
    "Location": "region",
    "가입기간": "tenure_months",
    "Tenure_Months": "tenure_months",
}


def read_table(path: Path) -> pd.DataFrame:
    frame = (
        pd.read_excel(path)
        if path.suffix.lower() in {".xlsx", ".xls"}
        else pd.read_csv(path)
    )
    return frame.rename(columns=COLUMN_ALIASES)


def require_columns(frame: pd.DataFrame, columns: set[str], name: str) -> None:
    missing = columns - set(frame.columns)
    if missing:
        raise ValueError(f"{name} missing columns: {sorted(missing)}")


def build_coupon_population(
    sales: pd.DataFrame, customers: pd.DataFrame
) -> pd.DataFrame:
    require_columns(
        sales,
        {
            "customer_id",
            "transaction_id",
            "transaction_date",
            "product_category",
            "quantity",
            "unit_price",
            "coupon_status",
        },
        "sales",
    )
    require_columns(
        customers,
        {"customer_id", "gender", "region", "tenure_months"},
        "customers",
    )
    if customers["customer_id"].duplicated().any():
        raise ValueError("customers contains duplicate customer_id values")

    sales = sales.copy()
    sales["transaction_date"] = pd.to_datetime(
        sales["transaction_date"], errors="raise"
    )
    sales["line_value"] = sales["quantity"] * sales["unit_price"]
    latest_index_date = sales["transaction_date"].max() - pd.Timedelta(days=61)

    first_used = (
        sales[sales["coupon_status"].eq("Used")]
        .groupby("customer_id", as_index=False)["transaction_date"]
        .min()
        .rename(columns={"transaction_date": "index_date"})
    )
    first_used["coupon_used"] = 1

    clicked_only = (
        sales[
            sales["coupon_status"].eq("Clicked")
            & ~sales["customer_id"].isin(first_used["customer_id"])
        ]
        .groupby("customer_id", as_index=False)["transaction_date"]
        .min()
        .rename(columns={"transaction_date": "index_date"})
    )
    clicked_only["coupon_used"] = 0

    population = pd.concat([first_used, clicked_only], ignore_index=True)
    population = population[population["index_date"].le(latest_index_date)].copy()
    if population.empty or population["coupon_used"].nunique() != 2:
        raise ValueError("eligible population must contain both coupon groups")

    first_purchase = (
        sales.groupby("customer_id", as_index=False)["transaction_date"]
        .min()
        .assign(
            first_purchase_month=lambda frame: frame["transaction_date"].dt.month
        )[["customer_id", "first_purchase_month"]]
    )

    indexed_sales = sales.merge(
        population[["customer_id", "index_date"]],
        on="customer_id",
        how="inner",
        validate="many_to_one",
    )
    pre = (
        indexed_sales[indexed_sales["transaction_date"].lt(indexed_sales["index_date"])]
        .groupby("customer_id", as_index=False)
        .agg(
            pre_frequency=("transaction_id", "nunique"),
            pre_purchase_days=("transaction_date", "nunique"),
            pre_line_value=("line_value", "mean"),
            pre_category_diversity=("product_category", "nunique"),
        )
    )

    outcome_rows = indexed_sales[
        indexed_sales["transaction_date"].gt(indexed_sales["index_date"])
        & indexed_sales["transaction_date"].le(
            indexed_sales["index_date"] + pd.Timedelta(days=60)
        )
    ]
    outcomes = (
        outcome_rows.groupby("customer_id", as_index=False)
        .agg(
            outcome_transactions=("transaction_id", "nunique"),
            product_revenue_60d=("line_value", "sum"),
        )
        .assign(
            repurchase_60d=lambda frame: frame["outcome_transactions"].gt(0).astype(int)
        )
        .drop(columns="outcome_transactions")
    )

    result = (
        population.merge(
            customers[["customer_id", "gender", "region", "tenure_months"]],
            on="customer_id",
            how="left",
            validate="one_to_one",
        )
        .merge(first_purchase, on="customer_id", how="left", validate="one_to_one")
        .merge(pre, on="customer_id", how="left", validate="one_to_one")
        .merge(outcomes, on="customer_id", how="left", validate="one_to_one")
    )
    if result[["gender", "region", "tenure_months"]].isna().any().any():
        raise ValueError("eligible sales customers are missing customer attributes")

    metric_columns = [
        "pre_frequency",
        "pre_purchase_days",
        "pre_line_value",
        "pre_category_diversity",
        "repurchase_60d",
        "product_revenue_60d",
    ]
    result[metric_columns] = result[metric_columns].fillna(0)
    result["pre_purchase_days_2plus"] = result["pre_purchase_days"].ge(2).astype(int)
    result["new_customer"] = result["pre_frequency"].eq(0).astype(int)

    columns = [
        "customer_id",
        "index_date",
        "coupon_used",
        "gender",
        "region",
        "tenure_months",
        "first_purchase_month",
        "pre_frequency",
        "pre_purchase_days",
        "pre_line_value",
        "pre_category_diversity",
        "pre_purchase_days_2plus",
        "new_customer",
        "repurchase_60d",
        "product_revenue_60d",
    ]
    return result[columns].sort_values("customer_id").reset_index(drop=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sales", type=Path, required=True)
    parser.add_argument("--customers", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    population = build_coupon_population(
        read_table(args.sales), read_table(args.customers)
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    population.to_csv(args.output, index=False)
    counts = population["coupon_used"].value_counts().to_dict()
    print(f"rows: {len(population):,}; treated: {counts.get(1, 0):,}; control: {counts.get(0, 0):,}")
    print(f"saved private customer-level output: {args.output}")


if __name__ == "__main__":
    main()
