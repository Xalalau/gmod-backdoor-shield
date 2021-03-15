--[[
    2020-2021 Xalalau Xubilozo. MIT License
    https://xalalau.com/
--]]

-- Auto check for detouring
-- 	 First 5m running: check every 5s
-- 	 Later: check every 60s
function BS:Validate_AutoCheckDetouring()
	local function SetAuto(name, delay)
		timer.Create(name, delay, 0, function()
			if self.RELOADED then
				timer.Remove(name)

				return
			end

			for funcName,_ in pairs(self.control) do
				self:Validate_Detour(funcName)
			end
		end)
	end

	local name = self:Utils_GetRandomName()

	SetAuto(name, 5)

	timer.Simple(300, function()
		SetAuto(name, 60)
	end)
end

-- Check a detour
function BS:Validate_Detour(funcName, trace)
	local currentAddress = self:Functions_GetCurrent(funcName)
	local detourAddress = self.control[funcName].detour
	local trace_aux = debug.getinfo(currentAddress, "S").source

	if detourAddress ~= currentAddress then
		local info = {
			func = name,
			trace = trace or trace_aux
		}

		-- Check if it's a low risk detection. If so, only report
		local lowRisk = false

		if not trace_aux or string.len(trace_aux) == 4 then
			trace_aux = self:Utils_ConvertAddonPath(string.Trim(string.Explode(":", string.Explode("\n", trace or debug.traceback())[2])[1]))
		else
			trace_aux = self:Utils_ConvertAddonPath(string.sub(trace_aux, 1, 1) == "@" and string.sub(trace_aux, 2))
		end

		if self.lowRiskFiles_Check[trace_aux] then
			lowRisk = true
		else
			for _,v in pairs(self.lowRiskFolders) do
				local start = string.find(trace_aux, v, nil, true)

				if start == 1 then
					lowRisk = true

					break
				end
			end
		end

		if lowRisk then
			if self.IGNORED_DETOURS[trace_aux] then
				return true
			end

			info.suffix = "warning"
			info.alert = "Warning! Detour detected in a low risk location. Ignoring it..."
			self.IGNORED_DETOURS[trace_aux] = true
		else
			info.suffix = "detour"
			info.alert = "Detour captured and undone!"

			self:Functions_SetDetour_Aux(funcName, detourAddress)
		end

		self:Report_Detection(info)

		return false
	end

	return true
end

