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
    for _, line in ipairs(lines) do
        file:write(line .. "\n")
    end
    file:close()
end

-- save table to file
local save_to_file = ya.sync(function(state,filename)
    local file = io.open(filename, "w+")
	for path, f in pairs(state.autofilter) do
		file:write(string.format("%s###%s",path,f.word), "\n")
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
		if autofilter == nil or #autofilter < 2 then
			goto nextline
		end
		state.autofilter[autofilter[1]] = {
			word = autofilter[2],
		}

		::nextline::
	end
    file:close()
end)



local save_autofilter = ya.sync(function(state,word)

	-- avoid add exists path
	for path, _ in pairs(state.autofilter) do
		if tostring(cx.active.current.cwd) == path then
			return 
		end
	end

	state.autofilter[tostring(cx.active.current.cwd)] = {
		word = tostring(word),
	}

	ya.notify {
		title = "autofilter",
		content = "autofilter:<"..word.."> saved",
		timeout = 2,
		level = "info",
	}
	ya.manager_emit("filter_do", { word, smart = true })
	state.force_fluse_header = true
	state.force_fluse_mime = true
	save_to_file(SERIALIZE_PATH)
end)

local delete_autofilter = ya.sync(function(state)
	local key = tostring(cx.active.current.cwd)
	ya.notify {
		title = "autofilter",
		content = "autofilter:<"..state.autofilter[key].word .."> deleted",
		timeout = 2,
		level = "info",
	}
	state.autofilter[key] = nil
	ya.manager_emit("filter_do", { "", smart = true })
	state.force_fluse_header = true
	state.force_fluse_mime = true
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
	ya.manager_emit("filter_do", { "", smart = true })
	state.force_fluse_header = true
	state.force_fluse_mime = true
	delete_lines_by_content(SERIALIZE_PATH,".*")
end)

return {
	setup = function(st,opts)
		load_file_to_state(SERIALIZE_PATH)
		local color = opts and opts.color and config.color or "#CE91A0"

		-- add a nil module to header to detect cwd change
		local function cwd_change_detect(self)
			local cwd = cx.active.current.cwd
			if st.cwd ~= cwd or st.force_fluse_header then
				st.force_fluse_header = false
				st.cwd = cwd
				if st.autofilter[tostring(cwd)] then
					st.is_auto_filter_cwd = true
					ya.manager_emit("filter_do", { st.autofilter[tostring(cwd)].word, smart = true })
					st.need_flush_mime = true
					st.url =  tostring(cx.active.current.hovered.url)
				else
					st.is_auto_filter_cwd = false
				end
			end
			return st.is_auto_filter_cwd and ui.Line { ui.Span(" [AF]"):fg(color):bold() } or ui.Line{}
		end

		Header:children_add(cwd_change_detect,8000,Header.LEFT)

		local function Status_mime(self)
			local window = cx.active.current.window
			local url = cx.active.current.hovered and tostring(cx.active.current.hovered.url) or ""
			if (st.need_flush_mime and url ~= st.url) or st.force_fluse_mime then
				local job = {}
				st.force_fluse_mime = false
				job.files = window
				require("mime-ext").fetch(job)
				st.need_flush_mime = false
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
				save_autofilter(value)
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
