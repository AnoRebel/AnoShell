-- Runs a Hyprland Lua config against a recording `hl` and prints its binds as
-- JSON (keybinds importer). Usage: lua - <hyprland.lua> < stub.lua
-- Every hl.* call is accepted; hl.bind calls are recorded with the action as
-- {__dsp = "dsp.window.move", __args = {...}}; functions as {__function = line}.
local cfg = arg[1]
-- The config only describes Hyprland; nothing it does may touch the system.
os.execute, os.remove, os.rename, os.exit, io.popen, io.open, io.write, io.output =
	nil, nil, nil, nil, nil, nil, nil, nil
local write = io.stdout
local root = cfg:match("^(.*)/[^/]*$") or "."
local binds, submap = {}, nil

local function rec(path)
	return setmetatable({}, {
		__index = function(_, k) return rec(path .. "." .. k) end,
		__call = function(_, ...) return { __dsp = path, __args = { ... } } end,
	})
end
hl = setmetatable({}, { __index = function(_, k) return rec(k) end })
hl.dsp = rec("dsp")
hl.bind = function(chord, action, opts)
	local at = debug.getinfo(2, "Sl")
	binds[#binds + 1] = { chord = chord, action = action, opts = opts, submap = submap,
		line = at.currentline, file = at.source:sub(2) }
end
hl.define_submap = function(name, fn)
	local prev = submap
	submap = name
	fn()
	submap = prev
end
hl.get_active_workspace = function() return nil end
hl.get_active_special_workspace = function() return nil end

-- require("Ano.custom.x") → <dir of the config>/custom/x.lua
table.insert(package.searchers, 2, function(name)
	local rel = name:gsub("^Ano%.", ""):gsub("%.", "/")
	local path = root .. "/" .. rel .. ".lua"
	local f = loadfile(path)
	if f then return f, path end
	return "\n\tno file " .. path
end)

dofile(cfg)

local function enc(v)
	local t = type(v)
	if t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			if c == "\n" then return "\\n" elseif c == "\t" then return "\\t" end
			if c == '"' or c == "\\" then return "\\" .. c end
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "number" then
		if v == math.floor(v) then return string.format("%d", v) end
		return tostring(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "function" then
		return '{"__function":' .. debug.getinfo(v, "S").linedefined .. "}"
	elseif t == "table" then
		local n = #v
		local isArr = n > 0 or next(v) == nil
		if isArr then
			for k in pairs(v) do if type(k) ~= "number" then isArr = false end end
		end
		local out = {}
		if isArr then
			for i = 1, n do out[#out + 1] = enc(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do out[#out + 1] = enc(k) .. ":" .. enc(v[k]) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
write:write(enc(binds))
