"""Build the decision-oriented charts shown in the project README.

The input files contain aggregate results only. They are committed so that a
reviewer can rebuild the portfolio figures without access to the raw Dacon
files or the author's BigQuery project.
"""

from pathlib import Path

import matplotlib.font_manager as fm
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
import numpy as np
import pandas as pd

try:
    import koreanize_matplotlib  # noqa: F401
except ImportError:
    koreanize_matplotlib = None


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "derived"
OUTPUT = ROOT / "visualizations"

NAVY = "#17324D"
BLUE = "#4A90D9"
ORANGE = "#E07B5B"
GRAY = "#A7B0B8"
LIGHT_GRAY = "#E7EBEF"
TEXT = "#263238"


def configure_style() -> None:
    preferred_fonts = [
        "AppleGothic",
        "Arial Unicode MS",
        "NanumGothic",
        "Malgun Gothic",
        "Noto Sans CJK KR",
        "DejaVu Sans",
    ]
    installed = {font.name for font in fm.fontManager.ttflist}
    selected = next((font for font in preferred_fonts if font in installed), "DejaVu Sans")
    plt.rcParams.update(
        {
            "font.family": selected,
            "axes.unicode_minus": False,
            "axes.edgecolor": LIGHT_GRAY,
            "axes.labelcolor": TEXT,
            "xtick.color": TEXT,
            "ytick.color": TEXT,
            "text.color": TEXT,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
        }
    )


