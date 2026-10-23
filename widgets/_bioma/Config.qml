pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common as Ano
import qs.services as AnoServices

// Bioma's Config.get for the ported organisms and their services: the few
// keys AnoShell has its own setting for come from AnoShell's config, the rest
// keep Bioma's defaults. An organism's own options come from its widget's
// settings, not from here.
Singleton {
    id: root

    function get(key, fallback) {
        switch (key) {
        // No city set: the bar's weather finds one from the IP address; use what it found.
        case "weather.city": {
            const city = (Ano.Config.options?.bar?.weather?.city ?? "").trim()
            if (city) return city
            const found = AnoServices.Weather.data?.city
            return typeof found === "string" && found !== "City" ? found : fallback
        }
        case "weather.minutes": return Ano.Config.options?.bar?.weather?.fetchInterval ?? fallback
        case "weather.fahrenheit": return Ano.Config.options?.bar?.weather?.useUSCS ?? fallback
        case "fonts.technical": return Ano.Appearance.font.family.numbers || fallback
        case "fonts.expressive": return Ano.Appearance.font.family.expressive || Ano.Appearance.font.family.title || fallback
        case "animations.enable": return Ano.Config.options?.animations?.enable ?? fallback
        }
        return fallback
    }
}
