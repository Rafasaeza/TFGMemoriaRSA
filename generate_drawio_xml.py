"""Editable diagrams.net source for the ML subsystem architecture figure."""

import xml.etree.ElementTree as ET


def generate_drawio_xml():
    root = ET.Element(
        "mxfile",
        host="app.diagrams.net",
        agent="architecture-revision",
        version="22.0.0",
        type="device",
    )
    diagram = ET.SubElement(root, "diagram", name="ML-Subsystem-Architecture", id="ml_arch")
    model = ET.SubElement(
        diagram,
        "mxGraphModel",
        dx="1400",
        dy="800",
        grid="1",
        gridSize="10",
        guides="1",
        tooltips="1",
        connect="1",
        arrows="1",
        fold="1",
        page="1",
        pageScale="1",
        pageWidth="1400",
        pageHeight="780",
        math="0",
        shadow="0",
    )
    graph = ET.SubElement(model, "root")
    ET.SubElement(graph, "mxCell", id="0")
    ET.SubElement(graph, "mxCell", id="1", parent="0")

    def cell(cid, value, style, x, y, w, h):
        node = ET.SubElement(
            graph, "mxCell", id=cid, value=value, style=style, vertex="1", parent="1"
        )
        ET.SubElement(
            node,
            "mxGeometry",
            x=str(x),
            y=str(y),
            width=str(w),
            height=str(h),
            **{"as": "geometry"},
        )

    def edge(cid, source, target, style, value=""):
        node = ET.SubElement(
            graph,
            "mxCell",
            id=cid,
            value=value,
            style=style,
            edge="1",
            source=source,
            target=target,
            parent="1",
        )
        ET.SubElement(node, "mxGeometry", relative="1", **{"as": "geometry"})

    lane_train = (
        "swimlane;whiteSpace=wrap;html=1;fillColor=#f4f7fa;strokeColor=#4A6FA5;"
        "fontColor=#1D39C4;fontStyle=1;fontSize=14;rounded=1;arcSize=4;"
        "horizontal=1;startSize=32;"
    )
    lane_mlflow = (
        "swimlane;whiteSpace=wrap;html=1;fillColor=#fffbf0;strokeColor=#D48806;"
        "fontColor=#D46B08;fontStyle=1;fontSize=14;rounded=1;arcSize=4;startSize=32;"
    )
    lane_infer = (
        "swimlane;whiteSpace=wrap;html=1;fillColor=#f6ffed;strokeColor=#4C8C4A;"
        "fontColor=#237804;fontStyle=1;fontSize=14;rounded=1;arcSize=4;startSize=32;"
    )
    box = (
        "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#d9d9d9;"
        "fontColor=#262626;fontSize=12;spacing=6;arcSize=10;"
    )
    box_hi = (
        "rounded=1;whiteSpace=wrap;html=1;fillColor=#e6f7ff;strokeColor=#1890ff;"
        "fontColor=#262626;fontSize=12;spacing=6;arcSize=10;"
    )
    box_gold = (
        "rounded=1;whiteSpace=wrap;html=1;fillColor=#fff7e6;strokeColor=#ffa940;"
        "fontColor=#d4380d;fontSize=12;spacing=6;arcSize=10;"
    )
    contract = (
        "rounded=1;whiteSpace=wrap;html=1;fillColor=#f9f0ff;strokeColor=#722ED1;"
        "fontColor=#531DAB;fontStyle=1;fontSize=13;spacing=8;arcSize=8;"
    )
    arr = (
        "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeColor=#1890FF;"
        "strokeWidth=2;endArrow=block;endFill=1;"
    )
    arr_orange = (
        "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeColor=#D48806;"
        "strokeWidth=2;dashed=1;endArrow=block;endFill=1;fontColor=#D46B08;fontStyle=1;"
    )
    arr_purple = (
        "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeColor=#722ED1;"
        "strokeWidth=2;endArrow=block;endFill=1;fontColor=#531DAB;fontStyle=1;"
    )
    arr_green = (
        "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeColor=#237804;"
        "strokeWidth=2;endArrow=block;endFill=1;"
    )

    cell("train", "OFFLINE TRAINING", lane_train, 20, 20, 860, 250)
    cell(
        "t1",
        "<b>Silver snapshot</b><br><font color='#595959'>fleet_features, consistent read</font>",
        box,
        40,
        70,
        180,
        70,
    )
    cell(
        "t2",
        "<b>Per-vehicle windows</b><br><font color='#595959'>shared contract, then chronological split</font>",
        box,
        250,
        70,
        190,
        70,
    )
    cell(
        "t3",
        "<b>Standardize</b><br><font color='#595959'>fit on training windows only</font>",
        box_hi,
        470,
        70,
        180,
        70,
    )
    cell(
        "t4",
        "<b>GRU autoencoder</b><br><font color='#595959'>MSE, Adam, early stopping</font>",
        box_hi,
        680,
        70,
        180,
        70,
    )
    edge("e1", "t1", "t2", arr)
    edge("e2", "t2", "t3", arr)
    edge("e3", "t3", "t4", arr)

    cell("mlflow", "MLFLOW CONTROL PLANE", lane_mlflow, 910, 20, 360, 250)
    cell(
        "m1",
        "<b>Experiment tracking</b><br><font color='#595959'>parameters and metrics</font>",
        box_gold,
        930,
        70,
        320,
        50,
    )
    cell(
        "m2",
        "<b>Model Registry</b><br><font color='#595959'>promoted production version</font>",
        box_gold,
        930,
        135,
        320,
        50,
    )
    cell(
        "m3",
        "<font color='#595959'>Fitted scaler bound to that same run</font>",
        box_gold,
        930,
        200,
        320,
        40,
    )
    edge("epub", "t4", "m2", arr_orange, "publish")

    cell(
        "contract",
        "<b>SHARED CONTRACT · ml-common</b><br><font color='#595959'>"
        "Feature order, window length and step, gap rule, threshold policy.<br>"
        "Consumed by training and by inference. Holds no fitted statistics.</font>",
        contract,
        20,
        300,
        860,
        90,
    )
    edge("ec1", "contract", "t2", arr_purple, "same window rules")

    cell(
        "infer",
        "ONLINE INFERENCE · Spark Structured Streaming",
        lane_infer,
        20,
        420,
        1250,
        220,
    )
    cell(
        "i1",
        "<b>fleet-features</b><br><font color='#595959'>Redpanda micro-batches</font>",
        box,
        40,
        480,
        200,
        70,
    )
    cell(
        "i2",
        "<b>Per-vehicle windows</b><br><font color='#595959'>contract validation and gap rule</font>",
        box,
        280,
        480,
        210,
        70,
    )
    cell(
        "i3",
        "<b>Promoted scaler</b><br><font color='#595959'>training mean and variance</font>",
        box_hi,
        530,
        480,
        200,
        70,
    )
    cell(
        "i4",
        "<b>GRU reconstruction</b><br><font color='#595959'>score and channel contribution</font>",
        box_hi,
        770,
        480,
        210,
        70,
    )
    cell(
        "i5",
        "<b>ai-anomalies</b><br><font color='#595959'>normal / suspicious / anomalous</font>",
        box,
        1020,
        480,
        220,
        70,
    )
    edge("ei1", "i1", "i2", arr_green)
    edge("ei2", "i2", "i3", arr_green)
    edge("ei3", "i3", "i4", arr_green)
    edge("ei4", "i4", "i5", arr_green)
    edge("ec2", "contract", "i2", arr_purple)
    edge("eload", "m2", "i3", arr_orange, "load promoted model and scaler")

    tree = ET.ElementTree(root)
    tree.write(
        "figures/ml-subsystem-architecture.drawio",
        encoding="utf-8",
        xml_declaration=True,
    )
    print("Wrote figures/ml-subsystem-architecture.drawio")


if __name__ == "__main__":
    generate_drawio_xml()
