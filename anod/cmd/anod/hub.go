package main

import (
	"encoding/json"
	"log"

	"ano/anod/internal/hub"
	"ano/anod/internal/ipc"
)

// registerHub serves the Hub (Settings → Hub, `ano hub`):
//
//	hub.list       {type?}                     → {revision, items, catalog, catalogs} (cache only)
//	hub.refresh    {type?}                     → the same, after fetching every catalog
//	hub.prepare    {type, id, catalog}         → {token, code, name, author, catalog, catalogName, version,
//	                                              findings, hosts, commands, capabilitiesChanged, modifiedFiles, update}
//	hub.commit     {token}                     → {path}
//	hub.cancel     {token}                     → true
//	hub.remove     {type, id}                  → true
//	hub.riceApply  {id, layers}                → {snapshot, applied, created, skipped, wallpaper}
//	hub.riceUndo                               → true
//	hub.riceExport {name}                      → {id, path}
func registerHub(srv *ipc.Server, h *hub.Hub) {
	if err := h.Init(); err != nil {
		log.Printf("hub: %v", err)
	}
	bad := func(err error) error { return ipc.Errorf(ipc.CodeBadInput, "%v", err) }
	type typeID struct {
		Type    string `json:"type"`
		ID      string `json:"id"`
		Catalog string `json:"catalog"`
	}
	srv.Handle("hub.list", func(p json.RawMessage) (any, error) {
		var req typeID
		json.Unmarshal(p, &req)
		res, err := h.List(req.Type)
		if err != nil {
			return nil, bad(err)
		}
		return res, nil
	})
	srv.HandleSlow("hub.refresh", func(p json.RawMessage) (any, error) {
		var req typeID
		json.Unmarshal(p, &req)
		res, err := h.Refresh(req.Type)
		if err != nil {
			return nil, bad(err)
		}
		return res, nil
	})
	srv.HandleSlow("hub.prepare", func(p json.RawMessage) (any, error) {
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
	srv.HandleSlow("hub.commit", func(p json.RawMessage) (any, error) {
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
	srv.Handle("hub.cancel", func(p json.RawMessage) (any, error) {
		tok, err := tokenOf(p)
		if err != nil {
			return nil, err
		}
		h.Cancel(tok)
		return true, nil
	})
	srv.HandleSlow("hub.remove", func(p json.RawMessage) (any, error) {
		var req typeID
		if err := json.Unmarshal(p, &req); err != nil || req.Type == "" || req.ID == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {type, id}")
		}
		if err := h.Remove(req.Type, req.ID); err != nil {
			return nil, bad(err)
		}
		return true, nil
	})
	srv.HandleSlow("hub.riceApply", func(p json.RawMessage) (any, error) {
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
	srv.HandleSlow("hub.riceUndo", func(json.RawMessage) (any, error) {
		if err := h.RiceUndo(); err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return true, nil
	})
	srv.HandleSlow("hub.riceExport", func(p json.RawMessage) (any, error) {
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
