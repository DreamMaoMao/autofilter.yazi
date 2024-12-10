-- stylua: ignore
local SUPPORTED_KEYS = {
	"a","s","d","j","k","l","p", "b", "e", "t",  "o", "i", "n", "r", "h","c",
	"u", "m", "f", "g", "w", "v", "x", "z", "y", "q"
}

local LINUX_BASE_PATH = "/.config/yazi/plugins/autofilter.yazi/filtercache"
local WINDOWS_BASE_PATH = "\\yazi\\config\\plugins\\autofilter.yazi\\filtercache"

local SERIALIZE_PATH = ya.target_family() == "windows" and os.getenv("APPDATA") .. WINDOWS_BASE_PATH or os.getenv("HOME") .. LINUX_BASE_PATH

local function string_split(input,delimiter)

	local result = {}

	for match in (input..delimiter):gmatch("(.-)"..delimiter) do
	        table.insert(result, match)
	end
	return result
end

local function delete_lines_by_content(file_path, pattern)
    local lines = {}
    local file = io.open(file_path, "r")

    -- Read all lines and store those that do not match the pattern
    for line in file:lines() do
        if not line:find(pattern) then
            table.insert(lines, line)
        end
    end
    file:close()

    -- Write back the lines that don't match the pattern
    file = io.open(file_path, "w")
    for i, line in ipairs(lines) do
        file:write(line .. "\n")
    end
    file:close()
end

-- save table to file
local save_to_file = ya.sync(function(state,filename)
    local file = io.open(filename, "w+")
	for path, f in pairs(state.autofilter) do
		file:write(string.format("%s###%s###%s",f.on,path,f.word), "\n")
	end
    file:close()
end)

-- load from file to state
local load_file_to_state = ya.sync(function(state,filename)

	if state.autofilter == nil then 
		state.autofilter = {}
	else
		return
	end

    local file = io.open(filename, "r")
	if file == nil then 
		return
	end

	for line in file:lines() do
		line = line:gsub("[\r\n]", "")
		local autofilter = string_split(line,"###")
		if autofilter == nil or #autofilter < 3 then
			goto nextline
		end
		state.autofilter[autofilter[2]] = {
			on = autofilter[1],
			word = autofilter[3],
		}

		::nextline::
	end
    file:close()
end)



local save_autofilter = ya.sync(function(state,word,key)

	-- avoid add exists path
	for path, _ in pairs(state.autofilter) do
		if tostring(cx.active.current.cwd) == path then
			return 
		end
	end

	state.autofilter[tostring(cx.active.current.cwd)] = {
		on = key,
		word = tostring(word),
	}

	ya.notify {
		title = "autofilter",
		content = "autofilter:<"..word.."> saved",
		timeout = 2,
		level = "info",
	}
	state.url = ""
	ya.manager_emit("filter_do", { word, smart = true })
	state.need_flush_mime = true
	-- ya.render()
	save_to_file(SERIALIZE_PATH)
end)

local all_autofilter = ya.sync(function(state) return state.autofilter or {} end)

local delete_autofilter = ya.sync(function(state)
	local key = tostring(cx.active.current.cwd)
	ya.notify {
		title = "autofilter",
		content = "autofilter:<"..state.autofilter[key].word .."> deleted",
		timeout = 2,
		level = "info",
	}
	state.autofilter[key] = nil
	state.url = ""
	ya.manager_emit("filter_do", { "", smart = true })
	state.need_flush_mime = true
	-- ya.render()
  save_to_file(SERIALIZE_PATH)
end)

local delete_all_autofilter = ya.sync(function(state)
	ya.notify {
		title = "autofilter",
		content = "autofilter:all autofilter has been deleted",
		timeout = 2,
		level = "info",
	}
	state.autofilter = nil
	state.url = ""
	ya.manager_emit("filter_do", { "", smart = true })
	state.need_flush_mime = true
	-- ya.render()
	delete_lines_by_content(SERIALIZE_PATH,".*")
end)


local function keyset_notify(str)
	ya.notify {
		title = "keyset",
		content = str,
		timeout = 2,
		level = "info",
	}	
end

local auto_generate_key = ya.sync(function(state)
	-- if input_key is empty,auto find a key to bind from begin SUPPORTED_KEYS
	local find = false
	local auto_assign_key
	for i, key in ipairs(SUPPORTED_KEYS) do
		if find then
			break
		end

		for _, cand in pairs(state.autofilter) do
			if key == cand.on then
				goto continue				
			end
		end
		
		auto_assign_key = key
		find = true

		::continue::
	end	

	if find then
		return auto_assign_key
	else
		keyset_notify("assign fail,all key has been assign")
		return nil
	end
end)


local function get_bind_key()
	local generate_key = auto_generate_key()
	return generate_key
end

return {
	setup = function(st,opts)
		load_file_to_state(SERIALIZE_PATH)
		local color = opts and opts.color and config.color or "#CE91A0"

		-- add a nil module to header to detect cwd change
		local function cwd_change_detect(self)
			local cwd = cx.active.current.cwd
			if st.cwd ~= cwd then
				st.cwd = cwd
				if st.autofilter[tostring(cwd)] then
					st.is_auto_filter_cwd = true
					ya.manager_emit("filter_do", { st.autofilter[tostring(cwd)].word, smart = true })
					st.need_flush_mime = true
					st.url =  tostring(cx.active.current.hovered.url)
					ya.err("filter")
				else
					st.is_auto_filter_cwd = false
				end
			end
			return st.is_auto_filter_cwd and ui.Line { ui.Span(" [AH]"):fg(color):bold() } or ui.Line{}
		end

		Header:children_add(cwd_change_detect,8000,Header.LEFT)

		local function Status_mime(self)
			local window = cx.active.current.window
			local url = cx.active.current.hovered and tostring(cx.active.current.hovered.url) or ""
			if st.need_flush_mime and url ~= st.url then
				local job = {}
				job.files = window
				require("mime-ext"):fetch(job)
				st.need_flush_mime = false
				ya.err("mime")
			end
			if st.url ~= url then
				st.url = url
			end
			return ui.Line {}
		end
	
		Status:children_add(Status_mime,100000,Status.LEFT)
	end,

	entry = function(_,job)
		local args = job.args
		local action = args[1]
		if not action then
			return
		end

		if action == "save" then
			local value, event = ya.input({
				realtime = false,
				title = "set autofilter word:",
				position = { "top-center", y = 3, w = 40 },
			})
			if event == 1 then
				local key = get_bind_key()
				if key == nil then
					return
				end
				save_autofilter(value,key)
			end
			return
		end


		if action == "delete_all" then
			return delete_all_autofilter()
		end


		if action == "delete" then
			delete_autofilter()
			return
		end
	end,
}
