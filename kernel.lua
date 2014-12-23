_LAZULI_VERSION = "0.1.0"
_OSVERSION = "Lazuli " .. _LAZULI_VERSION

-- The scheduler is the core.

local spark, schedule, next_scheduled, higher_scheduled, get_process

do -- Note that O() declarations ignore memory allocation.
	local active_priorities = {}
	local function get_highest_priority()
		return active_priorities[1]
	end
	local function activate_queue(priority) -- O(n)
		for i, v in ipairs(active_priorities) do
			if v <= priority then
				assert(v ~= priority, "activate_queue on active queue")
				table.insert(active_priority, i, priority)
			end
		end
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
	last_pid = 0
	function spark(main_function, priority, user_id, param)
		local routine = coroutine.create(main_function)
		local structure = {coroutine=routine, user_id=user_id, priority=priority, queued=false, param=param}
		last_pid = last_pid + 1
		structure.pid = last_pid
		processes[structure.pid] = structure
		schedule(structure.pid)
		return structure.pid
	end
	function schedule(pid)
		local proc = processes[pid]
		assert(proc, "schedule on nonexistent process")
		assert(not proc.queued, "schedule on scheduled process")
		insert_queue(proc.queue, proc)
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
end

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
	local function handle_yield_ret(co, is_process_yield, ...)
		if is_process_yield then
			coroutine.yield(true)
			return handle_yield_ret(co, coroutine.resume(co))
		else
			return ...
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
	for _, name in ipairs({"insert", "maxn", "remove", "sort"}) do
		env.table[name] = table[name]
	end
	env.math = {}
	for _, name in ipairs({"abs", "acos", "asin", "atan", "atan2", "ceil", "cos",
		            "cosh", "deg", "exp", "floor", "fmod", "frexp", "huge",
		            "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow",
					"rad", "random", "randomseed", "sin", "sinh", "sqrt", "tan", "tanh"}) do
		env.math[name] = math[name]
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

local active_process
local timeslice_ticks
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
function api.get_priority()
	return active_process.priority
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
function api.spawn(code, chunkname, priority, param)
	local env = generate_environment(api)
	return spark(load(code, chunkname, "s", env), priority, active_process.user_id, param)
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

-- scheduler loop
while true do
	active_process = next_scheduled()
	assert(active_process, "scheduler deadlock")
	timeslice_ticks = 10
	coroutine.resume(active_process.coroutine)
end
