-- This code file is derived from OpenOS code.
-- Such work was:
--     Copyright (c) 2013-2014 Florian "Sangar" N??cke
-- Under the MIT license.
-- The rest of the code here is also available under the same license.

function print(...)
	lazuli.broadcast("cast_console", ...)
end

lazuli.register_event("cast_console_input")

print("Lua 5.2.3 Copyright (C) 1994-2013 Lua.org, PUC-Rio")
print("Enter a statement and hit enter to evaluate it.")
print("Prefix an expression with '=' to show its value.")
print("Type 'exit' to exit the interpreter.")

while true do
	lazuli.block_event()
	local evt = lazuli.pop_event()
	if evt[1] == "cast_console_input" then
		local command = evt[2]
		print("lua> " .. command)
		if command == "exit" then
			break
		end
		local code, reason
		if command:sub(1, 1) == "=" then
			code, reason = load("return " .. command:sub(2), "=stdin", "t")
		else
			code, reason = load(command, "=stdin", "t")
		end

		if code then
			local result = table.pack(xpcall(code, debug.traceback))
			if not result[1] then
				print("[ERR]", tostring(result[2]))
			else
				for i = 2, result.n do
					-- result[i] = serialization_serialize(result[i], true)
					result[i] = tostring(result[i])
				end
				if result.n > 1 then
					print(table.concat(result, "\t", 2))
				end
			end
		else
			print("[ERR]", reason)
		end
	end
end
lazuli.unregister_event("cast_console_input")
