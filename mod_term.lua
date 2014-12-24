print = lazuli.get_param()
print("== starting term ==")
lazuli.register_event("cast_term")
while true do
	lazuli.block_event()
	local ev = lazuli.pop_event()
	if ev[1] == "cast_term" then
		print(table.unpack(ev, 2, ev.n))
	end
end
