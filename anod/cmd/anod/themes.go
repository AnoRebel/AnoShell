package main

import (
	"context"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/ipc"
	"ano/anod/internal/themestudio"
	"ano/anod/internal/wallpaper"
)

// registerThemes serves the Theme studio (Settings → Appearance) and static
// theme application:
//
//	theme.generate {primary, secondary?, tertiary?, mode?, schemeType?, overrides?} → {colors}   (preview, nothing written)
//	theme.save     {name, …the same}  → {name: slug, colors}  (cfg/anoshell/themes/<slug>.json)
//	theme.delete   {name: slug}       → true                  (studio-made themes only)
//	theme.apply    {name: slug}       → wallpaper.Result      (colors.json, GTK, the hooks that don't read the image)
func registerThemes(ctx context.Context, srv *ipc.Server, wp *wallpaper.Pipeline) {
	store := themestudio.Store{
		UserDir:    filepath.Join(filepath.Dir(config.UserPath()), "themes"),
		BundledDir: filepath.Join(config.ShellDir(), "assets", "themes"),
	}
	matugen := func(ctx context.Context, args ...string) ([]byte, error) {
		c, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		return exec.CommandContext(c, "matugen", args...).Output()
	}
	generate := func(p json.RawMessage, save bool) (any, error) {
		var req themestudio.Request
		if err := json.Unmarshal(p, &req); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {name?, primary, secondary?, tertiary?, mode?, schemeType?, overrides?}")
		}
		if err := req.Validate(save); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		if _, err := exec.LookPath("matugen"); err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "matugen is not installed")
		}
		colors, err := themestudio.Generate(ctx, matugen, wp.MatugenConfig(), req)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		if !save {
			return map[string]any{"colors": colors}, nil
		}
		slug, err := store.Save(req, colors)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return map[string]any{"name": slug, "colors": colors}, nil
	}
	srv.HandleSlow("theme.generate", func(p json.RawMessage) (any, error) { return generate(p, false) })
	srv.HandleSlow("theme.save", func(p json.RawMessage) (any, error) { return generate(p, true) })
	parseName := func(p json.RawMessage) (string, error) {
		var n struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(p, &n); err != nil || !themestudio.ValidSlug(n.Name) {
			return "", ipc.Errorf(ipc.CodeBadInput, "want {name}: a theme file name (a–z, 0–9, dashes)")
		}
		return n.Name, nil
	}
	srv.Handle("theme.delete", func(p json.RawMessage) (any, error) {
		name, err := parseName(p)
		if err != nil {
			return nil, err
		}
		if err := store.Delete(name); err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return true, nil
	})
	srv.HandleSlow("theme.apply", func(p json.RawMessage) (any, error) {
		name, err := parseName(p)
		if err != nil {
			return nil, err
		}
		colors, dark, err := store.Palette(name)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		mode := "light"
		if dark {
			mode = "dark"
		}
		_, s := wallpaperSettings()
		return wp.ApplyPalette(ctx, colors, mode, s)
	})
}
