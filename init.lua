_LAZULI_VERSION = "0.1.0"
_OSVERSION = "Lazuli " .. _LAZULI_VERSION

-- The scheduler is the core.

local spark, schedule, next_scheduled, higher_scheduled, get_process, dealloc_process, processes_exist, list_processes, process_wait

do -- Note that O() declarations ignore memory allocation.
	local active_priorities = {}
	local function get_highest_priority()
		return active_priorities[1]
	end
	local function activate_queue(priority) -- O(n)
		for i, v in ipairs(active_priorities) do
			if v <= priority then
				assert(v ~= priority, "activate_queue on active queue")
				table.insert(active_priorities, i, priority)
				return
			end
		end
		table.insert(active_priorities, priority)
	end
	local function deactivate_queue(priority) -- O(n)
		for i, v in ipairs(active_priorities) do
			if v == priority then
				table.remove(active_priorities, i)
				return
			end
		end
		error("deactivate_queue on deactive queue")
	end

	local queues = {}
	local function get_queue(priority) -- O(1)
		if not queues[priority] then
			queues[priority] = {}
		end
		return queues[priority]
	end
	local function insert_queue(priority, entry) -- O(n)
		local queue = get_queue(priority)
		if not queue[1] then
			activate_queue(priority)
		end
		table.insert(queue, entry)
	end
	local function pop_queue(priority)
		if not priority then return end
		local queue = get_queue(priority)
		-- TODO: Don't use an O(n) algorithm
		local out = table.remove(queue, 1)
		assert(out, "pop_queue on empty queue")
		if not queue[1] then
			deactivate_queue(priority)
		end
		return out
	end
	local function peek_queue(priority)
		if not priority then return end
		local queue = get_queue(priority)
		return queue[1]
	end
	local function pop_highest()
		return pop_queue(get_highest_priority())
	end
	local function peek_highest()
		return peek_queue(get_highest_priority())
	end

	local processes = {}
	local next_pid = 0
	function spark(main_function, source, priority, user_id, param)
		local routine = coroutine.create(main_function)
		local structure = {coroutine=routine, source=source, user_id=user_id, priority=priority, queued=false, param=param, event_queue={}, waiting={}, cputime=0}
		structure.pid = next_pid
		next_pid = next_pid + 1
		processes[structure.pid] = structure
		schedule(structure.pid)
		return structure.pid
	end
	function schedule(pid)
		assert(pid, "pid expected in schedule")
		local proc = processes[pid]
		assert(proc, "schedule on nonexistent process")
		if not proc.queued then
			insert_queue(proc.priority, proc)
			proc.queued = true
		end
	end
	function next_scheduled()
		local highest = pop_highest()
		if highest then
			highest.queued = false
		end
		return highest
	end
	-- Is there a higher-priority process than this priority?
	function higher_scheduled(priority)
		local highest = peek_highest()
		return highest and highest.priority > priority
	end
	function get_process(pid)
		return processes[pid]
	end
	function dealloc_process(proc)
		assert(not proc.queued, "cannot deallocate a queued process")
		for _, pid in ipairs(processes[proc.pid].waiting) do
			if processes[pid] then
				schedule(pid)
			end
		end
		processes[proc.pid] = nil
	end
	function processes_exist()
		for pid, proc in pairs(processes) do
			return true
		end
		return false
	end
	function list_processes()
		local out = {}
		for pid, proc in pairs(processes) do
			table.insert(out, pid)
		end
		table.sort(out)
		return out
	end
	function process_wait(listener, target)
		local proct = processes[target]
		assert(proct, "process_wait on nonexistent process")
		table.insert(proct.waiting, listener)
	end
end

-- event subsystem

local event_check, event_sleep, event_register, event_unregister, event_send, event_exists, event_subscribe, event_unsubscribe
do
	local event_registry = {}
	local subscribers = {}
	function event_subscribe(pid)
		table.insert(subscribers, pid)
	end
	function event_unsubscribe(pid)
		for k, v in ipairs(subscribers) do
			if v == pid then
				table.remove(subscribers, k)
				return
			end
		end
		error("pid not subscribed to event updates: " .. tostring(pid))
	end
	local function event_handle(evt)
		local target = event_registry[evt[1]]
		if target then
			local proc = get_process(target)
			if proc then
				table.insert(proc.event_queue, evt)
				schedule(target)
				return true
			else
				event_unregister(evt[1], target)
			end
		end
		return false
	end
	function event_sleep(timeout)
		local data = table.pack(computer.pullSignal(timeout))
		if data.n > 0 then
			event_handle(data)
		end
	end
	function event_check()
		event_sleep(0)
	end
	function event_exists(name)
		return not not event_registry[name]
	end
	function event_send(pid, source, name, ...)
		local data = table.pack(name, ...)
		data.spid = source
		if pid then
			local proc = get_process(pid)
			if proc then
				table.insert(proc.event_queue, data)
				schedule(pid)
				return true
			else
				return false
			end
		else
			return event_handle(data)
		end
	end
	function event_register(name, pid)
		if event_registry[name] ~= nil then
			assert(not get_process(event_registry[name]), "event already registered: " .. name .. " (to " .. pid .. ")")
		end
		event_registry[name] = pid
		for i, pid in ipairs(subscribers) do
			schedule(pid)
		end
	end
	function event_unregister(name, pid)
		assert(event_registry[name] == pid, "event not registered: " .. name)
		event_registry[name] = nil
		for i, pid in ipairs(subscribers) do
			schedule(pid)
		end
	end
