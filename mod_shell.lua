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
help.fload = "fload <PATH> [PRIORITY]: load filesystem module"
function commands.fload(path, priority)
	if not path then
		print("file name expected")
	else
		local f = lazuli.proc_call(nil, "fopen", path)
		local buf = ""
		while true do
			local x = f.read(4096)
			if not x then break end
			buf = buf .. x
		end
		f.close()
		print("spawned as", lazuli.spawn(buf, name, tonumber(priority) or 0, lazuli.get_param()))
	end
end
help.fexec = "fexec <PATH> [PRIORITY]: load filesystem module and release console until exit"
function commands.fexec(path, priority)
	if not path then
		print("file name expected")
	else
		local f = lazuli.proc_call(nil, "fopen", path)
		local buf = ""
		while true do
			local x = f.read(4096)
			if not x then break end
			buf = buf .. x
		end
		f.close()
		lazuli.unregister_event("cast_console_input")
		pid = lazuli.spawn(buf, name, tonumber(priority) or 0, lazuli.get_param())
		print("spawned as", pid)
		lazuli.join(pid)
		print("joined", pid)
		lazuli.register_event("cast_console_input")
	end
end
help.fed = "fed <PATH>: edit the specified file"
function commands.fed(path)
	local lines
	local function fed_load(path)
		lines = {}
		local f = lazuli.proc_call(nil, "fopen", path)
		local buf = ""
		while true do
			local x = f.read(4096)
			if not x then break end
			buf = buf .. x
			while buf:find("\n") do
				local cut = buf:find("\n")
				table.insert(lines, buf:sub(1, cut - 1))
				buf = buf:sub(cut + 1)
			end
		end
		if #buf > 0 then
			table.insert(lines, buf)
		end
		f.close()
		print("loaded: " .. path .. ": " .. #lines .. " lines.")
	end
	local function fed_save(path)
		local f = lazuli.proc_call(nil, "fopen", path, "w")
		local buf = ""
		for i, line in ipairs(lines) do
			buf = buf .. line .. "\n"
			if #buf > 4096 then
				f.write(buf)
				buf = ""
			end
		end
		if #buf ~= 0 then
			f.write(buf)
		end
		f.close()
		print("saved: " .. path .. ": " .. #lines .. " lines.")
	end
	if path then
		fed_load(path)
	else
		lines = {}
		print("empty buffer")
	end
	local running = true
	local function fed_cmd(c, argfrom, argto, arg2)
		if c == "i" then
			if argfrom then
				for line = argfrom, argto do
					table.insert(lines, line, arg2)
				end
			else
				table.insert(lines, arg2)
			end
		elseif c == "e" then
			if argfrom then
				assert(argfrom >= 1 and argfrom <= #lines, "line out of bounds: " .. argfrom)
				assert(argto >= 1 and argto <= #lines, "line out of bounds: " .. argto)
				for line = argfrom, argto do
					lines[line] = arg2
				end
			else
				assert(#lines ~= 0, "empty file")
				lines[#lines] = arg2
			end
		elseif c == "p" then
			if argfrom then
				assert(argfrom >= 1 and argfrom <= #lines, "line out of bounds: " .. argfrom)
				assert(argto >= 1 and argto <= #lines, "line out of bounds: " .. argto)
				for line = argfrom, argto do
					print(line .. ": " .. lines[line])
				end
			else
				print("lines: " .. #lines)
				for i, v in ipairs(lines) do
					print(i .. ": " .. v)
				end
			end
		elseif c == "d" then
			assert(argfrom, "expected a line")
			assert(argfrom >= 1 and argfrom <= #lines, "line out of bounds: " .. argfrom)
			assert(argto >= 1 and argto <= #lines, "line out of bounds: " .. argto)
			for line = argto, argfrom, -1 do
				table.remove(lines, line)
			end
		elseif c == "w" then
			if #arg2 > 0 then
				fed_save(arg2)
			else
				assert(path, "expected a file")
				fed_save(path)
			end
		elseif c == "r" then
			if #arg2 > 0 then
				fed_load(arg2)
			else
				assert(path, "expected a file")
				fed_load(path)
			end
		elseif c == "q" then
			print("bye")
			running = false
		elseif c == "c" then
			print("line count: " .. #lines)
		elseif c == "h" then
			print("fed help: file editor")
			print("<CMD><ARG1> <ARG2>")
			print("ARG1 can be a line number or a range A-B")
			print("Commands:")
			print("i<L> <TEXT>: insert a line before line L (default: end)")
			print("e<L> <TEXT>: replace line L (default: end)")
			print("p<L>: print line L (default: all)")
			print("d<L>: delete line L (default: do nothing)")
			print("w <FILE>: write the buffer to FILE (default: command-line file)")
			print("r <FILE>: read the buffer from FILE (default: command-line file)")
			print("c: count the number of lines")
			print("q: quit fed")
			print("h: show this help")
		else
			print("unknown fed command (try 'h')")
		end
	end
	while running do
		lazuli.block_event()
		local event = lazuli.pop_event()
		if event[1] == "cast_console_input" and #event[2] > 0 then
			local cmd = event[2]
			print("fed> " .. cmd)
			local c = cmd:sub(1, 1)
			local spt = cmd:find(" ", 2)
			local arg1, arg2
			local valid = true
			if spt then
				arg1, arg2 = cmd:sub(2, spt - 1), cmd:sub(spt + 1)
			else
				arg1, arg2 = cmd:sub(2), ""
			end
			local argfrom, argto = tonumber(arg1), nil
			if not argfrom and arg1:find("-") then
				local spt = arg1:find("-")
				argfrom, argto = tonumber(arg1:sub(1, spt - 1)), tonumber(arg1:sub(spt + 1))
				if not argfrom or not argto or argto < argfrom then
					print("invalid range")
					valid = false
				end
			else
				argto = argfrom
			end
			if valid then
				local succ, err = pcall(fed_cmd, c, argfrom, argto, arg2)
				if not succ then
					print("failed: " .. err)
				end
			end
		end
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
	if event[1] == "cast_console_input" and #event[2] > 0 then
		print("> " .. event[2])
		local cmd = {}
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