def save(fig: plt.Figure, name: str) -> None:
    OUTPUT.mkdir(exist_ok=True)
    fig.savefig(OUTPUT / name, dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def segment_revenue_chart() -> None:
    df = pd.read_csv(DATA / "segment_revenue_share.csv")
    df["cumulative_share_pct"] = df["revenue_share_pct"].cumsum()
    colors = [ORANGE if name in {"성장형 고객", "핵심 파트너 고객"} else GRAY for name in df["segment"]]

    fig, ax = plt.subplots(figsize=(11.5, 6.2))
    y = np.arange(len(df))
    bars = ax.barh(y, df["revenue_share_pct"], color=colors, height=0.62)
    ax.set_yticks(y, df["segment"])
    ax.invert_yaxis()
    ax.set_xlim(0, 45)
    ax.set_xlabel("2019년 관측 매출 비중 (%)")
    fig.suptitle(
        "매출은 상위 2개 RFM 세그먼트에 68.3% 집중",
        x=0.01,
        y=0.98,
        ha="left",
        fontsize=17,
        weight="bold",
    )
    fig.text(
        0.01,
        0.91,
        "누적 고객 매출의 기술통계 — 미래 LTV 예측이 아님",
        color="#5F6B73",
        fontsize=10.5,
    )
    for bar, share, revenue in zip(bars, df["revenue_share_pct"], df["revenue"]):
        ax.text(
            share + 0.7,
            bar.get_y() + bar.get_height() / 2,
            f"{share:.1f}%  (${revenue / 1_000_000:.2f}M)",
            va="center",
            fontsize=10,
        )
    ax.axvline(0, color=TEXT, linewidth=0.8)
    ax.grid(axis="x", color=LIGHT_GRAY, linewidth=0.8)
    ax.set_axisbelow(True)
    for spine in ["top", "right", "left"]:
        ax.spines[spine].set_visible(False)
    fig.text(
        0.01,
        0.01,
        "주의: Monetary가 RFM 분류 변수이므로 매출 집중은 세그먼트의 독립적 성과 검증이 아니라 분류 결과의 설명이다.",
        fontsize=9,
        color="#5F6B73",
    )
    fig.tight_layout(rect=(0, 0.05, 1, 0.88))
    save(fig, "segment_revenue_concentration.png")


def cohort_retention_chart() -> None:
    df = pd.read_csv(DATA / "cohort_retention_snapshot.csv")
    month_columns = [f"m{i}" for i in range(12)]
    matrix = df[month_columns].to_numpy(dtype=float)

    fig, (ax, ax_size) = plt.subplots(
        1,
        2,
        figsize=(13, 6.6),
        gridspec_kw={"width_ratios": [10, 1.35], "wspace": 0.26},
    )
    color_map = plt.colormaps["Blues"].copy()
    color_map.set_bad("#ECEFF1")
    color_values = matrix.copy()
    color_values[:, 0] = np.nan
    image = ax.imshow(np.ma.masked_invalid(color_values), cmap=color_map, vmin=0, vmax=30, aspect="auto")
    for row_index in range(matrix.shape[0]):
        ax.add_patch(
            Rectangle(
                (-0.5, row_index - 0.5),
                1,
                1,
                facecolor="#D0D5D9",
                edgecolor="white",
                linewidth=1.1,
            )
        )

    ax.set_xticks(np.arange(12), month_columns)
    ax.set_yticks(np.arange(len(df)), df["first_purchase_month"])
    ax.set_xlabel("첫 구매 후 월차")
    ax.set_ylabel("첫 구매월")
    ax.set_title("월차별 구매 리텐션 (%)", loc="left", fontsize=13, weight="bold")
    ax.set_xticks(np.arange(-0.5, 12, 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(df), 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=1.1)
    ax.tick_params(which="minor", bottom=False, left=False)

    for row_index in range(matrix.shape[0]):
        for column_index in range(matrix.shape[1]):
            value = matrix[row_index, column_index]
            if np.isnan(value):
                continue
            text_color = "white" if value >= 18 and column_index != 0 else TEXT
            ax.text(
                column_index,
                row_index,
                f"{value:.1f}",
                ha="center",
                va="center",
                fontsize=8,
                color=text_color,
            )

    ax.add_patch(Rectangle((4.5, -0.5), 3, 1, fill=False, edgecolor=ORANGE, linewidth=2.2))
    color_bar = fig.colorbar(image, ax=ax, fraction=0.028, pad=0.02)
    color_bar.ax.set_title("%", pad=8, fontsize=9)

    y = np.arange(len(df))
    ax_size.barh(y, df["cohort_size"], color=GRAY, height=0.72)
    ax_size.set_ylim(len(df) - 0.5, -0.5)
    ax_size.set_yticks([])
    ax_size.set_xlabel("코호트 크기")
    ax_size.set_title("고객 수", fontsize=11)
    ax_size.grid(False)
    for yi, value in zip(y, df["cohort_size"]):
        ax_size.text(value + 4, yi, f"{int(value)}", va="center", fontsize=8.5)
    ax_size.set_xlim(0, df["cohort_size"].max() * 1.35)
    for spine in ["top", "right", "left"]:
        ax_size.spines[spine].set_visible(False)

    fig.suptitle(
        "첫 구매 다음 달 리텐션은 코호트 단순평균 9.68%",
        x=0.01,
        y=0.99,
        ha="left",
        fontsize=17,
        weight="bold",
    )
    fig.text(
        0.01,
        0.925,
        "1월 코호트는 m5~m7에 다시 20%대로 나타나며, 구매 리텐션은 단조 감소하지 않는다.",
        color="#5F6B73",
        fontsize=10.5,
    )
    fig.text(
        0.01,
        0.015,
        "m0는 100% 기준월이라 중립색으로 표시했다. 이후 회색 셀은 아직 도래하지 않은 월이며, 첫 구매월은 회원 가입월이 아니다.",
        fontsize=9,
        color="#5F6B73",
    )
    fig.subplots_adjust(left=0.15, right=0.97, bottom=0.13, top=0.84, wspace=0.30)
    save(fig, "cohort_retention_heatmap.png")


def purchase_activity_ladder_chart() -> None:
    df = pd.read_csv(DATA / "activity_ladder_summary.csv")
    fig, ax = plt.subplots(figsize=(11.5, 6.2))
    y = np.arange(len(df))
    colors = [NAVY, BLUE, BLUE, GRAY]
    bars = ax.barh(y, df["reached"], color=colors, height=0.62)
    ax.set_yticks(y, [f"{stage}. {name}" for stage, name in zip(df["stage"], df["stage_name"])])
    ax.invert_yaxis()
    ax.set_xlim(0, 1660)
    ax.set_xlabel("고객 수")
    fig.suptitle(
        "거래 고객의 91.5%가 서로 다른 거래ID를 2개 이상 기록",
        x=0.01,
        y=0.98,
        ha="left",
        fontsize=17,
        weight="bold",
    )
    fig.text(
        0.01,
        0.91,
        "획득 퍼널이 아니라 2019년 거래 고객 1,468명의 전체 관측기간 분류",
        color="#5F6B73",
        fontsize=10.5,
    )
    for i, (bar, reached, conversion) in enumerate(
        zip(bars, df["reached"], df["previous_stage_conversion_pct"])
    ):
        label = f"{int(reached):,}명"
        if pd.notna(conversion):
            label += f"  ·  직전 단계의 {conversion:.1f}%"
        ax.text(reached + 22, bar.get_y() + bar.get_height() / 2, label, va="center", fontsize=10)

    ax.annotate(
        "8.5% 이탈",
        xy=(df.loc[1, "reached"], 1),
        xytext=(1510, 1.55),
        arrowprops={"arrowstyle": "->", "color": ORANGE, "lw": 1.5},
        color=ORANGE,
        fontsize=10.5,
        ha="center",
    )
    ax.grid(axis="x", color=LIGHT_GRAY, linewidth=0.8)
    ax.set_axisbelow(True)
    for spine in ["top", "right", "left"]:
        ax.spines[spine].set_visible(False)
    fig.text(
        0.01,
        0.01,
        "마지막 단계의 감소는 행동 이탈이 아니라 RFM 규칙으로 대상을 좁힌 결과다. 가입→첫 구매는 원천 데이터로 측정할 수 없다.",
        fontsize=9,
        color="#5F6B73",
    )
    fig.tight_layout(rect=(0, 0.05, 1, 0.88))
    save(fig, "purchase_activity_ladder.png")


def matched_effect_chart() -> None:
    df = pd.read_csv(DATA / "matched_effects.csv")
    fig, axes = plt.subplots(1, 2, figsize=(12, 5.8))
    panels = [
        ("60일 재구매율", "차이 (percentage point)", (-2, 50)),
        ("60일 상품매출", "차이 (USD)", (-100, 2200)),
    ]
    method_colors = {"단순 차이": GRAY, "72쌍 매칭 차이": ORANGE}

    for ax, (outcome, xlabel, xlim) in zip(axes, panels):
        part = df[df["outcome"] == outcome].reset_index(drop=True)
        y = np.arange(len(part))[::-1]
        for yi, row in zip(y, part.itertuples(index=False)):
            color = method_colors[row.method]
            ax.plot([row.ci_lower, row.ci_upper], [yi, yi], color=color, linewidth=2.4)
            ax.scatter(row.estimate, yi, color=color, s=75, zorder=3)
            label = f"{row.estimate:+.1f}"
            ax.text(row.ci_upper + (xlim[1] - xlim[0]) * 0.025, yi, label, va="center", fontsize=10)
        ax.axvline(0, color=TEXT, linewidth=1, linestyle="--")
        ax.set_yticks(y, part["method"])
        ax.set_xlim(*xlim)
        ax.set_xlabel(xlabel)
        ax.set_title(outcome, loc="left", fontsize=13, weight="bold")
        ax.grid(axis="x", color=LIGHT_GRAY, linewidth=0.8)
        ax.set_axisbelow(True)
        for spine in ["top", "right", "left"]:
            ax.spines[spine].set_visible(False)

    fig.suptitle("쿠폰 사용 고객의 60일 결과 차이와 불확실성", x=0.05, ha="left", fontsize=17, weight="bold")
    fig.text(
        0.05,
        0.90,
        "관찰 데이터 비교: 매칭 후에도 16개 공변량 중 6개가 |SMD| ≥ 0.1",
        fontsize=10.5,
        color="#5F6B73",
    )
    fig.text(
        0.05,
        0.015,
        "점은 평균 차이, 선은 bootstrap 95% CI. 72쌍 매칭 결과는 가설 생성용이며 전체 처치군 ATT 또는 인과효과로 해석하지 않는다.",
        fontsize=9,
        color="#5F6B73",
    )
    fig.tight_layout(rect=(0, 0.06, 1, 0.86), w_pad=3.5)
    save(fig, "matched_outcome_differences.png")


def matched_balance_chart() -> None:
    df = pd.read_csv(DATA / "matched_balance.csv")
    df["abs_before"] = df["smd_before"].abs()
    df["abs_after"] = df["smd_after"].abs()
    df = df.sort_values("abs_before", ascending=True).reset_index(drop=True)
    y = np.arange(len(df))

    fig, ax = plt.subplots(figsize=(10.5, 7.2))
    for yi, row in zip(y, df.itertuples(index=False)):
        ax.plot([row.abs_before, row.abs_after], [yi, yi], color=LIGHT_GRAY, linewidth=1.5)
    ax.scatter(df["abs_before"], y, color=GRAY, s=55, label="매칭 전", zorder=3)
    ax.scatter(df["abs_after"], y, color=ORANGE, s=55, label="매칭 후", zorder=3)
    ax.axvline(0.1, color=NAVY, linestyle="--", linewidth=1.3, label="균형 기준 0.1")
    ax.set_yticks(y, df["covariate"])
    ax.set_xlabel("|Standardized Mean Difference|")
    ax.set_xlim(0, max(0.30, df[["abs_before", "abs_after"]].to_numpy().max() * 1.1))
    ax.grid(axis="x", color=LIGHT_GRAY, linewidth=0.8)
    ax.legend(frameon=False, loc="lower right")
    for spine in ["top", "right", "left"]:
        ax.spines[spine].set_visible(False)
    fig.suptitle(
        "매칭 후에도 16개 공변량 중 6개가 균형 기준 밖",
        x=0.01,
        y=0.99,
        ha="left",
        fontsize=17,
        weight="bold",
    )
    fig.text(
        0.01,
        0.935,
        "점이 0에 가까울수록 두 집단의 관측 특성이 유사하다.",
        color="#5F6B73",
        fontsize=10.5,
    )
    fig.tight_layout(rect=(0, 0.02, 1, 0.90))
    save(fig, "psm_love_plot.png")


def main() -> None:
    configure_style()
    segment_revenue_chart()
    cohort_retention_chart()
    purchase_activity_ladder_chart()
    matched_effect_chart()
    matched_balance_chart()
    print("Built: segment_revenue_concentration.png")
    print("Built: cohort_retention_heatmap.png")
    print("Built: purchase_activity_ladder.png")
    print("Built: matched_outcome_differences.png")
    print("Built: psm_love_plot.png")


if __name__ == "__main__":
    main()