end

-- debugging

do
	local gpu = component.list("gpu")()
	local screen = component.list("screen")()
	component.invoke(gpu, "bind", screen)
	local cursorY = 1
	local w, h = component.invoke(gpu, "getResolution")
	component.invoke(gpu, "fill", 1, 1, w, h, " ")
	function print(...)
		if event_send(nil, nil, "debug_print", ...) then
			return nil
		end
		local args = table.pack("[debug]", ...)
		for i = 1, args.n do
			args[i] = tostring(args[i])
		end
		component.invoke(gpu, "set", 1, cursorY, table.concat(args, " ", 1, args.n))
		cursorY = cursorY + 1
		return cursorY, gpu, screen
	end
end

-- timer subsystem

local timer_start, timer_check, timer_delete, timer_sleep
do
	local timers = {}
	function timer_start(time, pid)
		assert(timers[pid] == nil, "timer already started")
		timers[pid] = computer.uptime() + time
	end
	function timer_delete(pid)
		assert(timers[pid] ~= nil, "timer not started")
		timers[pid] = nil
	end
	function timer_check() -- TODO: make this faster
		local now = computer.uptime()
		local expired = {}
		local nextat
		for pid, when in pairs(timers) do
			if when <= now then
				table.insert(expired, pid)
			elseif nextat == nil or when < nextat then
				nextat = when
			end
		end
		for _, pid in ipairs(expired) do
			timers[pid] = nil
			schedule(pid)
		end
		return nextat
	end
	function timer_sleep()
		local nextat = timer_check()
		if nextat then
			event_sleep(nextat - computer.uptime())
		else
			event_sleep() -- forever
		end
	end
end

-- sandbox subsystem

local function generate_environment(api)
	local env = {}
	env._G = env
	env.load = function (chunk, chunkname, mode, nenv)
		assert(mode == nil or mode == "t" or mode == "bt", "load is only allowed for textual chunks")
		if not nenv then
			nenv = env
		end
		return load(chunk, chunkname, "t", nenv)
	end
	env.assert = assert
	env.error = error
	env.ipairs = ipairs
	env.next = next
	env.pairs = pairs
	env.pcall = pcall

	env.rawequal = rawequal
	env.rawget = rawget
	env.rawset = rawset
	
	env.select = select
	env.tonumber = tonumber
	env.tostring = tostring
	env.type = type
	env.unpack = unpack
	env.xpcall = xpcall
	env._VERSION = _VERSION
	env._OSVERSION = _OSVERSION
	env._LAZULI_VERSION = _LAZULI_VERSION
	env.coroutine = {}
	env.coroutine.create = coroutine.create
	-- first parameter in actual coroutine yield is if the yield is a process-yield
	local function handle_yield_ret(co, success, is_process_yield, ...)
		if success then
			if is_process_yield then
				coroutine.yield(true)
				return handle_yield_ret(co, coroutine.resume(co))
			else
				return ...
			end
		else
			error("coroutine failure: " .. is_process_yield) -- is_process_yield has the error in this case
		end
	end
	function env.coroutine.resume(co, ...)
		return handle_yield_ret(co, coroutine.resume(co, ...))
	end
	function env.coroutine.yield(...)
		api.check_process_yield()
		return coroutine.yield(false, ...)
	end
	env.coroutine.running = coroutine.running
	env.coroutine.status = coroutine.status
	local function handle_error_ret(pass, ...)
		if pass then
			return ...
		else
			local errm = ...
			error(errm)
		end
	end
	function env.coroutine.wrap(f)
		co = env.coroutine.create(f)
		return function(...)
			return handle_error_ret(env.coroutine.resume(co, ...))
		end
	end
	env.string = {}
	for _, name in ipairs({"byte", "char", "find", "format", "gmatch", "gsub", "len", "lower",
		                   "match", "rep", "reverse", "sub", "upper"}) do
		env.string[name] = string[name]
	end
	env.table = {}
	for _, name in ipairs({"insert", "remove", "sort", "concat", "pack", "unpack"}) do
		env.table[name] = table[name]
	end
	env.math = {}
	for _, name in ipairs({"abs", "acos", "asin", "atan", "atan2", "ceil", "cos",
		            "cosh", "deg", "exp", "floor", "fmod", "frexp", "huge",
		            "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow",
					"rad", "random", "randomseed", "sin", "sinh", "sqrt", "tan", "tanh"}) do
		env.math[name] = math[name]
	end
	env.bit32 = {}
	for _, name in ipairs({"arshift", "band", "bnot", "bor", "btest", "bxor", "extract",
		                   "replace", "lrotate", "lshift", "rrotate", "rshift"}) do
		env.bit32[name] = bit32[name]
	end
	env.unicode = {}
	for _, name in ipairs({"char", "charWidth", "isWide", "len", "lower", "reverse", "sub", "upper", "wlen", "wtrunc"}) do
		env.unicode[name] = unicode[name]
	end
	env.os = {}
	env.os.time = os.time
	env.os.difftime = os.difftime
	env.debug = {}
	env.debug.traceback = debug.traceback
	env.lazuli = {}
	for k, v in pairs(api) do
		env.lazuli[k] = v
	end
	return env