-- Check http.fetch calls
function BS:Validate_HttpFetchPost(trace, funcName, args)
	local url = args[1]

	local function Scan(args2)
		local blocked = {{}, {}}
		local warning = {}
		local detected

		for k,v in pairs(self.whitelistUrls) do
			local urlStart = string.find(url, v)

			if urlStart and urlStart == 1 then
				return self:Functions_CallProtected(funcName, args)
			end
		end

		self:Scan_String(trace, url, "lua", blocked, warning)

		for _,arg in pairs(args2) do
			if isstring(arg) then
				self:Scan_String(trace, arg, "lua", blocked, warning)
			elseif istable(arg) then
				for k,v in pairs(arg) do
					self:Scan_String(trace, k, "lua", blocked, warning)
					self:Scan_String(trace, v, "lua", blocked, warning)
				end
			end
		end

		local detected = (#blocked[1] > 0 or #blocked[2] > 0) and { "blocked", "Execution blocked!", blocked } or
		                 #warning > 0 and { "warning", "Suspicious execution!", warning }

		if detected then
			local info = {
				suffix = detected[1],
				folder = funcName,
				alert = detected[2],
				func = funcName,
				trace = trace,
				url = url,
				detected = detected[3],
				content = table.ToString(args2, "arguments", true)
			}

			self:Report_Detection(info)
		end

		if #blocked[1] == 0 and #blocked[2] == 0 then
			self:Functions_CallProtected(funcName, args)
		end
	end

	if funcName == "http.Fetch" then
		http.Fetch(url, function(...)
			local args2 = { ... }
			Scan(args2)
		end, function(...)
			local args2 = { ... }
			Scan(args2)
		end, args[4])
	elseif funcName == "http.Post" then
		http.Post(url, args[2], function(...)
			local args2 = { ... }
			args2[9999] = args[2]
			Scan(args2)
		end, function(...)
			local args2 = { ... }
			args2[9999] = args[2]
			Scan(args2)
		end, args[5])
	end

	return true
end

-- Check CompileString, CompileFile, RunString and RunStringEX calls
function BS:Validate_StrCode(trace, funcName, args)
	local code = funcName == "CompileFile" and file.Read(args[1], "LUA") or args[1]
	local blocked = {{}, {}}
	local warning = {}

	if not _G[funcName] then return "" end -- RunStringEx exists but is deprecated
	if not isstring(code) then return "" end -- Just checking

	self:Scan_String(trace, code, "lua", blocked, warning)

	local detected = (#blocked[1] > 0 or #blocked[2] > 0) and { "blocked", "Execution blocked!", blocked } or
	                 #warning > 0 and { "warning", "Suspicious execution!", warning }

	if detected then
		local info = {
			suffix = detected[1],
			folder = funcName,
			alert = detected[2],
			func = funcName,
			trace = trace,
			detected = detected[3],
			content = code
		}

		self:Report_Detection(info)
	end

	return #blocked[1] == 0 and #blocked[2] == 0 and self:Functions_CallProtected(funcName, #args > 0 and args or {""})
end

-- Protect our custom environment
function BS:Validate_Environment(trace, funcName, args)
	local result = self:Functions_CallProtected(funcName, args)
	result = result == _G and self.__G or result

	if result == self.__G then
		local info = {
			suffix = "warning",
			alert = "A script got _G through " .. funcName .. "!",
			func = funcName,
			trace = trace,
		}

		self:Report_Detection(info)
	end

	return result
end

-- Hide our detours
--   These functions are used to verify if other functions have valid addresses:
--     debug.getinfo, jit.util.funcinfo and tostring
local checking = {}
function BS:Validate_Adrresses(trace, funcName, args)
	if checking[funcName] then -- Avoid loops
		return self:Functions_CallProtected(funcName, args)
	end
	checking[funcName] = true

	if args[1] and isfunction(args[1]) then
		for k,v in pairs(self.control) do
			if args[1] == v.detour then
				args[1] = self:Functions_GetCurrent(k, _G)
				break
			end
		end
	end

	checking[funcName] = nil
	return self:Functions_CallProtected(funcName, args)
end

-- HACKS: For some reason this function is EXTREMELY temperamental! I was unable to use the
-- code inside the orignal function, to pass parameters and even to freely write variables
-- or acceptable syntax. It only works when it's this mess. Test each changed line if you
-- want to touch it.
-- If the stack is good, return false
-- If the stack is bad, return the detected func address, func name 1 and func name 2
local BS_PROTECTEDCALLS_Hack
local Callers_Aux_StartHack = { ["Validate_Callers_Aux"] = true }
local _debug = {}
_debug.getinfo = debug.getinfo
_debug.getlocal = debug.getlocal
local function Validate_CallStack()
	local counter = { increment = 1, detected = 0, jumpStart = 0, firstDetection = "" }
	while true do
		local func = _debug.getinfo(counter.increment, "flnSu" )
		local name, value = _debug.getlocal(1, 2, counter.increment)
		if func == nil then break end
		if value then
			print(value.name and value.name or "")
			--print(value.func)
			if counter.jumpStart == 3 then
				if value.func then
					--print(value.name and value.name or "")
					for k,v in ipairs(BS_PROTECTEDCALLS_Hack) do
						if value.func and value.func == v then
							counter.detected = counter.detected + 1
							if counter.detected == 2 then
								return value.func, value.name and value.name or "", counter.firstDetection
							else
								counter.firstDetection = value.name and value.name or ""
							end
							break
						end
					end
				end
			end
			if counter.jumpStart == 2 then
				counter.jumpStart = counter.jumpStart + 1
			end
			if value.name and Callers_Aux_StartHack[value.name] then
				counter.jumpStart = counter.jumpStart + 1
			end
		end
		counter.increment = counter.increment + 1
	end
	return false
end

-- Validate functions that can't call each other
local callersWarningCooldown = {} -- Don't flood the console with messages
function BS:Validate_Callers(trace, funcName, args)
	-- Hack, explained above Validate_Callers_Aux()
	if not BS_PROTECTEDCALLS_Hack then
		BS_PROTECTEDCALLS_Hack = table.Copy(self.PROTECTEDCALLS)
	end

	local funcAddress, funcName1, funcName2 = Validate_CallStack()

	if funcAddress then
		if not callersWarningCooldown[funcAddress] then
			callersWarningCooldown[funcAddress] = true
			timer.Simple(0.1, function()
				callersWarningCooldown[funcAddress] = nil
			end)

			local info = {
				suffix = "unknown",
				folder = funcName2,
				alert = "Dangerous execution detected! The blocking attempt was uncertain!",
				func = funcName2,
				trace = trace,
				detected = { funcName1 }
			}

			self:Report_Detection(info)
		end

		return false
	else
		return true
	end
end