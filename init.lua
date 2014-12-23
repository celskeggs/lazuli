_LAZULI_VERSION = "0.1.0"
_OSVERSION = "Lazuli " .. _LAZULI_VERSION

-- The scheduler is the core.

local spark, schedule, next_scheduled, higher_scheduled, get_process, dealloc_process

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
	function spark(main_function, priority, user_id, param)
		local routine = coroutine.create(main_function)
		local structure = {coroutine=routine, user_id=user_id, priority=priority, queued=false, param=param, event_queue={}}
		structure.pid = next_pid
		next_pid = next_pid + 1
		processes[structure.pid] = structure
		schedule(structure.pid)
		return structure.pid
	end
	function schedule(pid)
		local proc = processes[pid]
		assert(proc, "schedule on nonexistent process")
		assert(not proc.queued, "schedule on scheduled process")
		insert_queue(proc.priority, proc)
		proc.queued = true
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
		processes[proc.pid] = nil
	end
end

-- Timer and event subsystems

local event_check, event_sleep, event_register, event_unregister
do
	local event_registry = {}
	function event_sleep(timeout)
		local data = table.pack(computer.pullSignal(timeout))
		if data.n > 0 then
			local target = event_registry[data[1]]
			if target then
				table.insert(get_process(target).event_queue, data)
				schedule(target)
			end
		end
	end
	function event_check()
		event_sleep(0)
	end
	function event_register(name, pid)
		assert(event_registry[name] == nil, "event already registered: " .. name)
		event_registry[name] = pid
	end
	function event_unregister(name, pid)
		assert(event_registry[name] == pid, "event not registered: " .. name)
		event_registry[name] = nil
	end
end

local timer_start, timer_check, timer_delete, timer_sleep
do
	local timers = {}
	function timer_start(time, pid)
		timers[pid] = computer.uptime() + time
	end
	function timer_delete(pid)
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
		event_sleep(nextat - computer.uptime())
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
	env.print = print -- TODO: examine
	-- Note: these three are dubious.
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
	env.os = {}
	env.os.time = os.time
	env.os.difftime = os.difftime
	env.lazuli = {}
	for k, v in pairs(api) do
		env.lazuli[k] = v
	end
	return env
end

-- Lazuli API subsystem

local active_process
local timeslice_ticks
local shutdown_allowed = false
local api = {}
-- api MUST ONLY BE A TABLE OF FUNCTIONS

function api.get_pid()
	return active_process.pid
end
function api.get_uid()
	return active_process.user_id
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
function api.get_priority()
	return active_process.priority
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
		return spark(f, priority, user_id, param)
	else
		error("could not load chunk " .. chunkname .. ": " .. err)
	end
end
function api.spawn(code, chunkname, priority, param)
	return spawn_outer(code, chunkname, priority, active_process.user_id, param)
end
function api.schedule(pid)
	schedule(pid)
end
-- Always yield.
function api.process_yield()
	api.schedule(api.get_pid())
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
function api.halt()
	assert(active_process.user_id == 0, "must be root to halt")
	shutdown_allowed = true
end

spawn_outer([[
	print("== init script ==")
	print("test", lazuli.get_pid)
	print("pid is", lazuli.get_pid())
	print("uid is", lazuli.get_uid())
	print(lazuli.get_param())
	print("== event test ==")
	lazuli.register_event("key_down")
	print("waiting for key_down")
	lazuli.block_event()
	local event = lazuli.pop_event()
	print("got", event[1], event[2], event[3], event[4], event[5], event[6])
	lazuli.unregister_event("key_down")
	print("== end of init ==")
	lazuli.halt()
]], "init", 0, 0, "HELLO WORLD")

-- scheduler loop
while get_process(0) do
	timer_check()
	event_check()

	active_process = next_scheduled()
	if not active_process then
		timer_sleep()
	else
		timeslice_ticks = 10
		shutdown_allowed = false
		local success, err = coroutine.resume(active_process.coroutine)
		if not success then
			-- TODO: proper error handling
			print("process", active_process.pid, "crashed:", err)
		end
		if coroutine.status(active_process.coroutine) == "dead" then
			dealloc_process(active_process)
		end
	end
end
if shutdown_allowed then
	print("system halted")
else
	error("process 0 killed - crashed")
end
