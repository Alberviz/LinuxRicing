import QtQuick
import Caelestia.Config
import qs.services

ColorAnimation {
    duration: PowerSaving.active ? 0 : Tokens.anim.durations.expressiveSlowEffects
    easing: Tokens.anim.expressiveSlowEffects
}
