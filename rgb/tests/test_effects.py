def test_battery_level_color_low_is_pure_red(bl):
    assert bl.battery_level_color(10) == (255, 0, 0)


def test_battery_level_color_full_is_greenish(bl):
    r, g, b = bl.battery_level_color(100)
    assert g > r and g > b


def test_battery_step_buckets_by_ten(bl):
    assert bl._battery_step(None) is None
    assert bl._battery_step(0) == 0
    assert bl._battery_step(55) == 5
    assert bl._battery_step(100) == 10


def test_mchose_payload_red_breathing_encodes_red(bl):
    raw = bl.build_mchose_base_payload("red_breathing", 15, (10, 20, 30))
    assert raw[0] == 0x11
    dec = [raw[0]] + [x ^ 0xFF for x in raw[1:]]
    assert dec[1] == 0x2B
    assert (dec[10], dec[11], dec[12]) == (255, 0, 0)   # bytes de color del anillo


def test_mchose_payload_none_returns_none(bl):
    assert bl.build_mchose_base_payload("none", 50, (1, 2, 3)) is None


def test_akko_sidestrip_red_static_packet(bl):
    pkts = bl.build_akko_packets("sidestrip", "red_static", 12, (9, 9, 9))
    assert len(pkts) == 1
    body = pkts[0][1:]                 # quita Report ID 0x00
    assert body[0] == 0x08            # opcode tira lateral
    assert body[1] == 0x01            # modo fijo
    assert (body[5], body[6], body[7]) == (255, 0, 0)
    assert body[8] == (0xFF - (sum(body[:8]) & 0xFF)) & 0xFF


def test_akko_keys_theme_uses_theme_rgb(bl):
    pkts = bl.build_akko_packets("keys", "theme", 90, (12, 34, 56))
    body = pkts[0][1:]
    assert body[0] == 0x07
    assert (body[5], body[6], body[7]) == (12, 34, 56)


def test_akko_keys_wave_uses_firmware_mode_4(bl):
    pkts = bl.build_akko_packets("keys", "wave", 90, (12, 34, 56))
    assert len(pkts) == 1
    body = pkts[0][1:]
    assert body[0] == 0x07           # opcode teclas
    assert body[1] == 0x04           # modo Wave del firmware (1 escritura)
    assert (body[5], body[6], body[7]) == (12, 34, 56)


def test_akko_keys_wave_battery_low_is_red(bl):
    body = bl.build_akko_packets("keys", "wave_battery", 10, (1, 2, 3))[0][1:]
    assert body[1] == 0x04
    assert (body[5], body[6], body[7]) == (255, 0, 0)


def test_akko_stream_not_built_on_keys(bl):
    # 'stream' en las teclas era Ripple (inútil): ya no se genera paquete.
    assert bl.build_akko_packets("keys", "stream", 50, (1, 2, 3)) == []


def test_apply_magichome_none_does_not_call_subprocess(bl, monkeypatch):
    called = []
    monkeypatch.setattr(bl.subprocess, "run", lambda *a, **k: called.append(a))
    bl.apply_magichome("none", 10, (1, 2, 3))
    assert called == []


def test_apply_magichome_battery_color_calls_control_with_hex(bl, monkeypatch):
    calls = []
    monkeypatch.setattr(bl.subprocess, "run", lambda *a, **k: calls.append(list(a[0])))
    bl.apply_magichome("battery_color", 10, (1, 2, 3))
    flat = [tok for c in calls for tok in c]
    assert any("magichome-control" in tok for tok in flat)
    assert "ff0000" in flat            # rojo puro por nivel <= 15


def test_apply_openrgb_missing_sdk_is_swallowed(bl, monkeypatch):
    import builtins
    real = builtins.__import__
    def boom(name, *a, **k):
        if name == "openrgb":
            raise ImportError("no sdk")
        return real(name, *a, **k)
    monkeypatch.setattr(builtins, "__import__", boom)
    bl.apply_openrgb("solid_theme", 50, (1, 2, 3))   # no lanza
