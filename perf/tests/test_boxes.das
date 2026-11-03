options gen2
require dastest/testing_boost public
require strings
require daslib/json_boost
require ../boxes.das

[test]
def test_box_of(t : T?) {
    t |> run("each box's CPU model names its box") @(t : T?) {
        t |> equal(box_of("AMD Ryzen 3 1200 Quad-Core Processor"), "bench")
        t |> equal(box_of("AMD Ryzen 7 7435HS"), "PC")
        t |> equal(box_of("AMD FX(tm)-6300 Six-Core Processor"), "fx")
    }
    t |> run("another CPU, an unknown one and none name no box") @(t : T?) {
        t |> equal(box_of("Intel(R) Core(TM) i7-8700"), "")
        t |> equal(box_of("unknown cpu"), "")
        t |> equal(box_of(""), "")
    }
}

[test]
def test_box_label(t : T?) {
    t |> run("a box and a cpu: the box with the cpu in parentheses") @(t : T?) {
        t |> equal(box_label("bench", "AMD Ryzen 3 1200"), "bench (AMD Ryzen 3 1200)")
    }
    t |> run("one of them alone, then neither") @(t : T?) {
        t |> equal(box_label("", "Some CPU"), "Some CPU")
        t |> equal(box_label("fx", ""), "fx")
        t |> equal(box_label("", ""), "unlabelled box")
    }
}

[test]
def test_capture_box(t : T?) {
    t |> run("a named box wins over the cpu's") @(t : T?) {
        t |> equal(capture_box("PC", "AMD Ryzen 3 1200"), "PC")
    }
    t |> run("without a name, the cpu's box, or none") @(t : T?) {
        t |> equal(capture_box("", "AMD Ryzen 3 1200"), "bench")
        t |> equal(capture_box("", "unknown cpu"), "")
    }
}

[test]
def test_box_refusal(t : T?) {
    t |> run("no flag and every box name pass") @(t : T?) {
        t |> equal(box_refusal(""), "")
        for (name in ["bench", "PC", "fx"]) {
            t |> equal(box_refusal(name), "")
        }
    }
    t |> run("another name is refused, naming the boxes") @(t : T?) {
        t |> equal(box_refusal("laptop"), "--box takes bench, PC, fx, not `laptop`")
    }
}

def private parsed(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(replace(text, "'", "\""), error)
    t |> equal(error, "", "fixture is JSON")
    return js
}

[test]
def test_same_box(t : T?) {
    t |> run("one box: the same box field, the box of the cpu, or the same cpu without a box") @(t : T?) {
        t |> success(same_box(parsed(t, "\{'box': 'bench', 'cpu': 'X'\}"), parsed(t, "\{'cpu': 'AMD Ryzen 3 1200'\}")))
        t |> success(same_box(parsed(t, "\{'cpu': 'Other'\}"), parsed(t, "\{'cpu': 'Other', 'box': ''\}")))
        t |> success(same_box(parsed(t, "\{\}"), null))
    }
    t |> run("two boxes, or two cpus without a box") @(t : T?) {
        t |> success(!same_box(parsed(t, "\{'cpu': 'AMD FX(tm)-6300'\}"), parsed(t, "\{'cpu': 'AMD Ryzen 3 1200'\}")))
        t |> success(!same_box(parsed(t, "\{'cpu': 'X', 'box': 'PC'\}"), parsed(t, "\{'cpu': 'X'\}")))
        t |> success(!same_box(parsed(t, "\{'cpu': 'X'\}"), parsed(t, "\{'cpu': 'Y'\}")))
    }
}

[test]
def test_capture_label(t : T?) {
    t |> run("a capture with its box") @(t : T?) {
        t |> equal(capture_label(parsed(t, "\{'box': 'fx', 'cpu': 'AMD Ryzen 3 1200'\}")), "fx (AMD Ryzen 3 1200)")
    }
    t |> run("a capture with its cpu alone shows the cpu's box, or the cpu without one") @(t : T?) {
        t |> equal(capture_label(parsed(t, "\{'cpu': 'AMD Ryzen 3 1200'\}")), "bench (AMD Ryzen 3 1200)")
        t |> equal(capture_label(parsed(t, "\{'cpu': 'Other', 'box': ''\}")), "Other")
    }
    t |> run("a capture with neither, and no capture") @(t : T?) {
        t |> equal(capture_label(parsed(t, "\{'date': 'D'\}")), "unlabelled box")
        t |> equal(capture_label(null), "unlabelled box")
    }
}
