local initializers = {}
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
	elseif cmd ~= nil then
		warn("invalid bool_out command: " .. tostring(cmd))
	end
end
function publishers.bool_in(ref, cmd)
	if cmd == "query" then
		if ref.publish_value == nil then
			warn("no recorded value for", ref.publish_name)
		else
			lazuli.get_param()("[rtio report]", ref.publish_name, "=", ref.publish_value)
		end
	elseif cmd == "monitor" then
		ref.publish_report = true
	elseif cmd == nil then
		ref.publish_value = nil
		ref.publish_report = false
		ref.get(function(value)
			ref.publish_value = value
			if ref.publish_report then
				lazuli.get_param()("[rtio report]", ref.publish_name, "=", value)
			end
		end)
	else
		warn("invalid bool_in command: " .. tostring(cmd))
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
	local targets = {}
	local last_sent = nil
	function recheck(fside)
		if fside == side then
			if not card.component then
				warn("redstone event without a card?")
			else
				local cur = card.component.getOutput(side) > 0
				if cur ~= last_sent then
					last_sent = cur
					for _, target in ipairs(targets) do
						target(cur)
					end
				end
			end
		end
	end
	table.insert(card.cb, recheck)
	return put_handle("bool_out", {set=function(v)
		if card.component then
			if v then
				card.component.setOutput(side, 15)
			else
				card.component.setOutput(side, 0)
			end
			recheck(side)
		else
			warn("no component for " .. card.address)
		end
	end}), put_handle("bool_in", {get=function(target) -- target is a callback
		table.insert(targets, target)
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
				local cur = card.component.getInput(side) > 0
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
		assert(handle.publish_name == nil, "cannot publish twice: " .. name .. " and " .. tostring(handle.publish_name))
		handle.publish_name = name
		published[name] = handle
		publishers[type](handle)
	end
end
function conf_env.on_press(bool)
	bool = valid_handle("bool_in", bool)
	local targets = {}
	local last_value = true -- to prevent immediate triggering
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
function conf_env.filter(cond, event)
	cond = valid_handle("bool_in", cond)
	event = valid_handle(nil, event)
	assert(event.type == "event_in" or event.type == "event_out", "filter needs an event_in or an event_out")
	local active = nil
	cond.get(function(v)
		active = v
	end)
	if event.type == "event_in" then
		local targets = {}
		event.send(function()
			if active == nil then
				warn("filter checked before activity known")
			elseif active then
				for _, cb in ipairs(targets) do
					cb()
				end
			end
		end)
		return put_handle("event_in", {send=function(target) -- target is a callback
			table.insert(targets, target)
		end})
	else
		return put_handle("event_out", {event=function()
			if active == nil then
				warn("filter checked before activity known")
			elseif active then
				event.event()
			end
		end})
	end
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
function conf_env.set_from(out, inp)
	out = valid_handle("bool_out", out)
	inp = valid_handle("bool_in", inp)
	local value = nil
	inp.get(function(nval)
		value = nval
	end)
	return put_handle("event_out", {event=function()
		if value == nil then
			warn("set_from before value available")
		else
			out.set(value)
		end
	end})
end
function conf_env.let(out, inp)
	out = valid_handle("bool_out", out)
	inp = valid_handle("bool_in", inp)
	inp.get(out.set)
end
function conf_env.invert(chan)
	chan = valid_handle(nil, chan)
	if chan.type == "bool_out" then
		return put_handle("bool_out", {set=function(value)
			chan.set(not value)
		end})
	elseif chan.type == "bool_in" then
		return put_handle("bool_in", {get=function(cb)
			chan.get(function(value)
				cb(not value)
			end)
		end})
	else
		error("invalid type to invert: " .. chan.type)
	end
end
function conf_env.cell_bool(name, def)
	assert(type(name) == "string", "cell_bool needs a valid name")
	assert(def == true or def == false, "cell_bool needs a valid default")
	local targets = {}
	local value = nil
	table.insert(initializers, function()
		lazuli.event_wait("proc_nvget")
		value = lazuli.proc_call(nil, "nvget", name, def)
		for _, target in ipairs(targets) do
			target(value)
		end
	end)
	return put_handle("bool_out", {set=function(v)
		if v == value then return end
		value = v
		local succ, err = pcall(lazuli.proc_call, nil, "nvset", name, v)
		if not succ then
			warn("nvset failed: " .. tostring(err))
		end
		for _, target in ipairs(targets) do
			target(v)
		end
	end}), put_handle("bool_in", {get=function(target)
		table.insert(targets, target)
	end})
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

for _, init in ipairs(initializers) do
	init()
end

lazuli.get_param()("rtio module inited")

while true do
	lazuli.block_event()
	local event = lazuli.pop_event()
	if event[1] == "cast_rtio" then
		local found = event[2] and published[event[2]]
		if not found then
			warn("could not find published: " .. tostring(event[2]))
		elseif event[3] == nil then
			warn("nil command")
		else
			publishers[found.type](found, table.unpack(event, 3))
		end
	elseif event[1] == "cast_add_redstone" then
		local card = event[2]
		for _, redref in ipairs(handles_by_type["rs_card"]) do
			if redref.address == card.address then
				redref.component = card
				for _, cb in ipairs(redref.cb) do
					for side = 0, 5 do
						cb(side)
					end
				end
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
