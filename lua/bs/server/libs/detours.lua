--[[
    2020-2021 Xalalau Xubilozo. MIT License
    https://xalalau.com/
--]]

-- Initialize detours and filters from the control table
function BS:Detours_Init()
	for protectedFunc,_ in pairs(self.live.control) do
		local filters = self.live.control[protectedFunc].filters
		local failed = self.live.control[protectedFunc].failed
		local fast = self.live.control[protectedFunc].fast

		if isstring(filters) then
			self.live.control[protectedFunc].filters = self[self.live.control[protectedFunc].filters]
			filters = { self.live.control[protectedFunc].filters }
		elseif istable(filters) then
			for k,_ in ipairs(filters) do
				self.live.control[protectedFunc].filters[k] = self[self.live.control[protectedFunc].filters[k]]
			end

			filters = self.live.control[protectedFunc].filters
		end

		self:Detours_Create(protectedFunc, filters, failed, fast)
	end
end

-- Auto detouring protection
-- 	 First 5m running: check every 5s
-- 	 Later: check every 60s
-- This function isn't really necessary, but it's good for advancing detections
function BS:Detours_SetAutoCheck()
	local function SetAuto(name, delay)
		timer.Create(name, delay, 0, function()
			if self.reloaded then
				timer.Remove(name)

				return
			end

			for funcName,_ in pairs(self.live.control) do
				self:Detours_Validate(funcName)
			end
		end)
	end

	local name = self:Utils_GetRandomName()

	SetAuto(name, 5)

	timer.Simple(300, function()
		SetAuto(name, 60)
	end)
end

-- Protect a detoured address
function BS:Detours_Validate(funcName, trace, isLowRisk)
	local currentAddress = self:Detours_GetFunction(funcName)
	local detourAddress = self.live.control[funcName].detour
	local luaFile

    if not trace or string.len(trace) == 4 then
		local source = debug.getinfo(currentAddress, "S").source
        luaFile = self:Utils_ConvertAddonPath(string.sub(source, 1, 1) == "@" and string.sub(source, 2))
	else 
        luaFile = self:Trace_GetLuaFile()
    end

	if detourAddress ~= currentAddress then
		local info = {
			func = funcName,
			trace = trace or luaFile
		}

		if isLowRisk then
			info.type = "warning"
			info.alert = "Warning! Detour detected in a low-risk location. Ignoring it..."
		else
			info.type = "detour"
			info.alert = "Detour captured and undone!"

			self:Detours_SetFunction(funcName, detourAddress)
		end

		self:Report_Detection(info)

		return false
	end

	return true
end

-- Call an original game function from our protected environment
-- Note: It was created to simplify these calls directly from Detours_GetFunction()
function BS:Detours_CallOriginalFunction(funcName, args)
	return self:Detours_GetFunction(funcName, _G)(unpack(args))
end

-- Get a function address by name from a selected environment
function BS:Detours_GetFunction(funcName, env)
	env = env or self.__G
	local currentFunc = {}

	for k,v in ipairs(string.Explode(".", funcName)) do
		currentFunc[k] = currentFunc[k - 1] and currentFunc[k - 1][v] or env[v]
	end

	return currentFunc[#currentFunc]
end

-- Update a function address by name in a selected environment
function BS:Detours_SetFunction(funcName, newfunc, env)
	env = env or self.__G

	local newTable = {}
	local newTableCurrent = newTable
	local explodedFuncName = string.Explode(".", funcName)

	for k,namePart in ipairs(explodedFuncName) do
		newTableCurrent[namePart] = k == #explodedFuncName and newfunc or {}
		newTableCurrent = newTableCurrent[namePart]
	end

	table.Merge(env, newTable)
end

-- Set a detour (including the filters)
-- Note: if a filter validates but doesn't return the result from Detours_CallOriginalFunction(), just return "true" (between quotes!)
function BS:Detours_Create(funcName, filters, failed, fast)
	local running = {} -- Avoid loops

	function Detour(...)
		local args = {...} 

		-- Avoid loops
		if running[funcName] then
			return self:Detours_CallOriginalFunction(funcName, args)
		end
		running[funcName] = true

		-- Fast mode
		if fast then
			self:Detours_Validate(funcName, trace)
			running[funcName] = nil

			return filters and filters[1](self, trace, funcName, args) or self:Detours_CallOriginalFunction(funcName, args)
		end

		-- Get and check the trace
		local trace = self:Trace_Get(debug.traceback())
		local isWhitelisted = self:Trace_IsWhitelisted(trace)

		if isWhitelisted then
			running[funcName] = nil

			return self:Detours_CallOriginalFunction(funcName, args)
		end

		local isLowRisk = self:Trace_IsLowRisk(trace)
		
		-- Check detour
		self:Detours_Validate(funcName, trace, isLowRisk)

		-- Run filters
		if filters then
			local i = 1
			for _,filter in ipairs(filters) do
				local result = filter(self, trace, funcName, args, isLowRisk)

				running[funcName] = nil

				if not result then
					return failed
				elseif i == #filters then
					return result ~= "true" and result or self:Detours_CallOriginalFunction(funcName, args)
				end

				i = i + 1
			end
		else
			running[funcName] = nil

			return self:Detours_CallOriginalFunction(funcName, args)
		end
	end

	-- Set detour
	self:Detours_SetFunction(funcName, Detour)
	self.live.control[funcName].detour = Detour
end

-- Remove our detours
-- Used only by live reloading functions
function BS:Detours_Remove()
	for k,v in pairs(self.live.control) do
		self:Detours_SetFunction(k, self:Detours_GetFunction(k, _G))
	end
end
