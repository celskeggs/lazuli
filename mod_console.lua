-- This code file contains some work derived from OpenOS code.
-- Such work was:
--     Copyright (c) 2013-2014 Florian "Sangar" N??cke
-- Under the MIT license.
-- Such code is marked as coming from OpenOS
-- The rest of the code here is also available under the same license.

local function is_empty(tab)
	for k, v in pairs(tab) do
		return false
	end
	return true
end

local gpus, screens = {}, {}
function print_console(...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = tostring(args[i])
	end
	console_write(table.concat(args, "\t", 1, args.n) .. "\n")
end

function text_detab(value) -- From OpenOS
	tabWidth = 8
	local function rep(match)
		local spaces = tabWidth - match:len() % tabWidth
		return match .. string.rep(" ", spaces)
	end
	return value:gsub("([^\n]-)\t", rep) -- truncate results
end

function text_wrap(value, width, maxWidth) -- From OpenOS
	local line, nl = value:match("([^\r\n]*)(\r?\n?)") -- read until newline
	if unicode.wlen(line) > width then -- do we even need to wrap?
		local partial = unicode.wtrunc(line, width)
		local wrapped = partial:match("(.*[^a-zA-Z0-9._()'`=])")
		if wrapped or unicode.wlen(line) > maxWidth then
			partial = wrapped or partial
			return partial, unicode.sub(value, unicode.len(partial) + 1), true
		else
			return "", value, true -- write in new line.
		end
	end
	local start = unicode.len(line) + unicode.len(nl) + 1
	return line, start <= unicode.len(value) and unicode.sub(value, start) or nil, unicode.len(nl) > 0
end

function console_write(value) -- From OpenOS
	local base_value = text_detab(tostring(value))
	if unicode.wlen(base_value) == 0 then
		return
	end
	if not next(gpus) then return end -- no gpus
	local gpuiter_index, gpu
	for addr, screen in pairs(screens) do
		gpuiter_index, gpu = next(gpus, gpuiter_index)
		if gpuiter_index == nil then
			gpuiter_index, gpu = next(gpus, gpuiter_index)
			assert(gpuiter_index, "no gpus, somehow?")
		end
		if gpu.getScreen() ~= screen.address then
			assert(gpu.bind(screen.address))
		end
		local w, h = gpu.getResolution()
		if w then
			local value = base_value
			h = h - 1 -- input line not included
			local line, nl
			repeat
				local wrapAfter, margin = w - (screen.cursorX - 1), w
				line, value, nl = text_wrap(value, wrapAfter, margin)
				gpu.set(screen.cursorX, screen.cursorY, line)
				screen.cursorX = screen.cursorX + unicode.wlen(line)
				if nl or (screen.cursorX > w and wrap) then
					screen.cursorX = 1
					screen.cursorY = screen.cursorY + 1
				end
				if screen.cursorY > h then
					gpu.copy(1, 1, w, h, 0, -1)
					gpu.fill(1, h, w, 1, " ")
					screen.cursorY = h
				end
			until not value
		end
	end
end

print = lazuli.get_param()

local _, rootgpu, rootscreen = print("starting console handler...")

lazuli.register_event("cast_add_gpu")
lazuli.register_event("cast_rem_gpu")
lazuli.register_event("cast_add_screen")
lazuli.register_event("cast_rem_screen")
lazuli.register_event("cast_console")
lazuli.register_event("cast_console_raw")
lazuli.register_event("key_down")
lazuli.register_event("key_up")

lazuli.broadcast("cast_resend_devices")

local input_string = ""

local function rerender_input()
	if not next(gpus) then return end -- no gpus
	local gpuiter_index, gpu
	for addr, screen in pairs(screens) do
		gpuiter_index, gpu = next(gpus, gpuiter_index)
		if gpuiter_index == nil then
			gpuiter_index, gpu = next(gpus, gpuiter_index)
			assert(gpuiter_index, "no gpus, somehow?")
		end
		if gpu.getScreen() ~= screen.address then
			assert(gpu.bind(screen.address))
		end
		local w, h = gpu.getResolution()
		if w then
			if #input_string <= w - 2 then
				gpu.set(1, h, "> " .. input_string)
				if #input_string ~= w - 2 then
					gpu.fill(2 + #input_string + 1, h, w - 3 - #input_string, 1, " ")
				end
			else
				gpu.set(1, h, "> ..." .. input_string:sub(#input_string - w + 6))
			end
		end
	end
end

local need_clear = {}
local root_gpu_ready, root_screen_ready = false, false

while true do
	lazuli.block_event()
	local ev = lazuli.pop_event()
	if ev[1] == "cast_console" then
		print_console(table.unpack(ev, 2, ev.n))
	elseif ev[1] == "cast_console_raw" then
		console_write(tostring(ev[2]))
	elseif ev[1] == "debug_print" then
		print_console("[DEBUG]", table.unpack(ev, 2, ev.n))
	elseif ev[1] == "key_down" then
		if ev[3] ~= 0 then
			if ev[3] == 13 or ev[3] == 10 then
				if not lazuli.broadcast("cast_console_input", input_string) then
					print("unhandled:", input_string)
				end
				input_string = ""
			elseif ev[3] >= 32 and ev[3] <= 126 then
				input_string = input_string .. string.char(ev[3])
			elseif ev[3] == 8 then
				if #input_string ~= 0 then
					input_string = input_string:sub(1, #input_string - 1)
				end
			else
				print("unknown char:", ev[3])
			end
			rerender_input()
		end
	elseif ev[1] == "cast_add_gpu" then
		gpus[ev[2].address] = ev[2]
		if ev[2].address == rootgpu and not root_gpu_ready then
			root_gpu_ready = true
			if root_screen_ready then
				screens[rootscreen].cursorY = print("switching debug to console")
				lazuli.register_event("debug_print")
			end
		end
		for addr, _ in pairs(need_clear) do
			local scr = ev[2].getScreen()
			if scr ~= addr then
				ev[2].bind(addr)
			end
			local w, h = ev[2].getResolution()
			ev[2].fill(1, 1, w, h, " ")
			if scr and scr ~= addr then
				ev[2].bind(scr)
			end
		end
		need_clear = {}
		rerender_input()
	elseif ev[1] == "cast_rem_gpu" then
		gpus[ev[2].address] = nil
		if is_empty(gpus) then
			lazuli.unregister_event("debug_print")
		end
	elseif ev[1] == "cast_add_screen" then
		screens[ev[2].address] = ev[2]
		ev[2].cursorX = 1
		ev[2].cursorY = 1
		if ev[2].address == rootscreen then
			if not root_screen_ready then
				root_screen_ready = true
				if root_gpu_ready then
					ev[2].cursorY = print("switching debug to console")
					lazuli.register_event("debug_print")
				end
			end
		else
			local found = false
			for _, gpu in pairs(gpus) do
				local scr = gpu.getScreen()
				if scr ~= ev[2].address then
					gpu.bind(ev[2].address)
				end
				local w, h = gpu.getResolution()
				gpu.fill(1, 1, w, h, " ")
				if scr and scr ~= ev[2].address then
					gpu.bind(scr)
				end
				found = true
				break
			end
			if not found then
				need_clear[ev[2].address] = true
			end
		end
		rerender_input()
	elseif ev[1] == "cast_rem_screen" then
		screens[ev[2].address] = nil
	end
end
