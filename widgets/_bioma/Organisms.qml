pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common as Ano

// What the ported organisms ask Bioma's organism registry: a cell's option.
// The only one they use is the clock's 12/24 hours, from AnoShell's time format.
Singleton {
    function cellOption(type, key, fallback) {
        if (type === "clock" && key === "format")
            return /h/.test(Ano.Config.options?.time?.format ?? "hh:mm") && !/ap/i.test(Ano.Config.options?.time?.format ?? "") ? "24h" : "12h"
        return fallback
    }
}
