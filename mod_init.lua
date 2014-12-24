function print(...)
	lazuli.broadcast("cast_console", ...)
end

print(_OSVERSION)
print("== mod_init.lua ==")
print("pid is", lazuli.get_pid())
print("uid is", lazuli.get_uid())
print("HELLO", "WORLD")
print("== event test ==")
lazuli.register_event("key_down")
print("waiting for key_down")
while true do
	lazuli.block_event()
	local event = lazuli.pop_event()
	print("got", event[1], event[2], event[3], event[4], event[5], event[6])
	if event[3] == 13 or event[3] == 10 then
		break
	end
end
lazuli.unregister_event("key_down")
print("== end of init ==")
lazuli.halt()
