package main

import (
	"encoding/json"
	"log"

	"ano/anod/internal/atelier"
	"ano/anod/internal/ipc"
)

// registerAtelier serves the Atelier (Settings → Atelier, `ano atelier`):
//
//	atelier.list       {type?}                     → {revision, items, catalog, catalogs, lastRice} (cache only)
//	atelier.refresh    {type?}                     → the same, after fetching every catalog
//	atelier.prepare    {type, id, catalog}         → {token, code, name, author, catalog, catalogName, version,
//	                                              findings, hosts, commands, capabilitiesChanged, modifiedFiles, update, keybinds?}
//	atelier.commit     {token}                     → {path}
//	atelier.cancel     {token}                     → true
//	atelier.remove     {type, id}                  → true
//	atelier.confirm    {type, id, path?}           → {confirmed} (the update loaded: drop the kept previous version)
//	atelier.rollback   {type, id, path?}           → {version} (it didn't: the previous version comes back)
//	atelier.riceApply  {id, layers}                → {snapshot, applied, created, skipped, wallpaper, keybinds, appliedAt}
//	atelier.riceUndo                               → {ok: true, kept: [config keys you changed since, left as you set them]}
//	atelier.riceExport {name}                      → {id, path}
//	atelier.wallhaven  {query, page?, purity?, sorting?} → {items, page, lastPage, hasKey, error?}
//	atelier.wallhavenInstall {id}                  → {path}
func registerAtelier(srv *ipc.Server, h *atelier.Store) {
	if err := h.Init(); err != nil {
		log.Printf("atelier: %v", err)
	}
	bad := func(err error) error { return ipc.Errorf(ipc.CodeBadInput, "%v", err) }
	type typeID struct {
		Type    string `json:"type"`
		ID      string `json:"id"`
		Catalog string `json:"catalog"`
	}
	srv.Handle("atelier.list", func(p json.RawMessage) (any, error) {
		var req typeID
		json.Unmarshal(p, &req)
		res, err := h.List(req.Type)
		if err != nil {
			return nil, bad(err)
		}
		return res, nil
	})
	srv.HandleSlow("atelier.refresh", func(p json.RawMessage) (any, error) {
		var req typeID
		json.Unmarshal(p, &req)
		res, err := h.Refresh(req.Type)
		if err != nil {
			return nil, bad(err)
		}
		return res, nil
	})
	srv.HandleSlow("atelier.prepare", func(p json.RawMessage) (any, error) {
		var req typeID
		if err := json.Unmarshal(p, &req); err != nil || req.Type == "" || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {type, id, catalog}")
		}
		res, err := h.Prepare(req.Type, req.ID, req.Catalog)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return res, nil
	})
	tokenOf := func(p json.RawMessage) (string, error) {
		var req struct {
			Token string `json:"token"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Token == "" {
			return "", ipc.Errorf(ipc.CodeBadInput, "want {token}")
		}
		return req.Token, nil
	}
	srv.HandleSlow("atelier.commit", func(p json.RawMessage) (any, error) {
		tok, err := tokenOf(p)
		if err != nil {
			return nil, err
		}
		path, err := h.Commit(tok)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return map[string]any{"path": path}, nil
	})
	srv.Handle("atelier.cancel", func(p json.RawMessage) (any, error) {
		tok, err := tokenOf(p)
		if err != nil {
			return nil, err
		}
		h.Cancel(tok)
		return true, nil
	})
	srv.HandleSlow("atelier.remove", func(p json.RawMessage) (any, error) {
		var req typeID
		if err := json.Unmarshal(p, &req); err != nil || req.Type == "" || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {type, id}")
		}
		if err := h.Remove(req.Type, req.ID); err != nil {
			return nil, bad(err)
		}
		return true, nil
	})
	type loaded struct {
		Type string `json:"type"`
		ID   string `json:"id"`
		Path string `json:"path"`
	}
	srv.HandleSlow("atelier.confirm", func(p json.RawMessage) (any, error) {
		var req loaded
		if err := json.Unmarshal(p, &req); err != nil || req.Type == "" || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {type, id, path?}")
		}
		ok, err := h.Confirm(req.Type, req.ID, req.Path)
		if err != nil {
			return nil, bad(err)
		}
		return map[string]any{"confirmed": ok}, nil
	})
	srv.HandleSlow("atelier.rollback", func(p json.RawMessage) (any, error) {
		var req loaded
		if err := json.Unmarshal(p, &req); err != nil || req.Type == "" || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {type, id, path?}")
		}
		v, err := h.Rollback(req.Type, req.ID, req.Path)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return map[string]any{"version": v}, nil
	})
	srv.HandleSlow("atelier.riceApply", func(p json.RawMessage) (any, error) {
		var req struct {
			ID     string   `json:"id"`
			Layers []string `json:"layers"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {id, layers}")
		}
		res, err := h.RiceApply(req.ID, req.Layers)
		if err != nil {
			return res, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return res, nil
	})
	srv.HandleSlow("atelier.riceUndo", func(json.RawMessage) (any, error) {
		kept, err := h.RiceUndo()
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return map[string]any{"ok": true, "kept": kept}, nil
	})
	srv.HandleSlow("atelier.wallhaven", func(p json.RawMessage) (any, error) {
		var q atelier.WallhavenQuery
		if len(p) > 0 {
			if err := json.Unmarshal(p, &q); err != nil {
				return nil, ipc.Errorf(ipc.CodeBadInput, "want {query, page?, purity?, sorting?}")
			}
		}
		return h.WallhavenSearch(q), nil
	})
	srv.HandleSlow("atelier.wallhavenInstall", func(p json.RawMessage) (any, error) {
		var req struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {id}")
		}
		path, err := h.WallhavenInstall(req.ID)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return map[string]any{"path": path}, nil
	})
	srv.HandleSlow("atelier.riceExport", func(p json.RawMessage) (any, error) {
		var req struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Name == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {name}")
		}
		id, path, err := h.RiceExport(req.Name)
		if err != nil {
			return nil, bad(err)
		}
		return map[string]any{"id": id, "path": path}, nil
	})
}
