-----------------------------
-- Get the addon table
-----------------------------

local AddonName, iCPU = ...;

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local _G = _G; -- I always use _G.FUNC when I call a Global. Upvalueing done here.
local format = string.format;

-----------------------------------------
-- Variables, functions and colors
-----------------------------------------

local cfg; -- this stores our configuration GUI

local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";

---------------------------
-- The options table
---------------------------

function iCPU:CreateDB()
	iCPU.CreateDB = nil;
	
	return { profile = {
		UpdateTimer = 5,
		DisplayNumAddons = 30,
		DecimalDigits = 2,
	}};
end

---------------------------------
-- The configuration table
---------------------------------

cfg = {
		type = "group",
		name = AddonName,
		order = 1,
		get = function(info)
			return iCPU.db[info[#info]];
		end,
		set = function(info, value)
			iCPU.db[info[#info]] = value;
		end,
		args = {
			
		},
};

function iCPU:OpenOptions()
	_G.InterfaceOptionsFrame_OpenToCategory(AddonName);
end

LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, cfg);
LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName);
_G.SlashCmdList["ICPU"] = iCPU.OpenOptions;
_G["SLASH_ICPU1"] = "/icpu";