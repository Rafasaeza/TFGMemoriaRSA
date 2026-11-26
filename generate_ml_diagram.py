"""Architecture diagram of the machine learning subsystem.

Design-level view: offline training, the shared ml-common contract,
the MLflow control plane, and Spark streaming inference.
"""

import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch


def create_ml_architecture_diagram():
    fig, ax = plt.subplots(figsize=(13.2, 7.4), dpi=220)
    ax.set_xlim(0, 13.2)
    ax.set_ylim(0, 7.4)
    ax.axis("off")
    fig.patch.set_facecolor("#FFFFFF")

    c_text = "#1F1F1F"
    c_muted = "#595959"

    def rounded(x, y, w, h, face, edge, lw=1.4, radius=0.08, ls="-"):
        patch = FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle=f"round,pad=0.012,rounding_size={radius}",
            facecolor=face,
            edgecolor=edge,
            linewidth=lw,
            linestyle=ls,
            zorder=2,
        )
        ax.add_patch(patch)

    def label(x, y, text, size, weight="regular", color=c_text, ha="center", va="center"):
        ax.text(
            x,
            y,
            text,
            fontsize=size,
            fontweight=weight,
            color=color,
            ha=ha,
            va=va,
            zorder=5,
            linespacing=1.25,
        )

    def arrow(x1, y1, x2, y2, color, lw=1.6, ls="-"):
        ax.add_patch(
            FancyArrowPatch(
                (x1, y1),
                (x2, y2),
                arrowstyle="-|>",
                mutation_scale=11,
                linewidth=lw,
                linestyle=ls,
                color=color,
                zorder=4,
                shrinkA=0,
                shrinkB=0,
            )
        )

    # --- Offline training -------------------------------------------------
    rounded(0.25, 4.55, 8.55, 2.6, "#F4F7FA", "#4A6FA5", lw=1.8, radius=0.12)
    label(0.45, 6.9, "OFFLINE TRAINING", 11, "bold", "#1D39C4", ha="left", va="center")

    steps = [
        (0.45, "Silver snapshot", "fleet_features\nconsistent Iceberg read"),
        (2.5, "Per-vehicle windows", "shared contract,\nthen chronological split"),
        (4.55, "Standardize", "fit on training\nwindows only"),
        (6.6, "GRU autoencoder", "MSE, Adam,\nearly stopping"),
    ]
    for x, title, body in steps:
        face = "#E6F7FF" if title in ("Standardize", "GRU autoencoder") else "#FFFFFF"
        edge = "#1890FF" if title in ("Standardize", "GRU autoencoder") else "#D9D9D9"
        rounded(x, 4.85, 1.9, 1.55, face, edge, lw=1.2, radius=0.08)
        label(x + 0.95, 5.95, title, 8.5, "bold")
        label(x + 0.95, 5.4, body, 7, color=c_muted)

    for x in (2.35, 4.4, 6.45):
        arrow(x, 5.62, x + 0.15, 5.62, "#1890FF", lw=1.5)

    # --- MLflow control plane ---------------------------------------------
    rounded(9.0, 4.55, 3.95, 2.6, "#FFFBF0", "#D48806", lw=1.8, radius=0.12)
    label(9.2, 6.9, "MLFLOW CONTROL PLANE", 11, "bold", "#D46B08", ha="left")

    rounded(9.2, 6.05, 3.55, 0.7, "#FFF7E6", "#FFBB96", lw=1.15, radius=0.06)
    label(10.97, 6.52, "Experiment tracking", 8, "bold", "#D4380D")
    label(10.97, 6.26, "parameters and metrics of the run", 7, color=c_muted)

    rounded(9.2, 5.2, 3.55, 0.7, "#FFF7E6", "#FFBB96", lw=1.15, radius=0.06)
    label(10.97, 5.67, "Model Registry", 8, "bold", "#D4380D")
    label(10.97, 5.41, "promoted production version", 7, color=c_muted)

    rounded(9.2, 4.72, 3.55, 0.38, "#FFFFFF", "#FFBB96", lw=1.0, radius=0.05)
    label(10.97, 4.91, "Fitted scaler bound to that same run", 7, color=c_muted)

    arrow(8.5, 5.62, 9.2, 5.55, "#D48806", lw=1.6, ls="--")
    label(8.85, 5.95, "publish", 7, "bold", "#D46B08")

    # --- Shared contract --------------------------------------------------
    rounded(0.25, 3.15, 8.55, 1.15, "#F9F0FF", "#722ED1", lw=1.8, radius=0.1)
    label(
        4.52,
        3.95,
        "SHARED CONTRACT    ml-common",
        10,
        "bold",
        "#531DAB",
    )
    label(
        4.52,
        3.5,
        "Feature order, window length and step, gap rule, threshold policy.\n"
        "Consumed by training and by inference. Holds no fitted statistics.",
        7.5,
        color=c_muted,
    )

    # Contract feeds both windowing steps. Arrowheads point at the consumers.
    arrow(3.45, 4.30, 3.45, 4.85, "#722ED1", lw=1.5)
    arrow(3.95, 3.15, 3.95, 2.95, "#722ED1", lw=1.5)
    label(3.58, 4.42, "same window rules", 7, "bold", "#722ED1", ha="left")

    # --- Online inference -------------------------------------------------
    rounded(0.25, 0.25, 12.7, 2.55, "#F6FFED", "#4C8C4A", lw=1.8, radius=0.12)
    label(
        0.45,
        2.52,
        "ONLINE INFERENCE    Spark Structured Streaming",
        11,
        "bold",
        "#237804",
        ha="left",
    )

    infer = [
        (0.45, "fleet-features", "Redpanda micro-batches", False),
        (2.85, "Per-vehicle windows", "contract validation\nand gap rule", False),
        (5.25, "Promoted scaler", "training mean\nand variance", True),
        (7.65, "GRU reconstruction", "score and channel\ncontribution", True),
        (10.05, "fleet-anomalies", "normal / suspicious\n/ anomalous", False),
    ]
    for x, title, body, highlight in infer:
        face = "#F6FFED" if highlight else "#FFFFFF"
        edge = "#52C41A" if highlight else "#D9D9D9"
        rounded(x, 0.55, 2.2, 1.45, face, edge, lw=1.15, radius=0.08)
        label(x + 1.1, 1.5, title, 8.5, "bold")
        label(x + 1.1, 0.98, body, 7, color=c_muted)

    for x in (2.65, 5.05, 7.45, 9.85):
        arrow(x, 1.27, x + 0.2, 1.27, "#237804", lw=1.5)

    # Promoted bundle lands between the scaler and the reconstruction step.
    arrow(10.98, 4.55, 10.98, 3.05, "#D48806", lw=1.7)
    arrow(10.98, 3.05, 7.55, 3.05, "#D48806", lw=1.5)
    arrow(7.55, 3.05, 7.55, 2.05, "#D48806", lw=1.5)
    label(11.1, 3.85, "load promoted\nmodel and scaler", 7, "bold", "#D46B08", ha="left")

    plt.tight_layout(pad=0.15)
    fig.savefig(
        "figures/ml-subsystem-architecture.drawio.png",
        dpi=220,
        bbox_inches="tight",
        facecolor="white",
    )
    plt.close()
    print("Wrote figures/ml-subsystem-architecture.drawio.png")


if __name__ == "__main__":
    create_ml_architecture_diagram()
