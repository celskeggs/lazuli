print = lazuli.get_param()

local filesystems = {}
local short_cache = {}
local dyn_cache_list = {}

short_cache.boot = lazuli.boot_device()
short_cache.temp = lazuli.temp_device()

function raw_split(name)
	if name:sub(1, 1) ~= "/" then
		return nil, "file not found"
	end
	local sptat = name:find("/", 3)
	local drive, path
	if not sptat then
		drive, path = name:sub(1), "/"
	else
		drive, path = name:sub(2, sptat - 1), name:sub(sptat)
	end
	if short_cache[drive] then
		if not filesystems[short_cache[drive]] then
			return nil, "disk unavailable: " .. drive .. " => " .. short_cache[drive]
		end
		drive = short_cache[drive]
	elseif not filesystems[drive] and #drive >= 4 then
		for name, _ in pairs(filesystems) do
			if name:sub(1, #drive) == drive then
				short_cache[drive] = name
				drive = name
			end
		end
	end
	if not filesystems[drive] then
		return nil, "disk unavailable: " .. drive
	end
	return filesystems[drive], path
end

local fs = {}
function fs.test(x)
	print("hello, world:", x)
	return 127
end
function fs.fopen(name, mode)
	local fs, path = raw_split(name)
	if not fs then
		error("cannot open " .. name .. ": " .. path)
	end
	local handle, err = fs.open(path, mode)
	if not handle then
		error("cannot open " .. name .. ": " .. err)
	end
	local obj = {}
	function obj.seek(whence, offset)
		return fs.seek(handle, whence, offset)
	end
	function obj.write(str)
		return fs.write(handle, str)
	end
	function obj.read(count)
		return fs.read(handle, count)
	end
	function obj.close()
		fs.close(handle)
	end
	return obj
end
function fs.fmkdir(name)
	local fs, path = raw_split(name)
	if not fs then
		error("cannot make directory " .. name .. ": " .. path)
	end
	local succ, err = fs.makeDirectory(path)
	if not succ then
		error("cannot make directory " .. name .. ": " .. err)
	end
end
function fs.fexists(name)
	local fs, path = raw_split(name)
	if not fs then
		return false
	end
	return fs.exists(path)
end
function fs.fisdir(name)
	local fs, path = raw_split(name)
	if not fs then
		return false
	end
	return fs.isDirectory(path)
end
function fs.frename(from, to)
	local fs1, path1 = raw_split(from)
	local fs2, path2 = raw_split(to)
	if not fs1 then
		error("cannot rename " .. from .. ": " .. path1)
	end
	if not fs2 then
		error("cannot rename to " .. to .. ": " .. path2)
	end
	if fs1 == fs2 then
		local succ, err = fs1.rename(path1, path2)
		if not succ then
			error("cannot rename " .. from .. " to " .. to ": " .. err)
		end
	else
		local out, err2 = fs2.open(path2, "wb")
		if not out then
			error("cannot rename to " .. to .. ": " .. err2)
		end
		local in, err1 = fs1.open(path1, "rb")
		if not out then
			fs2.close(out)
			error("cannot rename " .. from .. ": " .. err1)
		end
		while true do
			local data, err = fs1.read(in, 4096)
			if not data then
				if err then
					fs2.close(out)
					fs1.close(in)
					error("cannot rename " .. from .. ": " .. err)
				else
					break
				end
			end
			local succ, err = fs2.write(out, data)
			if not succ then
				fs2.close(out)
				fs1.close(in)
				error("cannot rename to " .. to .. ": " .. err)
			end
		end
		fs2.close(out)
		fs1.close(in)
	end
end
function fs.flist(name)
	if name == "/" then
		local out = {}
		for addr, fs in pairs(filesystems) do
			table.insert(out, addr)
		end
		for addr, tgt in pairs(short_cache) do
			table.insert(out, addr)
		end
		return out
	else
		local fs, path = raw_split(name)
		if not fs then
			error("cannot list " .. name .. ": " .. path)
		end
		local list, err = fs.list(path)
		if not list then
			error("cannot list " .. name .. ": " .. err)
		end
		return list
	end
end
function fs.fremove(name)
	local fs, path = raw_split(name)
	if not fs then
		error("cannot list " .. name .. ": " .. path)
	end
	local succ, err = fs.remove(path)
	if not succ then
		error("cannot list " .. name .. ": " .. err)
	end
end

function default_handle(event)
	if event[1] == "cast_add_filesystem" then
		filesystems[event[2].address] = event[2]
		local label = event[2].getLabel()
		if label and not short_cache[label] then
			short_cache[label] = event[2].address
			dyn_cache_list[event[2].address] = label
		end
	elseif event[1] == "cast_rem_filesystem" then
		filesystems[event[2].address] = nil
		if dyn_cache_list[event[2].address] then
			short_cache[dyn_cache_list[event[2].address]] = nil
			dyn_cache_list[event[2].address] = nil
		end
	end
end
lazuli.register_event("cast_add_filesystem")
lazuli.register_event("cast_rem_filesystem")
lazuli.proc_serve_loop(fs, true, default_handle)
