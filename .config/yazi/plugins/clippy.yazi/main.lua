local selected_or_hovered = ya.sync(function()
	-- yazi 26.x yields File objects here and tostring() on one prints an address
	-- ("File: 0x..."), so resolve .url first; older yazi yields the Url itself.
	-- (Helper lives inside ya.sync: sync blocks can't see outer locals.)
	local function to_path(v)
		local ok, url = pcall(function() return v.url end)
		if ok and url ~= nil then
			return tostring(url)
		end
		return tostring(v)
	end

	local tab, paths = cx.active, {}
	for _, u in pairs(cx.yanked) do
		table.insert(paths, to_path(u))
	end
	if #paths == 0 and tab.current.hovered then
		paths[1] = to_path(tab.current.hovered)
	end
	return paths
end)

return {
	entry = function()
		-- clippy is macOS-only (it puts file references on the system pasteboard).
		-- Off macOS this is a silent no-op, so the same `y` keymap works on every
		-- machine; the `yank` that runs just before this plugin has already happened.
		if ya.target_os and ya.target_os() ~= "macos" then
			return
		end

		local urls = selected_or_hovered()

		if #urls == 0 then
			return ya.notify({ title = "System Clipboard", content = "No file selected", level = "warn", timeout = 5 })
		end

		local cmd = Command("clippy")
		for _, url in ipairs(urls) do
			cmd = cmd:arg(url)
		end

		local child, spawn_err = cmd:stdout(Command.PIPED):stderr(Command.PIPED):spawn()
		if not child then
			-- On macOS a failed spawn means clippy is missing/broken: say so instead of crashing.
			return ya.notify({
				title = "Clipboard",
				content = string.format("Could not run clippy: %s", tostring(spawn_err)),
				level = "error",
				timeout = 5,
			})
		end
		local output, err = child:wait_with_output()

		if err == nil then
			ya.notify({
				title = "Clipboard: Copied " .. tostring(#urls) .. " file(s)",
				content = table.concat(urls, "\n"),
				level = "info",
				timeout = 5,
			})
		end

		if err ~= nil then
			ya.notify({
				title = "Clipboard",
				content = string.format("Could not copy selected file(s): %s", output and output.stderr or tostring(err)),
				level = "error",
				timeout = 5,
			})
		end
	end,
}
