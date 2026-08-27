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
