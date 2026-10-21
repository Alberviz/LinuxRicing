import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        PowerSaving;
        ServerMode;
        TabletDisplay;
        Notifs;
        Players;
        Brightness;
        Agents;
        Weather.reload();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
