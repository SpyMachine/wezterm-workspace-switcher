local wezterm = require("wezterm")

local layouts = {}

local M = {}

local config = {
	layouts_location = wezterm.config_dir .. "/layouts",
	workspace_selector_key = {
		key = "o",
		mods = "CMD",
	},
	previous_workspace_key = {
		key = "b",
		mods = "LEADER",
	},
	recent_workspace_status = {
		enabled = false,
		mods = "LEADER",
	},
}

local function table_contains(table, value)
	for i = 1, #table do
		if table[i] == value then
			return true
		end
	end
	return false
end

M.apply_to_config = function(config_builder, opts)
	if opts then
		config.layouts_location = opts.layouts_location or config.layouts_location
		config.workspace_selector_key = opts.workspace_selector_key or config.workspace_selector_key
		config.previous_workspace_key = opts.previous_workspace_key or config.previous_workspace_key
		config.workspaces = opts.workspaces
		config.update_status = opts.update_status or config.update_status

		if opts.recent_workspace_status then
			config.recent_workspace_status.enabled = opts.recent_workspace_status.enabled
				or config.recent_workspace_status.enabled
			config.recent_workspace_status.mods = opts.recent_workspace_status.mods
				or config.recent_workspace_status.mods
		end
	end

	for f in io.popen("ls " .. config.layouts_location):lines() do
		local name = string.gsub(f, ".lua", "")
		layouts[name] = require("layouts." .. name)
	end

	table.insert(config_builder.keys, {
		key = config.workspace_selector_key.key,
		mods = config.workspace_selector_key.mods,
		action = wezterm.action_callback(function(window, pane)
			M.activate_workspace_selector(window, pane)
		end),
	})

	table.insert(config_builder.keys, {
		key = config.previous_workspace_key.key,
		mods = config.previous_workspace_key.mods,
		action = wezterm.action_callback(function(window, pane)
			M.switch_to_recent_workspace(window, pane, 2)
		end),
	})

	if config.recent_workspace_status.enabled then
		for i = 1, 8 do
			table.insert(config_builder.keys, {
				key = tostring(i),
				mods = "LEADER",
				action = wezterm.action_callback(function(window, pane)
					M.switch_to_recent_workspace(window, pane, i + 1)
				end),
			})
		end

		wezterm.on("update-right-status", function(window, _)
			local workspace_selector = {}
			for index, workspace in ipairs(M.recent_workspaces) do
				if index == 1 then
					table.insert(workspace_selector, { Foreground = { Color = "#7AA89F" } })
					table.insert(workspace_selector, { Text = "Active: " .. workspace })
					table.insert(workspace_selector, "ResetAttributes")
				else
					table.insert(workspace_selector, { Text = "  |  " })
					table.insert(workspace_selector, { Text = tostring(index - 1) .. ": " .. workspace })
				end
			end

			table.insert(workspace_selector, { Text = "   " })

			window:set_right_status(wezterm.format(workspace_selector))
		end)
	end
end

M.recent_workspaces = {}

M.activate_workspace_selector = function(window, pane)
	window:perform_action(
		wezterm.action.InputSelector({
			action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
				if not id and not label then
					wezterm.log_info("cancelled")
				else
					M.switch_workspace(inner_window, inner_pane, label, id)
				end
			end),
			title = "Choose Workspace",
			choices = config.workspaces,
			fuzzy = true,
			fuzzy_description = "Select Workspace: ",
		}),
		pane
	)
end

M.switch_workspace = function(window, pane, workspace, working_directory)
	local previous_workspaces = wezterm.mux.get_workspace_names()

	window:perform_action(
		wezterm.action.SwitchToWorkspace({
			name = workspace,
			spawn = {
				label = "Workspace: " .. workspace,
				cwd = working_directory,
			},
		}),
		pane
	)

	for i, v in ipairs(M.recent_workspaces) do
		if v == workspace then
			table.remove(M.recent_workspaces, i)
		end
	end

	table.insert(M.recent_workspaces, 1, workspace)

	if #M.recent_workspaces > 5 then
		table.remove(M.recent_workspaces)
	end

	if not table_contains(previous_workspaces, workspace) then
		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == workspace then
				M.initialize_workspace(workspace, mux_win)
			end
		end
	end
end

M.initialize_workspace = function(workspace, window)
	if layouts[workspace] ~= nil then
		layouts[workspace](window)
	else
		layouts["default"](window)
	end
end

M.switch_to_recent_workspace = function(window, pane, index)
	local workspace = M.recent_workspaces[index]
	M.switch_workspace(window, pane, workspace)
end

return M
