print = lazuli.get_param()

-- implementation

local gpu = component.list("gpu")()
local cursorY = 1
function print(...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = tostring(args[i])
	end
	component.invoke(gpu, "set", 1, cursorY, table.concat(args, " ", 1, args.n))
	cursorY = cursorY + 1
end

print("== starting term ==")
lazuli.register_event("cast_term")
lazuli.register_event("key_down")
lazuli.register_event("key_up")
while true do
	lazuli.block_event()
	local ev = lazuli.pop_event()
	if ev[1] == "cast_term" then
		print(table.unpack(ev, 2, ev.n))
	elseif ev[1] == "key_down" then
		if ev[3] ~= 0 then
			print("press", string.char(ev[3]))
		end
	end
end
