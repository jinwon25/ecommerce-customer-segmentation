"""Recompute public aggregate snapshots from the source files.

The Dacon source files are not committed. This script accepts either Korean
competition column names or the equivalent public English schema and checks
that source-derived aggregates match data/derived.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
DERIVED = ROOT / "data" / "derived"

COLUMN_ALIASES = {
    "고객ID": "customer_id", "CustomerID": "customer_id",
    "거래ID": "transaction_id", "Transaction_ID": "transaction_id",
    "거래날짜": "transaction_date", "Transaction_Date": "transaction_date",
    "제품카테고리": "product_category", "Product_Category": "product_category",
    "수량": "quantity", "Quantity": "quantity",
    "평균금액": "unit_price", "Avg_Price": "unit_price",
    "배송료": "delivery_charge", "Delivery_Charges": "delivery_charge",
    "쿠폰상태": "coupon_status", "Coupon_Status": "coupon_status",
    "월": "month", "Month": "month",
    "할인율": "discount_pct", "Discount_pct": "discount_pct",
}


def read_table(path: Path) -> pd.DataFrame:
    frame = pd.read_excel(path) if path.suffix.lower() in {".xlsx", ".xls"} else pd.read_csv(path)
    return frame.rename(columns=COLUMN_ALIASES)


def require_columns(frame: pd.DataFrame, columns: set[str], name: str) -> None:
    missing = columns - set(frame.columns)
    if missing:
        raise ValueError(f"{name} missing columns: {sorted(missing)}")


def percent_rank_score(values: pd.Series, ascending: bool) -> pd.Series:
    rank = values.rank(method="min", ascending=ascending)
    percent_rank = (rank - 1) / (len(values) - 1)
    return np.minimum(4, 1 + np.floor(percent_rank * 4)).astype(int)


def classify_segment(row: pd.Series) -> str:
    recency, frequency, monetary = row[["r_score", "f_score", "m_score"]]
    if recency >= 4 and frequency >= 4 and monetary >= 4:
        return "핵심 파트너 고객"
    if (
        (2 <= recency <= 4 and 3 <= frequency <= 4 and monetary >= 4)
        or (3 <= recency <= 4 and 3 <= frequency <= 4 and 3 <= monetary <= 4)
    ):
        return "성장형 고객"
    if (
        (recency >= 3 and 1 <= frequency <= 3 and 1 <= monetary <= 3)
        or (recency >= 4 and frequency < 2 and monetary < 2)
        or (3 <= recency <= 4 and frequency < 2 and monetary < 2)
    ):
        return "유망 고객"
    if (
        (2 <= recency <= 3 and frequency < 3 and monetary < 3)
        or (2 <= recency <= 3 and 2 <= frequency <= 3 and 2 <= monetary <= 3)
    ):
        return "이탈 위험 고객"
    if (
        (recency < 3 and 2 <= frequency <= 4 and 2 <= monetary <= 4)
        or (recency < 2 and frequency >= 4 and monetary >= 4)
        or (recency < 2 and frequency < 2 and monetary < 2)
    ):
        return "장기 비활성 고객"
    return "기타"


def build_customer_master(
    sales: pd.DataFrame, discounts: pd.DataFrame, tax: pd.DataFrame
) -> tuple[pd.DataFrame, dict[str, float]]:
    sales = sales.copy()
    sales["transaction_date"] = pd.to_datetime(sales["transaction_date"])
    sales["month"] = sales["transaction_date"].dt.strftime("%b")
    joined = sales.merge(
        discounts[["month", "product_category", "discount_pct"]],
        on=["month", "product_category"], how="left", validate="many_to_one",
    ).merge(
        tax[["product_category", "GST"]],
        on="product_category", how="left", validate="many_to_one",
    )
    if joined["GST"].isna().any():
        raise ValueError("Tax join produced missing GST values")

    effective_discount = np.where(
        joined["coupon_status"].eq("Used"), joined["discount_pct"].fillna(0), 0
    )
    joined["product_amount"] = (
        joined["quantity"] * joined["unit_price"]
        * (1 - effective_discount / 100) * (1 + joined["GST"])
    )
    delivery_counts = joined.groupby("transaction_id")["delivery_charge"].nunique()
    if not delivery_counts.eq(1).all():
        raise ValueError("Delivery charge is inconsistent within a transaction")

    transactions = joined.groupby(
        ["customer_id", "transaction_id", "transaction_date"], as_index=False
    ).agg(product_amount=("product_amount", "sum"), delivery=("delivery_charge", "max"))
    transactions["transaction_amount"] = transactions["product_amount"] + transactions["delivery"]
    customer = transactions.groupby("customer_id", as_index=False).agg(
        last_purchase=("transaction_date", "max"),
        frequency=("transaction_id", "nunique"),
        monetary=("transaction_amount", "sum"),
    )
    customer["recency"] = (
        transactions["transaction_date"].max() - customer["last_purchase"]
    ).dt.days
    customer["r_score"] = percent_rank_score(customer["recency"], ascending=False)
    customer["f_score"] = percent_rank_score(customer["frequency"], ascending=True)
    customer["m_score"] = percent_rank_score(customer["monetary"], ascending=True)
    customer["segment"] = customer.apply(classify_segment, axis=1)

    diagnostics = {
        "sales_rows": len(sales),
        "customers": customer["customer_id"].nunique(),
        "transactions": transactions["transaction_id"].nunique(),
        "unmatched_discount_rows": int(joined["discount_pct"].isna().sum()),
        "repeated_shipping_overcount_avoided": float(
            joined["delivery_charge"].sum() - transactions["delivery"].sum()
        ),
        "observed_revenue": float(customer["monetary"].sum()),
    }
    return customer, diagnostics


def validate_segment_snapshot(customer: pd.DataFrame) -> None:
    actual = customer.groupby("segment", as_index=False).agg(
        customers=("customer_id", "size"), revenue=("monetary", "sum")
    ).sort_values("revenue", ascending=False).reset_index(drop=True)
    actual["revenue"] = actual["revenue"].round().astype(int)
    actual["revenue_share_pct"] = (actual["revenue"] / actual["revenue"].sum() * 100).round(1)
    expected = pd.read_csv(DERIVED / "segment_revenue_share.csv")
    pd.testing.assert_frame_equal(actual, expected, check_dtype=False, atol=1)


def validate_activity_snapshot(customer: pd.DataFrame) -> None:
    counts = [
        len(customer),
        int(customer["frequency"].ge(2).sum()),
        int(customer["frequency"].ge(5).sum()),
        int(customer["segment"].isin(["핵심 파트너 고객", "성장형 고객"]).sum()),
    ]
    expected = pd.read_csv(DERIVED / "activity_ladder_summary.csv")
    if counts != expected["reached"].tolist():
        raise AssertionError(
            f"Activity counts differ: actual={counts}, expected={expected['reached'].tolist()}"
        )


def validate_cohort_snapshot(sales: pd.DataFrame) -> None:
    frame = sales.copy()
    frame["transaction_date"] = pd.to_datetime(frame["transaction_date"])
    frame["activity_month"] = frame["transaction_date"].dt.to_period("M")
    first = frame.groupby("customer_id")["activity_month"].min().rename("first_purchase_month")
    frame = frame.join(first, on="customer_id")
    frame["month_index"] = (
        (frame["activity_month"].dt.year - frame["first_purchase_month"].dt.year) * 12
        + frame["activity_month"].dt.month - frame["first_purchase_month"].dt.month
    )
    sizes = first.value_counts().sort_index()
    active = frame.groupby(["first_purchase_month", "month_index"])["customer_id"].nunique()
    rows: list[dict[str, object]] = []
    for cohort_index, cohort_month in enumerate(sizes.index):
        row: dict[str, object] = {
            "first_purchase_month": str(cohort_month),
            "cohort_size": int(sizes.loc[cohort_month]),
        }
        for month_index in range(12):
            if month_index <= 11 - cohort_index:
                count = active.get((cohort_month, month_index), 0)
                row[f"m{month_index}"] = round(count / sizes.loc[cohort_month] * 100, 1)
            else:
                row[f"m{month_index}"] = np.nan
        rows.append(row)
    actual = pd.DataFrame(rows)
    expected = pd.read_csv(DERIVED / "cohort_retention_snapshot.csv")
    pd.testing.assert_frame_equal(actual, expected, check_dtype=False, atol=0.05)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sales", type=Path, required=True)
    parser.add_argument("--discount", type=Path, required=True)
    parser.add_argument("--tax", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    sales, discounts, tax = read_table(args.sales), read_table(args.discount), read_table(args.tax)
    require_columns(sales, {
        "customer_id", "transaction_id", "transaction_date", "product_category",
        "quantity", "unit_price", "delivery_charge", "coupon_status",
    }, "sales")
    require_columns(discounts, {"month", "product_category", "discount_pct"}, "discount")
    require_columns(tax, {"product_category", "GST"}, "tax")
    customer, diagnostics = build_customer_master(sales, discounts, tax)
    validate_segment_snapshot(customer)
    validate_activity_snapshot(customer)
    validate_cohort_snapshot(sales)
    for name, value in diagnostics.items():
        print(f"{name}: {value:,.2f}" if isinstance(value, float) else f"{name}: {value:,}")
    print("PASS: source data reproduces the public segment, activity, and cohort snapshots")


if __name__ == "__main__":
    main()
