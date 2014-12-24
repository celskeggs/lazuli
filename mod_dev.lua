print = lazuli.get_param()

print("loading device manager...")

lazuli.register_event("component_added")
lazuli.register_event("component_removed")
lazuli.register_event("cast_resend_devices")

lazuli.device_enumerate()

local devices = {}

local unsent = {}

while true do
	lazuli.block_event()
	local ev = lazuli.pop_event()
	if ev[1] == "component_added" then
		devices[ev[2]] = lazuli.device_proxy(ev[2])
		if not lazuli.broadcast("cast_add_" .. ev[3], devices[ev[2]]) then
			table.insert(unsent, ev[2])
		end
	elseif ev[1] == "component_removed" then
		lazuli.broadcast("cast_rem_" .. ev[3], devices[ev[2]])
		devices[ev[2]] = nil
	elseif ev[1] == "cast_resend_devices" then
		local loc_unsent = unsent
		unsent = {}
		for _, v in ipairs(loc_unsent) do
			local dev = devices[v]
			if dev then
				if not lazuli.broadcast("cast_add_" .. dev.type, dev) then
					table.insert(unsent, v)
				end
			end
		end
	end
end
