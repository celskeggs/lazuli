local handles_by_type = {}
local handles = {}
local next_handle = 1

function put_handle(type, env)
	env = env or {}
	env.type = type
	env.handle = next_handle
	next_handle = next_handle + 1
	handles[env.handle] = env

	if not handles_by_type[type] then handles_by_type[type] = {} end
	table.insert(handles_by_type[type], env)

	return env.handle
end
function valid_handle(type, handle)
	assert(handle and handles[handle], "invalid handle")
	assert(not type or handles[handle].type == type, "invalid handle type: " .. handles[handle].type .. " instead of " .. tostring(type))
	return handles[handle], handles[handle].type
end
function valid_dir(x)
	assert(x and x >= 0 and x <= 5 and x % 1 == 0, "invalid direction")
end
function warn(x)
	lazuli.get_param()("[rtio warning]", x)
end

local publishers = {}
local published = {}
function publishers.bool_out(ref, cmd)
	if cmd == "on" or cmd == "true" or cmd == "yes" then
		ref.set(true)
	elseif cmd == "off" or cmd == "false" or cmd == "no" then
		ref.set(false)
	else
		warn("invalid bool_out command: " .. tostring(cmd))
	end
end

local conf_env = {}
conf_env.down = 0
conf_env.up = 1
conf_env.north = 2
conf_env.south = 3
conf_env.west = 4
conf_env.east = 5
function conf_env.redstone_card(addr)
	assert(addr)
	return put_handle("rs_card", {address=addr, cb={}, component=nil})
end
function conf_env.vanilla_out(card, side)
	card = valid_handle("rs_card", card)
	valid_dir(side)
	return put_handle("bool_out", {set=function(v)
		if card.component then
			if v then
				card.component.setOutput(side, 15)
			else
				card.component.setOutput(side, 0)
			end
		else
			warn("no component for " .. card.address)
		end
	end})
end
function conf_env.vanilla_in(card, side)
	card = valid_handle("rs_card", card)
	valid_dir(side)
	local targets = {}
	local last_sent = nil
	table.insert(card.cb, function(fside)
		if fside == side then
			if not card.component then
				warn("redstone event without a card?")
			else
				local cur = card.component.getInput(side)
				if cur ~= last_sent then
					last_sent = cur
					for _, target in ipairs(targets) do
						target(cur)
					end
				end
			end
		end
	end)
	return put_handle("bool_in", {get=function(target) -- target is a callback
		table.insert(targets, target)
	end})
end
function conf_env.console_pub(...)
	for _, name in ipairs({...}) do
		local target = name and conf_env[name]
		assert(target, "invalid publish: " .. tostring(name))
		local handle, type = valid_handle(nil, target)
		assert(publishers[type], "cannot publish type: " .. tostring(type))
		published[name] = handle
	end
end
function conf_env.on_press(bool)
	bool = valid_handle("bool_in", bool)
	local targets = {}
	local last_value = nil
	bool.get(function(v)
		if v ~= last_value then
			last_value = v
			if v then
				for _, target in ipairs(targets) do
					target()
				end
			end
		end
	end)
	return put_handle("event_in", {send=function(target) -- target is a callback
		table.insert(targets, target)
	end})
end
function conf_env.when(inp, out)
	inp = valid_handle("event_in", inp)
	out = valid_handle("event_out", out)
	inp.send(function()
		out.event()
	end)
end
function conf_env.set(out, value)
	if type(value) == "boolean" then
		out = valid_handle("bool_out", out)
		return put_handle("event_out", {event=function()
			out.set(value)
		end})
	else
		error("invalid type to set: " .. type(value))
	end
end

local f, err = load(lazuli.root_load("rtio.conf", nil, true), "/rtio.conf", "t", conf_env)
if not f then
	error(err)
end
f()

lazuli.register_event("cast_rtio")
lazuli.register_event("cast_add_redstone")
lazuli.register_event("cast_rem_redstone")
lazuli.register_event("redstone_changed")

lazuli.broadcast("cast_resend_devices")

lazuli.get_param()("rtio module inited")

while true do
	lazuli.block_event()
	local event = lazuli.pop_event()
	if event[1] == "cast_rtio" then
		local found = event[2] and published[event[2]]
		if not found then
			warn("could not find published: " .. tostring(event[2]))
		else
			publishers[found.type](found, table.unpack(event, 3))
		end
	elseif event[1] == "cast_add_redstone" then
		local card = event[2]
		for _, redref in ipairs(handles_by_type["rs_card"]) do
			if redref.address == card.address then
				redref.component = card
			end
		end
	elseif event[1] == "cast_rem_redstone" then
		local card = event[2]
		for _, redref in ipairs(handles_by_type["rs_card"]) do
			if redref.address == card.address then
				redref.component = nil
			end
		end
	elseif event[1] == "redstone_changed" then
		local card_addr, side = event[2], event[3]
		for _, redref in ipairs(handles_by_type["rs_card"]) do
			if redref.address == card_addr then
				for _, cb in ipairs(redref.cb) do
					cb(side)
				end
			end
		end
	end
end
