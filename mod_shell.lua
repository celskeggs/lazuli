function print(...)
	lazuli.broadcast("cast_console", ...)
end

local commands, help = {}, {}
local running = true

help.exit = "exit [certain]: exit the shell if certain is specified"
function commands.exit(certain)
	if certain == "certain" then
		running = false
	else
		print("Are you sure you want to exit?")
		print("If so, type 'exit certain'")
		print("You may instead want to try 'halt'")
	end
end
help.halt = "halt: turn off the computer"
function commands.halt()
	print("Goodbye.")
	lazuli.halt()
end
help.reboot = "reboot: turn off and restart the computer"
function commands.reboot()
	print("Goodbye.")
	lazuli.halt(true)
end
help.echo = "echo <TEXT>: echo the text to the console"
function commands.echo(...)
	print(table.concat(table.pack(...), " "))
end
help.help = "help: show this information"
function commands.help()
	for k, v in pairs(help) do
		print(v)
	end
end
help.proc = "proc: list processes"
function commands.proc()
	print("PID", "PRI", "USER", "QUEUED", "SRC")
	for _, pid in ipairs(lazuli.list_processes()) do
		print(pid, lazuli.get_priority(pid), lazuli.get_uid(pid), lazuli.get_queued(pid), lazuli.get_source(pid))
	end
end
help.rload = "rload <FNAME> [PRIORITY]: load root disk module"
function commands.rload(name, priority)
	if not name then
		print("module name expected")
	else
		print("spawned as", lazuli.root_load(name, tonumber(priority) or 0))
	end
end
help.rexec = "rexec <FNAME> [PRIORITY]: load root disk module and release console until exit"
function commands.rexec(name, priority)
	if not name then
		print("module name expected")
	else
		lazuli.unregister_event("cast_console_input")
		pid = lazuli.root_load(name, tonumber(priority) or 0)
		print("spawned as", pid)
		lazuli.join(pid)
		print("joined", pid)
		lazuli.register_event("cast_console_input")
	end
end

lazuli.register_event("cast_console_input")
print("started shell")
while running do
	lazuli.block_event()
	local event = lazuli.pop_event()
	if event[1] == "cast_console_input" then
		local cmd = {}
		print("> " .. event[2])
		for word in string.gmatch(event[2], "[^ ]*") do
			if #word ~= 0 then
				table.insert(cmd, word)
			end
		end
		if commands[cmd[1]] then
			local success, err = pcall(commands[cmd[1]], table.unpack(cmd, 2))
			if not success then
				print("command failed:", err)
			end
		else
			print("Bad command:", cmd[1])
		end
	end
end
lazuli.unregister_event("cast_console_input")
print("ended shell")