pragma Singleton
import Quickshell

Singleton {
    id: root

    // Remove "file://" protocol prefix from a path
    function trimFileProtocol(path) {
        if (typeof path !== "string") return "";
        if (path.startsWith("file://")) return path.substring(7);
        return path;
    }

    // Add "file://" protocol prefix if not present
    function ensureFileProtocol(path) {
        if (typeof path !== "string") return "";
        if (path.startsWith("file://")) return path;
        return "file://" + path;
    }

    // A file:// URL for a path (names may hold '#', '?' or spaces).
    function fileUrl(path) {
        if (typeof path !== "string" || path.length === 0) return "";
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    // Image source for an icon given as a theme name, a path or a URL
    // (notification appIcon/image can be any of these).
    function iconSource(icon) {
        if (typeof icon !== "string" || icon.length === 0) return "";
        // Quickshell hands theme names over as image://icon/<name> already.
        if (icon.startsWith("image://icon/")) icon = icon.slice(13).split("?")[0];
        else if (icon.includes("://")) return icon;
        if (icon.startsWith("/")) return "file://" + icon;
        // A name the theme lacks would draw the magenta "missing" square.
        return Quickshell.hasThemeIcon(icon) ? "image://icon/" + icon : "";
    }

    // Image source for an app's icon (by app id or desktop-entry icon name):
    // the desktop entry's icon, else the name itself. A name the icon theme
    // lacks would draw Qt's magenta "missing" square, so it falls back to a
    // generic application icon (or nothing, if the theme has none either).
    function appIcon(appIdOrIcon) {
        void DesktopEntries.applications.values.length // re-run once entries load
        const id = typeof appIdOrIcon === "string" ? appIdOrIcon : ""
        return root.themedIcon(DesktopEntries.heuristicLookup(id)?.icon || id)
    }
    function themedIcon(name) {
        if (typeof name === "string" && (name.startsWith("/") || name.includes("://"))) return root.iconSource(name)
        if (typeof name === "string" && name.length > 0 && Quickshell.hasThemeIcon(name)) return "image://icon/" + name
        const generic = ["application-x-executable", "application-default-icon", "applications-other"].find(n => Quickshell.hasThemeIcon(n))
        return generic ? "image://icon/" + generic : ""
    }

    // Get filename from path
    function basename(path) {
        if (typeof path !== "string") return "";
        let cleaned = trimFileProtocol(path);
        let parts = cleaned.split("/");
        return parts[parts.length - 1] || "";
    }

    // Get directory from path
    function dirname(path) {
        if (typeof path !== "string") return "";
        let cleaned = trimFileProtocol(path);
        let parts = cleaned.split("/");
        parts.pop();
        return parts.join("/");
    }

    // Get file extension (without dot)
    function extension(path) {
        let name = basename(path);
        let dotIndex = name.lastIndexOf(".");
        if (dotIndex <= 0) return "";
        return name.substring(dotIndex + 1).toLowerCase();
    }

    // Check if path looks like an image file
    function isImage(path) {
        let ext = extension(path);
        return ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg", "avif", "ico", "tiff"].indexOf(ext) >= 0;
    }

    // Check if path looks like a video file
    function isVideo(path) {
        let ext = extension(path);
        return ["mp4", "webm", "mkv", "avi", "mov", "wmv", "flv", "m4v"].indexOf(ext) >= 0;
    }

    // Join path components
    function joinPath() {
        let parts = [];
        for (let i = 0; i < arguments.length; i++) {
            let p = arguments[i];
            if (typeof p === "string" && p.length > 0) {
                parts.push(p.replace(/\/+$/, ""));
            }
        }
        return parts.join("/");
    }
}
