-- This code file contains some work derived from OpenOS code.
-- Such work was:
--     Copyright (c) 2013-2014 Florian "Sangar" N??cke
-- Under the MIT license.
-- Such code is marked as coming from OpenOS
-- The rest of the code here is also available under the same license.

local gpus = {}
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
	value = text_detab(tostring(value))
	if unicode.wlen(value) == 0 then
		return
	end
	for addr, gpu in pairs(gpus) do
		local w, h = gpu.getResolution()
		if not w then
			return
		end
		h = h - 1 -- input line not included
		local line, nl
		repeat
			local wrapAfter, margin = w - (gpu.cursorX - 1), w
			line, value, nl = text_wrap(value, wrapAfter, margin)
			gpu.set(gpu.cursorX, gpu.cursorY, line)
			gpu.cursorX = gpu.cursorX + unicode.wlen(line)
			if nl or (gpu.cursorX > w and wrap) then
				gpu.cursorX = 1
				gpu.cursorY = gpu.cursorY + 1
			end
			if gpu.cursorY > h then
				gpu.copy(1, 1, w, h, 0, -1)
				gpu.fill(1, h, w, 1, " ")
				gpu.cursorY = h
			end
		until not value
	end
end

local function is_empty(tab)
	for k, v in pairs(tab) do
		return false
	end
	return true
end

print = lazuli.get_param()

print("starting console handler...")
lazuli.register_event("cast_add_gpu")
lazuli.register_event("cast_rem_gpu")
lazuli.register_event("cast_console")
lazuli.register_event("cast_console_raw")
lazuli.register_event("key_down")
lazuli.register_event("key_up")

lazuli.broadcast("cast_resend_devices")

local input_string = ""

local function rerender_input()
	for addr, gpu in pairs(gpus) do
		local w, h = gpu.getResolution()
		if not w then
			return
		end
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
		local next_y = 1
		if is_empty(gpus) then
			next_y = print("switching debug to console")
			lazuli.register_event("debug_print")
		end
		gpus[ev[2].address] = ev[2]
		local w, h = ev[2].getResolution()
		if next_y == 1 then
			ev[2].fill(1, 1, w, h, " ")
		end
		ev[2].cursorX = 1
		ev[2].cursorY = next_y
		rerender_input()
	elseif ev[1] == "cast_rem_gpu" then
		gpus[ev[2].address] = nil
		if is_empty(gpus) then
			lazuli.unregister_event("debug_print")
		end
	end
end
