"""Drift check: SettingsPopup.qml (the schema), manifest.json and BarWidget.qml must agree.
Also: no native text input anywhere, balanced braces, helper files present."""
import json, os, re

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
rd = lambda f: open(os.path.join(root, f), encoding="utf-8").read()

pop = rd("SettingsPopup.qml")
block = pop[pop.index("readonly property var tabs: ["):pop.index("readonly property var defaults")]
schema = {}
for chunk in block.split('{ key: "')[1:]:
    if "fallback:" not in chunk:
        continue                                   # a `when` condition, not a setting
    key = chunk[:chunk.index('"')]
    kind = re.search(r'kind: "(\w+)"', chunk).group(1)
    fb = json.loads(re.search(r'fallback: ("(?:[^"\\]|\\.)*"|true|false|-?[\d.]+)', chunk).group(1))
    opts = re.search(r"options: (\[[^\]]*\])", chunk)
    mn, mx = re.search(r"min: (-?\d+)", chunk), re.search(r"max: (-?\d+)", chunk)
    schema[key] = dict(kind=kind, fallback=fb, options=json.loads(opts.group(1)) if opts else None,
                       min=int(mn.group(1)) if mn else None, max=int(mx.group(1)) if mx else None)

m = json.load(open(os.path.join(root, "manifest.json")))["barWidget"]
types = {"enum": "enum", "scheme": "enum", "int": "integer", "bool": "boolean", "string": "string", "color": "string"}
assert set(schema) == {s["key"] for s in m["schema"]} == set(m["defaults"]), "popup / manifest keys differ"
for s in m["schema"]:
    p = schema[s["key"]]
    assert s["type"] == types[p["kind"]], s["key"] + ": type"
    assert s["defaultValue"] == p["fallback"] == m["defaults"][s["key"]], s["key"] + ": default"
    assert s.get("options") == p["options"], s["key"] + ": options"
    assert s.get("min") == p["min"] and s.get("max") == p["max"], s["key"] + ": range"

bar = rd("BarWidget.qml")
for key in schema:
    assert 'setting("%s"' % key in bar, "BarWidget.qml does not read " + key

assert schema["gridColor"]["fallback"] == re.search(r'DEFAULT_COLOR = "(#[0-9a-f]{6})"', rd("Stats.js")).group(1), "grid color default differs from Stats.js"
assert os.path.isfile(os.path.join(root, "bin", "dev-stats.sh"))
for f in ("Foreground.qml", "SettingsStore.qml", "SettingRow.qml", "Stats.js", "LICENSE"):
    assert os.path.isfile(os.path.join(root, f)), "missing " + f
for f in os.listdir(root):
    if f.endswith(".qml"):
        t = rd(f)
        assert not re.search(r"\b(TextInput|TextField|TextArea|TextEdit)\b\s*\{", t), f + " creates a native text element"
        assert "import QtQuick.Controls" not in t, f + " imports QtQuick.Controls"
        assert t.count("{") == t.count("}"), f + ": unbalanced braces"
print("ok")
