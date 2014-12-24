function print(...)
	lazuli.broadcast("cast_console", ...)
end

print(_OSVERSION)
print("== mod_init.lua ==")
print("pid is", lazuli.get_pid())
print("uid is", lazuli.get_uid())
print("HELLO", "WORLD")
--[[ print("== event test ==")
lazuli.register_event("cast_console_input")
print("waiting for cast_console_input")
while true do
	lazuli.block_event()
	local event = lazuli.pop_event()
	print("entered:", event[2])
	if event[2] == "exit" then
		break
	end
end
lazuli.unregister_event("cast_console_input") ]]
print("== end of init ==")
-- lazuli.halt()
