def _tele(akko=None, mouse=None, v9=None):
    base = {"level": None, "charging": False, "connected": False}
    def m(d): return {**base, **(d or {})}
    return {"akko_keyboard": m(akko), "mchose_mouse": m(mouse), "v9_headset": m(v9)}


def test_low_rule_fires_below_threshold(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 18, "connected": True}))
    assert out["mchose_base:_"]["effect"] == "red_breathing"
    assert out["mchose_base:_"]["trigger"] == "low"


def test_low_rule_silent_above_threshold(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]}]}
    assert bl.resolve(cfg, _tele(mouse={"level": 55, "connected": True})) == {}


def test_charging_rule_fires_when_charging(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "mchose_mouse", "trigger": "charging", "threshold": None,
         "actions": [{"target": "mchose_base", "effect": "theme_breathing"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 40, "charging": True, "connected": True}))
    assert out["mchose_base:_"]["trigger"] == "charging"


def test_critical_beats_low_on_same_zone(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "low", "source": "mchose_mouse", "trigger": "low", "threshold": 30,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]},
        {"id": "crit", "source": "mchose_mouse", "trigger": "critical", "threshold": None,
         "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 8, "connected": True}))
    assert out["mchose_base:_"]["effect"] == "red_static"


def test_same_severity_first_rule_wins(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "a", "source": "mchose_mouse", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_breathing"}]},
        {"id": "b", "source": "v9_headset", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    out = bl.resolve(cfg, _tele(mouse={"level": 10, "connected": True},
                                v9={"level": 10, "connected": True}))
    assert out["mchose_base:_"]["effect"] == "red_breathing"


def test_both_zone_expands(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "akko_keyboard", "trigger": "low", "threshold": 20,
         "actions": [{"target": "akko_keyboard", "zone": "both", "effect": "red_breathing"}]}]}
    out = bl.resolve(cfg, _tele(akko={"level": 12, "connected": True}))
    assert set(out) == {"akko_keyboard:keys", "akko_keyboard:sidestrip"}


def test_disconnected_source_never_fires(bl):
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "r", "source": "v9_headset", "trigger": "low", "threshold": 20,
         "actions": [{"target": "mchose_base", "effect": "red_static"}]}]}
    assert bl.resolve(cfg, _tele(v9={"level": 5, "connected": False})) == {}


def test_charging_rule_not_active_when_also_low_and_discharging(bl):
    # descargando al 8%: la regla 'charging' no aplica aunque exista
    cfg = {"critical_threshold": 10, "rules": [
        {"id": "c", "source": "akko_keyboard", "trigger": "charging", "threshold": None,
         "actions": [{"target": "akko_keyboard", "zone": "sidestrip", "effect": "stream_battery"}]}]}
    assert bl.resolve(cfg, _tele(akko={"level": 8, "charging": False, "connected": True})) == {}