end

-- Lazuli API subsystem

local active_process
local timeslice_ticks
local shutdown_allowed, shutdown_reboot = false, false
local api = {}
-- api MUST ONLY BE A TABLE OF FUNCTIONS

function api.sleep(timeout)
	timer_start(timeout, active_process.pid)
	api.process_block()
end
function api.get_pid()
	return active_process.pid
end
function api.get_uid(pid)
	if pid then
		local proc = get_process(pid)
		assert(proc, "get_uid on nonexistent process: " .. pid)
		return proc.user_id
	else
		return active_process.user_id
	end
end
function api.get_priority(pid)
	if pid then
		local proc = get_process(pid)
		assert(proc, "get_priority on nonexistent process: " .. pid)
		return proc.priority
	else
		return active_process.priority
	end
end
function api.get_queued(pid)
	if pid then
		local proc = get_process(pid)
		assert(proc, "get_queued on nonexistent process: " .. pid)
		return proc.queued
	else
		return active_process.queued
	end
end
function api.get_source(pid)
	if pid then
		local proc = get_process(pid)
		assert(proc, "get_source on nonexistent process: " .. pid)
		return proc.source
	else
		return active_process.source
	end
end
function api.get_cputime(pid)
	if pid then
		local proc = get_process(pid)
		assert(proc, "get_cputime on nonexistent process: " .. pid)
		return proc.cputime
	else
		return active_process.cputime
	end
end
function api.get_param()
	return active_process.param
end
function api.register_event(name)
	event_register(name, active_process.pid)
end
function api.unregister_event(name)
	event_unregister(name, active_process.pid)
end
function api.broadcast(name, ...)
	assert(type(name) == "string" and name:sub(1, 5) == "cast_", "broadcast names must start with cast_")
	local success = event_send(nil, active_process.pid, name, ...)
	api.check_process_yield()
	return success
end
function api.send(pid, name, ...)
	assert(type(name) == "string" and name:sub(1, 4) == "msg_", "send names must start with msg_")
	local success = event_send(pid, active_process.pid, name, ...)
	api.check_process_yield()
	return success
end
function api.proc_call(pid, name, ...)
	name = "proc_" .. name
	local compound = {ready=false, error=nil, results=nil, arguments=table.pack(...), notify=active_process.pid}
	assert(event_send(pid, active_process.pid, name, compound), "procedure unavailable: " .. name)
	while not compound.ready do
		api.process_block()
	end
	if compound.error then
		error(compound.error)
	end
	return table.unpack(compound.results, 1, compound.results.n)
end
function api.proc_serve_global(name)
	api.register_event("proc_" .. name)
end
function api.proc_serve_handle(event, name, target)
	if event[1] == "proc_" .. name then
		local cpd = event[2]
		local results = table.pack(pcall(target, table.unpack(cpd.arguments, 1, cpd.arguments.n)))
		if results[1] then
			table.remove(results, 1)
			results.n = results.n - 1
			cpd.results = results
		else
			cpd.error = results[2]
		end
		cpd.ready = true
		schedule(cpd.notify)
		return true
	end
	return false
end
function api.proc_serve_loop(procs, is_global, default)
	if is_global then
		for name, _ in pairs(procs) do
			api.proc_serve_global(name)
		end
	end
	while true do
		api.block_event()
		local event = api.pop_event()
		local proc = procs[event[1]:sub(6)]
		if event[1]:sub(1, 5) == "proc_" and proc then
			assert(api.proc_serve_handle(event, event[1]:sub(6), proc))
		else
			default(event)
		end
	end
