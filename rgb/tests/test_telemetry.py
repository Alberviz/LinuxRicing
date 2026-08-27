def test_write_then_shape_of_cache(bl, tmp_path):
    tele = {
        "akko_keyboard": {"level": 80, "charging": True, "connected": True},
        "mchose_mouse": {"level": 40, "charging": False, "connected": True},
        "v9_headset": {"level": None, "charging": False, "connected": False},
    }
    bl.write_battery_cache(tele)
    import json
    data = json.loads(open(bl.BATTERY_CACHE).read())
    assert data["akko_battery"] == 80
    assert data["akko_status"] == "Cargando"
    assert data["k7_status"] == "Descargando"


def test_write_battery_cache_preserves_notified_levels(bl):
    import json
    with open(bl.BATTERY_CACHE, "w") as f:
        json.dump({"notified_levels": {"k7": 20}}, f)
    bl.write_battery_cache({"akko_keyboard": {"level": 50, "charging": False, "connected": True},
                            "mchose_mouse": {"level": None, "charging": False, "connected": False},
                            "v9_headset": {"level": None, "charging": False, "connected": False}})
    assert json.loads(open(bl.BATTERY_CACHE).read())["notified_levels"] == {"k7": 20}


def test_read_telemetry_runs_without_hardware(bl):
    tele = bl.read_telemetry()
    assert set(tele) == {"akko_keyboard", "mchose_mouse", "v9_headset"}
    for v in tele.values():
        assert {"level", "charging", "connected", "status", "mode"}.issubset(set(v))
