"""Run the coupon-use observational matching diagnostic.

Input is a CSV export of sql/05_coupon_observational_population.sql. The
result is a matched-sample difference, not an ATT or a causal estimate.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.api as sm


def standardized_mean_difference(treated: pd.Series, control: pd.Series) -> float:
    pooled_variance = (treated.var() + control.var()) / 2
    if pooled_variance == 0 or np.isnan(pooled_variance):
        return 0.0
    return float((treated.mean() - control.mean()) / np.sqrt(pooled_variance))


def bootstrap_difference(
    treated: np.ndarray,
    control: np.ndarray,
    *,
    paired: bool,
    repetitions: int = 1_000,
    seed: int = 42,
) -> tuple[float, float, float]:
    rng = np.random.default_rng(seed)
    if paired:
        differences = treated - control
        point = float(differences.mean())
        samples = [rng.choice(differences, len(differences), replace=True).mean() for _ in range(repetitions)]
    else:
        point = float(treated.mean() - control.mean())
        samples = [
            rng.choice(treated, len(treated), replace=True).mean()
            - rng.choice(control, len(control), replace=True).mean()
            for _ in range(repetitions)
        ]
    lower, upper = np.percentile(samples, [2.5, 97.5])
    return point, float(lower), float(upper)


def build_features(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    numeric = frame[[
        "tenure_months", "pre_frequency", "pre_line_value", "pre_category_diversity",
        "pre_purchase_days_2plus", "new_customer",
    ]].astype(float)
    categorical = pd.get_dummies(
        frame[["gender", "region", "first_purchase_month"]].astype(str),
        drop_first=True,
        dtype=float,
    )
    features = pd.concat([numeric, categorical], axis=1)
    treatment = frame["coupon_used"].astype(int)

    features = features.loc[:, features.std() > 0]
    separated = [
        column for column in features
        if features.loc[treatment.eq(1), column].std() == 0
        or features.loc[treatment.eq(0), column].std() == 0
    ]
    features = features.drop(columns=separated)

    if "new_customer" in features:
        absorbed = []
        for column in ["pre_frequency", "pre_line_value", "pre_category_diversity"]:
            if column in features:
                agreement = ((features["new_customer"].eq(1)) == features[column].eq(0)).mean()
                if agreement > 0.99:
                    absorbed.append(column)
        features = features.drop(columns=absorbed)
    return features, treatment


def match_controls_to_treated(frame: pd.DataFrame) -> tuple[pd.DataFrame, float]:
    treated = frame[frame["coupon_used"].eq(1)].sort_values("customer_id")
    control = frame[frame["coupon_used"].eq(0)].sort_values("customer_id")
    lower = max(treated["propensity_score"].min(), control["propensity_score"].min())
    upper = min(treated["propensity_score"].max(), control["propensity_score"].max())
    support = frame[frame["propensity_score"].between(lower, upper)].copy()
    clipped = support["propensity_score"].clip(1e-8, 1 - 1e-8)
    support["logit_score"] = np.log(clipped / (1 - clipped))
    caliper = 0.2 * support["logit_score"].std()

    treated = support[support["coupon_used"].eq(1)].sort_values("customer_id")
    control = support[support["coupon_used"].eq(0)].sort_values("customer_id")
    used: set[int] = set()
    pairs: list[dict[str, float | int]] = []
    for control_index, control_row in control.iterrows():
        candidates = treated.loc[
            ~treated.index.isin(used), ["customer_id", "logit_score"]
        ].copy()
        candidates["distance"] = (
            candidates["logit_score"] - control_row["logit_score"]
        ).abs()
        candidates = candidates[candidates["distance"].le(caliper)].sort_values(
            ["distance", "customer_id"], kind="mergesort"
        )
        if candidates.empty:
            continue
        treated_index = int(candidates.index[0])
        pairs.append({
            "control_index": int(control_index),
            "treated_index": treated_index,
            "distance": float(candidates.iloc[0]["distance"]),
        })
        used.add(treated_index)
    return pd.DataFrame(pairs), float(caliper)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True, help="CSV exported from SQL step 05")
    parser.add_argument("--effects-output", type=Path, required=True)
    parser.add_argument("--balance-output", type=Path, required=True)
    args = parser.parse_args()

    frame = pd.read_csv(args.input)
    required = {
        "customer_id", "coupon_used", "gender", "region", "tenure_months",
        "first_purchase_month", "pre_frequency", "pre_line_value", "pre_category_diversity",
        "pre_purchase_days_2plus", "new_customer", "repurchase_60d", "product_revenue_60d",
    }
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"Missing input columns: {sorted(missing)}")

    features, treatment = build_features(frame)
    model_matrix = sm.add_constant(features)
    propensity_model = sm.Logit(treatment, model_matrix).fit(disp=False, maxiter=100)
    frame["propensity_score"] = propensity_model.predict(model_matrix)
    pairs, caliper = match_controls_to_treated(frame)
    if pairs.empty:
        raise RuntimeError("No matched pairs within the caliper")

    treated_index = pairs["treated_index"].astype(int)
    control_index = pairs["control_index"].astype(int)
    balance_rows = []
    for column in features:
        balance_rows.append({
            "covariate": column,
            "smd_before": standardized_mean_difference(
                features.loc[treatment.eq(1), column], features.loc[treatment.eq(0), column]
            ),
            "smd_after": standardized_mean_difference(
                features.loc[treated_index, column], features.loc[control_index, column]
            ),
        })
    balance = pd.DataFrame(balance_rows)
    balance["abs_smd_after"] = balance["smd_after"].abs()

    effect_rows = []
    specifications = [
        ("60일 재구매율", "repurchase_60d", "percentage point", 100),
        ("60일 상품매출", "product_revenue_60d", "USD", 1),
    ]
    for outcome_name, column, unit, multiplier in specifications:
        all_treated = frame.loc[treatment.eq(1), column].to_numpy()
        all_control = frame.loc[treatment.eq(0), column].to_numpy()
        matched_treated = frame.loc[treated_index, column].to_numpy()
        matched_control = frame.loc[control_index, column].to_numpy()
        for method, values, paired in [
            ("단순 차이", (all_treated, all_control), False),
            (f"{len(pairs)}쌍 매칭 차이", (matched_treated, matched_control), True),
        ]:
            estimate, lower, upper = bootstrap_difference(*values, paired=paired)
            effect_rows.append({
                "outcome": outcome_name,
                "method": method,
                "n_treat": len(values[0]),
                "n_control": len(values[1]),
                "estimate": round(estimate * multiplier, 2),
                "ci_lower": round(lower * multiplier, 2),
                "ci_upper": round(upper * multiplier, 2),
                "unit": unit,
            })

    args.effects_output.parent.mkdir(parents=True, exist_ok=True)
    args.balance_output.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(effect_rows).to_csv(args.effects_output, index=False)
    balance.to_csv(args.balance_output, index=False)
    print(f"pairs: {len(pairs)}; caliper: {caliper:.4f}")
    print(f"covariates with |SMD| >= 0.1 after matching: {(balance['abs_smd_after'] >= 0.1).sum()}/{len(balance)}")
    print("Interpretation: matched-sample observational difference, not an ATT or causal effect")


if __name__ == "__main__":
    main()
