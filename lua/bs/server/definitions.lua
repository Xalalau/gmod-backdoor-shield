--[[
    ©2020 Xalalau Xubilozo. All Rights Reserved.
    https://tldrlegal.com/license/all-rights-served#summary
    https://xalalau.com/
--]]

-- Functions that need to be protected
-- Some are scanned or serve some special purpose
BS.control = {
	--[[
	["some.game.function"] = { -- Max. of 2 dots. Ex, 1 dot: http.Fecth = _G["http"]["Fetch"]
		detour = function detoured some.game.function
		debug_getinfo = table debug.getinfo(some.game.function)
		jit_util_funcinfo = table jit_util_funcinfo(some.game.function)
		filter = function to scan some.game.function contents
	},
	]]
	["debug.getinfo"] = {}, -- Isolate our environment
	["jit.util.funcinfo"] = {}, -- Isolate our environment
	["getfenv"] = {}, -- Isolate our environment and alert the user
	["debug.getfenv"] = {}, -- Isolate our environment and alert the user
	["http.Post"] = {},
	["http.Fetch"] = {}, -- scanned
	["CompileString"] = {}, -- scanned
	["CompileFile"] = {}, -- scanned
	["RunString"] = {}, -- scanned
	["RunStringEx"] = {}, -- scanned
	["HTTP"] = {},
	["hook.Add"] = {},
	["hook.Remove"] = {},
	["hook.GetTable"] = {},
	["net.Receive"] = {},
	["net.Start"] = {},
	["net.ReadHeader"] = {},
	["net.WriteString"] = {},
	["require"] = {},
	["pcall"] = {},
	["xpcall"] = {},
	["Error"] = {},
	["jit.util.funck"] = {},
	["util.NetworkIDToString"] = {},
	["TypeID"] = {},
}

-- SCAN LISTS

-- These lists are used to check urls, files and codes passed as argument
-- Note: these lists are locked here for proper security
-- Note2: I'm not using patterns
-- -----------------------------------------------------------------------------------

-- Low risk files and folders
-- When scanning the game, these limes will be considered low risk, so they won't flood
-- the console with warnings (but they'll be normally reported in the logs)
BS.lowRiskFolders = {
	"gamemodes/darkrp/",
	"lua/entities/gmod_wire_expression2/",
	"lua/wire/",
	"lua/ulx/",
	"lua/ulib/",
	"lua/dlib/",
}

BS.lowRiskFiles = {
	"lua/derma/derma.lua",
	"lua/derma/derma_example.lua",
	"lua/entities/gmod_wire_target_finder.lua",
	"lua/entities/gmod_wire_keyboard/init.lua",
	"lua/entities/info_wiremapinterface/init.lua",
	"lua/includes/extensions/debug.lua",
	"lua/includes/modules/constraint.lua",
	"lua/includes/util/javascript_util.lua",
	"lua/includes/util.lua",
	"lua/vgui/dhtml.lua",
	"lua/autorun/cb-lib.lua",
	"lua/autorun/!sh_dlib.lua",
}

-- Whitelist urls
-- Don't scan the downloaded string!
-- Note: protected functions detouring will still be detected and undone
-- Note2: any protected functions called will still be scanned
-- Note3: insert a url starting with http or https and ending with a "/", like https://google.com/
BS.whitelistUrls = {
	"http://www.geoplugin.net/",
}

-- Whitelist TRACE ERRORS
-- By default, I do this instead of whitelisting files because the traces cannot be
-- replicated without many counterpoints
BS.whitelistTraceErrors = {
	"lua/entities/gmod_wire_expression2/core/extloader.lua:86", -- Wiremod
	"gamemodes/darkrp/gamemode/libraries/simplerr.lua:", -- DarkRP
	"lua/autorun/streamradio_loader.lua:254", -- 3D Stream Radio
	"lua/ulib/shared/plugin.lua:186", -- ULib
	"lua/dlib/sh_init.lua:105", -- DLib
	"lua/dlib/core/loader.lua:32", -- DLib
	"lua/dlib/modules/i18n/sh_loader.lua:66", -- DLib
}

-- Whitelist files
-- Ignore these files and all their contents, so they won't going to be scanned at all!
-- Note: protected functions detouring will still be detected and undone
-- Note2: only whitelist files if you trust them completely! Even protected functions will be disarmed
BS.whitelistFiles = {
}

-- Detections with these chars will be considered as not suspect at first
-- This lowers security a bit but eliminates a lot of false positives
BS.notSuspect = {
	"ÿ",
	"", -- 000F
}

-- High chance of direct backdoor detection (all files)
BS.blacklistHigh = {
	"=_G", -- !! Used by backdoors to start hiding names. Also, there is an extra check in the code to avoid incorrect results.
	"(_G)",
	",_G,",
	"!true",
	"!false",
}

-- High chance of direct backdoor detection (suspect code only)
BS.blacklistHigh_suspect = {
	"‪", -- LEFT-TO-RIGHT EMBEDDING
}

-- Medium chance of direct backdoor detection (all files)
BS.blacklistMedium = {
	"RunString",
	"RunStringEx",
	"CompileString",
	"CompileFile",
	"BroadcastLua",
	"setfenv",
	"http.Fetch",
	"http.Post",
	"debug.getinfo",
}

-- Medium chance of direct backdoor detection (suspect code only)
BS.blacklistMedium_suspect = {
	"_G[",
	"_G.",
}

-- Low chance of direct backdoor detection (all files)
BS.suspect = {
	"pcall",
	"xpcall",
	"SendLua",
}

-- Low chance of direct backdoor detection (suspect code only)
-- Note: during the scanner, if a file is detected with only 1
-- of the values below, it will be discarded from the results.
BS.suspect_suspect = {
	"]()",
	"0x",
	"\\x",
}
