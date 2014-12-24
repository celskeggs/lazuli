function print(...)
	lazuli.broadcast("cast_console", ...)
end
function write(x)
	lazuli.broadcast("cast_console_raw", x)
end

function path_join(a, b)
	if a:sub(#a) == "/" then
		if b:sub(1,1) == "/" then
			return a .. b:sub(2)
		else
			return a .. b
		end
	elseif b:sub(1,1) == "/" then
		return a .. b
	else
		return a .. "/" .. b
	end
end

local commands, help, help_list = {}, {}, {}
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
	for k, v in ipairs(help_list) do
		print(v)
	end
end
help.proc = "proc: list processes"
function commands.proc()
	print("PID", "PRI", "USER", "QUEUED", "CPU", "SRC")
	for _, pid in ipairs(lazuli.list_processes()) do
		local time = lazuli.get_cputime(pid)
		time = math.ceil(time * 1000)
		print(pid, lazuli.get_priority(pid), lazuli.get_uid(pid), lazuli.get_queued(pid), time, lazuli.get_source(pid))
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
help.flist = "flist <PATH>: list the specified directory"
function commands.flist(path)
	if not path then
		print("file path expected")
	else
		local listed = lazuli.proc_call(nil, "flist", path)
		table.sort(listed)
		print("Found", #listed, "files.")
		for i, v in ipairs(listed) do
			if lazuli.proc_call(nil, "fisdir", path_join(path, v)) then
				print(i, v .. "/")
			else
				print(i, v)
			end
		end
	end
end
help.fdel = "fdel <PATH>: delete the specified file"
function commands.fdel(path)
	if not path then
		print("file path expected")
	else
		lazuli.proc_call(nil, "fremove", path)
	end
end
help.frename = "frename <FROM> <TO>: rename the specified file"
function commands.frename(from, to)
	if not from or not to then
		print("file paths expected")
	else
		lazuli.proc_call(nil, "frename", from, to)
	end
end
help.fstat = "fstat <PATH>: provide status info on the file"
function commands.fstat(path)
	if not path then
		print("file path expected")
	elseif not lazuli.proc_call(nil, "fexists", path) then
		print(path .. ": file does not exist")
	elseif lazuli.proc_call(nil, "fisdir", path) then
		print(path .. ": directory")
	else
		print(path .. ": normal file")
	end
end
help.fmkdir = "fmkdir <PATH>: make the specified directory"
function commands.fmkdir(path)
	if not path then
		print("file path expected")
	else
		lazuli.proc_call(nil, "fmkdir", path)
	end
end
help.fdump = "fdump <PATH>: dump the file to the console"
function commands.fdump(path)
	if not path then
		print("file path expected")
	else
		local f = lazuli.proc_call(nil, "fopen", path)
		while true do
			local x = f.read(4096)
			if not x then break end
			write(x)
		end
		f.close()
	end
end

for _, v in pairs(help) do
	table.insert(help_list, v)
end
table.sort(help_list)

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
