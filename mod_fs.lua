print = lazuli.get_param()

local fs = {}
function fs.test(x)
	print("hello, world:", x)
	return 127
end
lazuli.proc_serve_loop(fs, true)
