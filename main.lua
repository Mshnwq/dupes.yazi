--- Dupes Plugin: Dynamic jdupes runner for Yazi file manager
--- @since 25.5.31
--- @description Finds and manages duplicate files using jdupes

local M = {}

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

--- Thread-safe state setter
--- @param state table The global state object
--- @param key string State key to set
--- @param value any Value to store
local set_state = ya.sync(function(state, key, value) state[key] = value end)

--- Thread-safe state getter
--- @param state table The global state object
--- @param key string State key to retrieve
--- @return any The stored value
local get_state = ya.sync(function(state, key) return state[key] end)

--- Get current working directory from Yazi context
--- @return string Current working directory path
local get_cwd = ya.sync(function() return cx.active.current.cwd end)

-- ============================================================================
-- DISPLAY FUNCTIONS
-- ============================================================================

--- Display duplicate files in Yazi's file list
--- @param _cwd string Current working directory
--- @param data table Parsed JSON data from jdupes output
--- @param style boolean If true, shows dry-run preview with deletion markers
local function display_dupes(_cwd, data, style)
	-- Validate input data structure
	if not data or not data.matchSets then
		ya.dbg("Invalid or missing matchSets in JSON data")
		ya.notify {
			title = "Dupes Plugin",
			content = "Invalid JSON data: no matchSets",
			level = "error",
			timeout = 5,
		}
		return
	end

	ya.dbg(string.format("Entering display_dupes, cwd: %s", _cwd))

	-- Create unique ID for this file operation
	local id = ya.id("ft")

	-- Set search context title based on mode
	local cwd
	if style then
		cwd = _cwd:into_search("Duplicate files Dry Run Preview 'X means will be deleted'")
	else
		cwd = _cwd:into_search("Duplicate files")
	end

	-- Navigate to the search view
	ya.emit("cd", { Url(cwd) })

	-- Initialize empty file list
	ya.emit("update_files", {
		op = fs.op("part", { id = id, url = Url(cwd), files = {} }),
	})

	-- Build file list from duplicate sets
	local files = {}
	for i, matchSet in ipairs(data.matchSets) do
		local dupe_set = string.format("dup-set-%02d", i)
		ya.dbg(string.format("Processing group: %s", dupe_set))

		-- Process each file in the duplicate set
		for j, fileObj in ipairs(matchSet.fileList) do
			local url = Url(cwd):join(fileObj.filePath)
			local cha = fs.cha(url, true)

			local file
			if style then
				-- In dry-run mode, mark files for deletion (except first one)
				if j == 1 then
					-- First file in set: keep it (normal display)
					file = File { url = url, cha = cha }
				else
					-- Subsequent files: mark as dummy (will be deleted)
					local dcha = Cha {
						kind = 16,
						is_dummy = true,
						len = cha.len,
						gid = cha.gid,
						uid = cha.uid,
						atime = cha.atime,
						btime = cha.btime,
						mtime = cha.mtime,
						perm = cha.perm,
					}
					file = File { url = url, cha = dcha }
				end
			else
				-- Normal mode: display all files equally
				file = File { url = url, cha = cha }
			end

			table.insert(files, file)
			ya.dbg(string.format("[Dupes] Added file %s", file.url))
		end
	end

	-- Update the file list in Yazi
	ya.emit("update_files", {
		op = fs.op("part", { id = id, url = Url(cwd), files = files }),
	})

	-- NOTE: Finalization with 'done' operation breaks file ordering
	-- Keeping these commented for future investigation
	-- ya.emit("update_files", {
	-- 	op = fs.op("done", {
	-- 		id = id,
	-- 		url = Url(cwd),
	-- 		cha = Cha({ kind = 16, mode = tonumber("100644", 8) })
	-- 	})
	-- })

	-- Show notification with results
	local mode_text = style and " (DRY RUN)" or ""
	ya.notify {
		title = "Dupes Plugin",
		content = string.format("Found %d files%s", #files, mode_text),
		level = "info",
		timeout = 3,
	}
end

-- ============================================================================
-- FILE SAVING FUNCTIONS
-- ============================================================================

--- Save jdupes output to file (JSON or plain text)
--- @param cwd string Directory to save the file in
--- @param stdout string Raw output from jdupes
--- @param format string Output format: "json" or "txt"
--- @return boolean success True if file was saved successfully
local function save_output(cwd, stdout, format)
	-- Validate format
	format = format or "json"
	if format ~= "json" and format ~= "txt" then
		ya.err(string.format("Invalid format '%s', defaulting to 'json'", format))
		format = "json"
	end

	-- Construct file path
	local file_path = string.format("%s/dupes.%s", cwd, format)

	-- Attempt to write file
	local file, err = io.open(file_path, "w")
	if not file then
		ya.err(string.format("Failed to write dupes.%s to %s: %s", format, file_path, err or "unknown error"))
		ya.notify {
			title = "Dupes Plugin",
			content = string.format("Failed to save file: %s", err or "unknown error"),
			level = "error",
			timeout = 5,
		}
		return false
	end

	-- Write content and close
	file:write(stdout)
	file:close()

	-- Success notification
	ya.notify {
		title = "Dupes Plugin",
		content = string.format("Saved dupes.%s to %s", format, file_path),
		level = "info",
		timeout = 3,
	}

	return true
end

-- ============================================================================
-- COMMAND BUILDING AND VALIDATION
-- ============================================================================

--- Build final command arguments with proper flag handling
--- @param args table User-provided arguments
--- @param no_json boolean Whether to exclude JSON flag
--- @return table Final argument list
local function build_command_args(args, no_json)
	-- Check if JSON flag already exists
	local has_j_flag = false
	for _, arg in ipairs(args) do
		if arg:match("^%-[^-]*j") or arg == "-j" then
			has_j_flag = true
			break
		end
	end

	-- Build final argument list
	local final_args = {}

	-- Add JSON flag if needed and not disabled
	if not has_j_flag and not no_json then
		table.insert(final_args, "-j")
	end

	-- Add all user arguments
	for _, arg in ipairs(args) do
		table.insert(final_args, arg)
	end

	return final_args
end

--- Execute shell command with proper error handling
--- @param cmdline string Base command (e.g., "jdupes")
--- @param args table Command arguments
--- @return table Command result with status, stdout, stderr
local function execute_command(cmdline, args)
	local argstr = table.concat(args, " ")
	local full_cmd = string.format("%s . %s 2>&1", cmdline, argstr)

	ya.dbg(string.format("Executing: %s", full_cmd))

	local cmd = Command(get_state("shell")):arg({ "-c", full_cmd }):stdout(Command.PIPED):stderr(Command.PIPED):output()

	-- Log execution results
	ya.dbg(string.format("Exit code: %s", tostring(cmd.status.code)))

	if cmd.stdout and #cmd.stdout > 0 then
		ya.dbg(string.format("STDOUT length: %d bytes", #cmd.stdout))
	end

	if cmd.stderr and #cmd.stderr > 0 then
		ya.err(string.format("STDERR:\n%s", cmd.stderr))
	end

	return cmd
end

-- ============================================================================
-- CORE EXECUTION FUNCTION
-- ============================================================================

--- Execute jdupes with given profile configuration
--- @param profile_name string Name of the profile being run
--- @param conf table Configuration with cmdline and args
--- @param save_to_file boolean Whether to save output to file
--- @param no_display boolean Whether to skip displaying results in Yazi
--- @param no_json boolean Whether to output plain text instead of JSON
local function run_dupes(profile_name, conf, save_to_file, no_display, no_json)
	-- Validate configuration
	if not conf then
		ya.err(string.format("ERROR: Profile '%s' configuration is nil!", profile_name))
		return
	end

	if not conf.cmdline then
		ya.err(string.format("ERROR: Profile '%s' missing cmdline", profile_name))
		return
	end

	-- Extract configuration with defaults
	local cmdline = conf.cmdline
	local args = conf.args or {}
	save_to_file = save_to_file or false
	no_display = no_display or false
	no_json = no_json or false

	-- Build command arguments
	local final_args = build_command_args(args, no_json)

	-- Execute command
	local cwd = get_cwd()
	local cmd = execute_command(cmdline, final_args)

	-- Handle command results
	if cmd.status.success then
		-- Save output to file if requested
		if save_to_file then
			local format = no_json and "txt" or "json"
			save_output(cwd, cmd.stdout, format)
		end

		-- Display results in Yazi unless suppressed
		if not no_display and not no_json then
			local parsed_data = ya.json_decode(cmd.stdout)
			if parsed_data then
				local is_dry_run = (profile_name == "dry")
				display_dupes(cwd, parsed_data, is_dry_run)
			else
				ya.err("Failed to parse JSON output from jdupes")
				ya.notify {
					title = "Dupes Plugin",
					content = "Failed to parse command output",
					level = "error",
					timeout = 5,
				}
				return
			end
		end

		-- Success notification
		ya.notify {
			title = "Dupes Plugin",
			content = string.format("Profile '%s' completed successfully", profile_name),
			level = "info",
			timeout = 3,
		}
	else
		-- Error notification with details
		local error_msg = cmd.stderr or "(no error details available)"
		ya.notify {
			title = "Dupes Plugin",
			content = string.format("Command failed:\n%s", error_msg),
			level = "error",
			timeout = 5,
		}
	end
end

-- ============================================================================
-- PROFILE HANDLING
-- ============================================================================

--- Create dry-run configuration from apply profile
--- @param apply_conf table Apply profile configuration
--- @return table Dry-run configuration
local function create_dry_config(apply_conf)
	local dry_args = {}

	-- Copy all arguments except destructive ones
	for _, arg in ipairs(apply_conf.args) do
		if arg ~= "-d" and arg ~= "--delete" then
			table.insert(dry_args, arg)
		else
			ya.dbg(string.format("Excluded destructive flag: %s", arg))
		end
	end

	return {
		cmdline = apply_conf.cmdline,
		args = dry_args,
	}
end

--- Parse custom arguments from user input
--- @param input string Space-separated argument string
--- @return table Parsed arguments
local function parse_custom_args(input)
	local args = {}
	for arg in input:gmatch("%S+") do
		table.insert(args, arg)
	end
	return args
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Recursively dump table contents for debugging
--- @param tbl table Table to dump
--- @param indent number Current indentation level
--- @return table Array of formatted lines
local function dump_table(tbl, indent)
	indent = indent or 0
	local lines = {}
	local prefix = string.rep("  ", indent)

	for k, v in pairs(tbl or {}) do
		if type(v) == "table" then
			table.insert(lines, string.format("%s%s = {", prefix, tostring(k)))
			for _, line in ipairs(dump_table(v, indent + 1)) do
				table.insert(lines, line)
			end
			table.insert(lines, string.format("%s},", prefix))
		else
			table.insert(lines, string.format("%s%s = %q,", prefix, tostring(k), tostring(v)))
		end
	end

	return lines
end

--- Count table entries
--- @param tbl table Table to count
--- @return number Number of entries
local function count_table(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
end

-- ============================================================================
-- PLUGIN LIFECYCLE FUNCTIONS
-- ============================================================================

--- Initialize the plugin with user configuration
--- Called from yazi/init.lua
--- @param opts table Configuration options
function M:setup(opts)
	opts = opts or {}

	-- Set global options with defaults
	set_state("save_op", opts.save_op or false)
	set_state("auto_confirm", opts.auto_confirm or false)
	set_state("cmdline", "jdupes")
	set_state("shell", "bash")

	ya.dbg("Dupes Plugin Setup: Starting profile processing")

	-- Process and store user-defined profiles
	local profiles = {}
	if opts.profiles then
		for profile_name, profile_conf in pairs(opts.profiles) do
			-- Validate profile configuration
			if not profile_conf then
				ya.err(string.format("Profile '%s' has nil configuration, skipping", profile_name))
			else
				local profile = {
					cmdline = profile_conf.cmdline or get_state("cmdline"),
					args = profile_conf.args or {},
					-- Profile-specific save_op overrides global setting
					save_op = profile_conf.save_op ~= nil and profile_conf.save_op or get_state("save_op"),
				}
				profiles[profile_name] = profile

				-- Log detailed profile configuration
				local profile_lines = dump_table(profile)
				ya.dbg(string.format("Setup profile '%s':\n%s", tostring(profile_name), table.concat(profile_lines, "\n")))
			end
		end
	else
		ya.dbg("Dupes Plugin Setup: No profiles provided in opts.profiles")
	end

	set_state("profiles", profiles)

	-- Log summary
	local profile_count = count_table(profiles)
	ya.dbg(string.format("Dupes Plugin Setup: Complete with %d profiles", profile_count))

	-- Register custom linemode to show deletion markers
	-- Priority 1500 ensures it runs before most other linemodes
	Linemode:children_add(function(self)
		if not self._file.cha.is_dummy then
			-- Normal file: no marker
			return ""
		elseif self._file.is_hovered then
			-- Hovered dummy file: show black background 'X'
			return ui.Line { " ", ui.Span("X"):style(ui.Style():bg("black")) }
		else
			-- Non-hovered dummy file: show red 'X'
			return ui.Line({ " ", "X" }):style(ui.Style():fg("red"))
		end
	end, 1500)
end

--- Main entry point when plugin is invoked
--- @param job string|table Profile name or job configuration
function M:entry(job)
	-- Exit visual mode if active
	ya.mgr_emit("escape", { visual = true })

	-- Parse profile name from job argument
	local profile_name = "interactive" -- default profile
	if type(job) == "string" then
		profile_name = job
	elseif type(job) == "table" then
		profile_name = (type(job.args) == "table" and job.args[1])
			or (type(job.args) == "string" and job.args)
			or "interactive"
	end

	ya.dbg(string.format("== Invoked profile: %s ==", profile_name))

	-- ========================================================================
	-- SPECIAL PROFILE: override
	-- Allows user to input custom jdupes arguments interactively
	-- ========================================================================
	if profile_name == "override" then
		ya.dbg("INFO: Waiting for custom input")

		local ov_args, ok = ya.input {
			title = "Dupes Override - Enter custom args",
			value = "-j",
			position = { "top-center", y = 3, w = 45 },
		}

		if ok ~= 1 then
			ya.dbg("Override cancelled by user")
			return
		end

		-- Parse and execute custom arguments
		local p_args = parse_custom_args(ov_args)
		run_dupes("override", {
			cmdline = get_state("cmdline"),
			args = p_args,
		}, get_state("save_op"))
		return
	end

	-- ========================================================================
	-- SPECIAL PROFILE: dry
	-- Inherits 'apply' profile but removes destructive flags for preview
	-- ========================================================================
	if profile_name == "dry" then
		local profiles = get_state("profiles")
		local apply_conf = profiles["apply"]

		if not apply_conf then
			ya.notify {
				title = "Dupes Plugin",
				content = "Cannot run dry: 'apply' profile missing.",
				level = "error",
				timeout = 4,
			}
			return
		end

		-- Create dry-run configuration
		local dry_conf = create_dry_config(apply_conf)
		dry_conf.save_op = apply_conf.save_op

		run_dupes("dry", dry_conf, dry_conf.save_op)
		return
	end

	-- ========================================================================
	-- REGULAR PROFILE EXECUTION
	-- ========================================================================
	local profiles = get_state("profiles")
	local conf = profiles[profile_name]

	if not conf then
		ya.err(string.format("ERROR: Profile '%s' not found", profile_name))
		ya.notify {
			title = "Dupes Plugin",
			content = string.format("Profile not found: %s", profile_name),
			level = "error",
			timeout = 3,
		}
		return
	end

	-- ========================================================================
	-- SPECIAL PROFILE: apply
	-- Destructive operation - requires confirmation and runs dry preview first
	-- ========================================================================
	if profile_name == "apply" then
		-- Check for auto-confirm or prompt user
		local apply_confirm = get_state("auto_confirm")
			or ya.confirm {
				pos = { "center", y = -8, w = 36, h = 8 },
				title = "Confirm Deduplication operation?",
				content = ui.Text {
					ui.Line(""),
					ui.Line("This will DELETE duplicate files!"):style(ui.Style():fg("red")),
					ui.Line("If unsure, try dry run first"):style(th.confirm.content),
					ui.Line(""),
				},
			}

		if not apply_confirm then
			ya.dbg("Apply cancelled by user")
			ya.notify {
				title = "Dupes Plugin",
				content = "Operation cancelled",
				level = "info",
				timeout = 3,
			}
			return
		end

		ya.dbg("Apply confirmed by user")

		-- First, run silent dry-run preview for logging
		local dry_conf = create_dry_config(conf)
		run_dupes("dry", dry_conf, conf.save_op, true) -- no_display = true

		-- Then execute actual deletion
		run_dupes(profile_name, conf, conf.save_op, true, true) -- no_display, no_json
		return
	end

	-- ========================================================================
	-- STANDARD PROFILE EXECUTION
	-- For 'interactive' and other custom profiles
	-- ========================================================================
	run_dupes(profile_name, conf, conf.save_op)
end

return M
