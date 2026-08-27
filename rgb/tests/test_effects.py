def test_battery_level_color_low_is_pure_red(bl):
    assert bl.battery_level_color(10) == (255, 0, 0)


def test_battery_level_color_full_is_greenish(bl):
    r, g, b = bl.battery_level_color(100)
    assert g > r and g > b


def test_meter_rows_scales(bl):
    assert bl.meter_rows(0, 5) == 0
    assert bl.meter_rows(1, 5) == 1
    assert bl.meter_rows(50, 5) == 3          # round(2.5)
    assert bl.meter_rows(100, 5) == 5


def test_akko_canvas_chunks_shape(bl):
    chunks = bl.akko_canvas_chunks([(1, 2, 3)] * 130)
    assert len(chunks) == 7
    assert all(len(c) == 64 for c in chunks)
    assert chunks[0][0] == 0x0C
    assert chunks[0][4] == 0        # chunk_index del primer chunk
    assert chunks[6][4] == 6


def test_akko_meter_keys_all_off_at_zero(bl):
    keys = bl.akko_meter_keys(0)
    assert len(keys) == 130
    assert set(keys) == {(0, 0, 0)}


def test_akko_meter_keys_full_lights_bottom_rows(bl):
    keys = bl.akko_meter_keys(100)
    # al menos las teclas mapeadas de la fila inferior están encendidas
    lit = [keys[i] for i in bl.AKKO_KEY_ROWS[-1]]
    assert all(px != (0, 0, 0) for px in lit)


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
