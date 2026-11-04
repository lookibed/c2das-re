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
    t |> run("no flag, every box name on an unknown CPU, and the CPU's own box pass") @(t : T?) {
        t |> equal(box_refusal("", "AMD Ryzen 3 1200"), "")
        for (name in ["bench", "PC", "fx"]) {
            t |> equal(box_refusal(name, "unknown cpu"), "")
        }
        t |> equal(box_refusal("bench", "AMD Ryzen 3 1200 Quad-Core Processor"), "")
    }
    t |> run("another name is refused, naming the boxes") @(t : T?) {
        t |> equal(box_refusal("laptop", "unknown cpu"), "--box takes bench, PC, fx, not `laptop`")
    }
    t |> run("a box the CPU contradicts is refused: a wrong label is worse than none") @(t : T?) {
        t |> equal(box_refusal("fx", "AMD Ryzen 7 7435HS"), "--box fx names another box than this CPU's: AMD Ryzen 7 7435HS is PC")
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
    }
    t |> run("two boxes, or two cpus without a box") @(t : T?) {
        t |> success(!same_box(parsed(t, "\{'cpu': 'AMD FX(tm)-6300'\}"), parsed(t, "\{'cpu': 'AMD Ryzen 3 1200'\}")))
        t |> success(!same_box(parsed(t, "\{'cpu': 'X', 'box': 'PC'\}"), parsed(t, "\{'cpu': 'X'\}")))
        t |> success(!same_box(parsed(t, "\{'cpu': 'X'\}"), parsed(t, "\{'cpu': 'Y'\}")))
    }
    t |> run("a capture naming neither box nor cpu matches none, not even another such") @(t : T?) {
        t |> success(!same_box(parsed(t, "\{\}"), parsed(t, "\{\}")))
        t |> success(!same_box(null, parsed(t, "\{'cpu': 'X'\}")))
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