end
function api.event_wait(name, timeout)
	if not event_exists(name) then
		timer_start(timeout or 1000, active_process.pid)
		event_subscribe(active_process.pid)
		while not event_exists(name) do
			api.process_block()
		end
		event_unsubscribe(active_process.pid)
		timer_delete(active_process.pid)
		assert(event_exists(name), "event_wait timed out on " .. name)
	end
end
function api.pop_event()
	if active_process.event_queue[1] then
		return table.remove(active_process.event_queue, 1)
	end
end
function api.block_event()
	while not active_process.event_queue[1] do
		api.process_block()
	end
end
function api.set_uid(uid)
	assert(active_process.user_id == 0, "root access required")
	active_process.user_id = uid
end
function api.set_far_uid(pid, uid)
	assert(active_process.user_id == 0, "root access required")
	local proc = get_process(pid)
	assert(proc, "process does not exist")
	proc.user_id = uid
end
function spawn_outer(code, chunkname, priority, user_id, param)
	local env = generate_environment(api)
	local f, err = load(code, chunkname, "t", env)
	if f then
		return spark(f, chunkname, priority, user_id, param)
	else
		error("could not load chunk " .. chunkname .. ": " .. err)
	end
end
function api.spawn(code, chunkname, priority, param)
	return spawn_outer(code, chunkname, priority, active_process.user_id, param)
end
function api.wake(pid)
	schedule(pid)
end
function api.join(pid)
	process_wait(active_process.pid, pid)
	while get_process(pid) do
		api.process_block()
	end
end
-- Always yield.
function api.process_yield()
	schedule(api.get_pid())
	coroutine.yield(true)
end
-- Yield if enough time has been spent.
function api.check_process_yield()
	timer_check()
	if higher_scheduled(active_process.priority) or timeslice_ticks <= 0 then
		api.process_yield()
	else
		timeslice_ticks = timeslice_ticks - 1
	end
end
-- Blocking yield.
function api.process_block()
	coroutine.yield(true)
end
function api.halt(is_reboot)
	assert(active_process.user_id == 0, "must be root to halt")
	shutdown_allowed = true
	shutdown_reboot = is_reboot
end
function api.device_enumerate()
	assert(active_process.user_id == 0, "must be root to enumerate devices")
	for address, type in component.list() do
		computer.pushSignal("component_added", address, type)
	end
end
function api.device_proxy(address)
	assert(active_process.user_id == 0, "must be root to proxy devices")
	return component.proxy(address)
end
function api.list_processes()
	return list_processes()
end
local root_load
function api.root_load(fname, priority, as_data)
	assert(active_process.user_id == 0, "must be root to root_load")
	return root_load(fname, priority, as_data)
end
function api.boot_device()
	return computer.getBootAddress()
end
function api.temp_device()
	return computer.tmpAddress()
end

function root_load(fname, priority, as_data)
	print("Loading: " .. fname)
	local address = computer.getBootAddress()
	assert(address, "expected a boot address")
	local handle, err = component.invoke(address, "open", fname)
	if not handle then
		error("can't open " .. fname .. ": " .. err)
	end
	local buffer = ""
	while true do
		local data, err = component.invoke(address, "read", handle, math.huge)
		if data then
			buffer = buffer .. data
		elseif err then
			error("can't read " .. fname .. ": " .. err)
		else
			break
		end
	end
	component.invoke(address, "close", handle)
	if as_data then
		return buffer
	else
		return spawn_outer(buffer, fname, priority, 0, print)
	end
end

local priority = 0
for mod in string.gmatch(root_load("/mods.conf", nil, true), "%S+") do
	if mod:sub(1, 1) == "=" then
		priority = tonumber(mod:sub(2))
	else
		root_load("/mod_" .. mod .. ".lua", priority)
	end
end

-- scheduler loop
while processes_exist() and not shutdown_allowed do
	timer_check()
	event_check()

	active_process = next_scheduled()
	if not active_process then
		timer_sleep()
	else
		timeslice_ticks = 10
		shutdown_allowed = false
		local start = os.clock()
		local success, err = coroutine.resume(active_process.coroutine)
		local endt = os.clock()
		active_process.cputime = active_process.cputime + endt - start
		if not success then
			-- TODO: proper error handling
			print("process " .. active_process.pid .. " crashed:", err)
		end
		if coroutine.status(active_process.coroutine) == "dead" and not active_process.queued then
			dealloc_process(active_process)
		end
	end
end
if shutdown_allowed then
	print("system halted")
	computer.shutdown(shutdown_reboot)
else
	error("all processes killed - crashed")
end
