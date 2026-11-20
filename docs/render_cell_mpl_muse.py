# render_cell_mpl_muse.py — draw one sky130 standard cell's real GDS
# geometry with matplotlib: the transistor-level portrait.
# _muse — written 2026-11-20.
#
# Why not KLayout's own renderer: the headless pip-module LayoutView
# would not apply layer properties in this environment (three attempts,
# byte-identical empty frames — see the §3.3 log). This script reads
# the same GDS through klayout.db and plots every polygon itself, in
# the conventional sky130 colour scheme, so what you see is exactly
# what is in the PDK file: diffusion, poly gates, local interconnect,
# metal-1, wells.
#
# Usage:
#   GDS=.../sky130_fd_sc_hd.gds CELL=sky130_fd_sc_hd__dfxtp_1 \
#   OUT=cell_dfxtp_1.png python3 render_cell_mpl_muse.py
import os

import klayout.db as db
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MplPolygon

# sky130 geometry layers, datatype 20 (drawing) only. Other layers in
# the cell GDS are pins, labels and markers (one of them, 81/4, is a
# full-cell rectangle that floods the plot if drawn as geometry).
# sky130 layer number -> (name, colour, alpha, zorder)
LAYERS = {
    64: ("nwell", "#8a6d3b", 0.35, 1),
    65: ("diffusion", "#27ae60", 0.85, 3),
    66: ("poly (gates)", "#e74c3c", 0.9, 4),
    67: ("local interconnect", "#3498db", 0.75, 5),
    68: ("metal-1", "#a0c4e8", 0.65, 6),
    69: ("metal-2", "#5d6d7e", 0.6, 7),
    236: ("cell boundary", "#ffffff", 1.0, 9),
}
TEXT_LAYERS = {5, 16, 44, 59, 20}  # label datatypes across layers


def main():
    gds = os.environ["GDS"]
    cell_name = os.environ["CELL"]
    out = os.environ["OUT"]

    ly = db.Layout()
    ly.read(gds)
    cell = ly.cell(cell_name)
    if cell is None:
        raise SystemExit("cell not found: " + cell_name)
    dbu = ly.dbu

    fig, ax = plt.subplots(figsize=(14, 8), dpi=170)
    fig.patch.set_facecolor("#101018")
    ax.set_facecolor("#101018")

    used = {}
    for li in ly.layer_indexes():
        info = ly.get_info(li)
        layer_no, dtype = info.layer, info.datatype
        for shape in cell.shapes(li):
            if shape.is_text():
                if dtype in TEXT_LAYERS:
                    t = shape.text
                    ax.annotate(
                        t.string,
                        (t.x * dbu, t.y * dbu),
                        color="#ecf0f1",
                        fontsize=7,
                        ha="center",
                        va="center",
                    )
                continue
            if not ((layer_no in LAYERS and dtype == 20) or layer_no == 236):
                continue
            try:
                poly = shape.polygon
            except Exception:
                continue
            pts = [(p.x * dbu, p.y * dbu) for p in poly.each_point_hull()]
            if layer_no == 236:
                ax.add_patch(
                    MplPolygon(
                        pts, closed=True, fill=False,
                        edgecolor="#ffffff", linewidth=1.2, zorder=9,
                    )
                )
                continue
            name, color, alpha, z = LAYERS.get(
                layer_no, ("layer %d" % layer_no, "#e67e22", 0.6, 5)
            )
            used[layer_no] = (name, color)
            ax.add_patch(
                MplPolygon(
                    pts, closed=True, facecolor=color, edgecolor="none",
                    alpha=alpha, zorder=z,
                )
            )

    bb = cell.bbox()
    ax.set_xlim(bb.left * dbu - 0.5, bb.right * dbu + 0.5)
    ax.set_ylim(bb.bottom * dbu - 0.5, bb.top * dbu + 0.5)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(
        "%s — sky130_fd_sc_hd layout (%.2f x %.2f um)\n"
        "the standard cell this design is built from"
        % (cell_name, bb.width() * dbu, bb.height() * dbu),
        color="#ecf0f1",
        fontsize=11,
    )
    handles = [
        MplPolygon(
            [[0, 0]], closed=True, facecolor=c, edgecolor="none", label=n
        )
        for _, (n, c) in sorted(used.items())
    ]
    if handles:
        ax.legend(
            handles=handles, loc="upper center",
            bbox_to_anchor=(0.5, -0.02), ncol=5, frameon=False,
            labelcolor="#ecf0f1", fontsize=8,
        )
    fig.savefig(out, facecolor=fig.get_facecolor(), bbox_inches="tight")
    print("wrote", out)


if __name__ == "__main__":
    main()
