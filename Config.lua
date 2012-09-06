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

local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";

---------------------------
-- The options table
---------------------------

function iCPU:CreateDB()
	iCPU.CreateDB = nil;
	
	return { profile = {
		UpdateInterval = 2.5,
		DisplayNumAddons = 30,
		DecimalDigits = 1,
		PluginShowMemory = true,
		PluginShowFramerate = true,
		PluginShowLatency = true,
		PluginShowCPU = true,
	}};
end

---------------------------------
-- The configuration table
---------------------------------

local function CreateConfig()
	return {
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
			GroupGeneral = {
				type = "group",
				name = L["General Options"],
				order = 10,
				inline = true,
				args = {
					DecimalDigits = {
						type = "range",
						name = L["Decimal digits"],
						desc = L["The number of decimal digits for all numbers."],
						order = 1,
						min = 0,
						max = 3,
						step = 1,
					},
					UpdateInterval = {
						type = "range",
						name = L["Update Interval"],
						desc = L["The lower the value, the more CPU is needed!"],
						order = 5,
						min = 1,
						max = 30,
						step = 0.5,
						width = "double",
						set = function(info, value)
							iCPU.db.UpdateInterval = value;
							iCPU:RefreshTimer();
						end,
					},
				},
			},
			GroupPlugin = {
				type = "group",
				name = L["Plugin Options"],
				order = 20,
				inline = true,
				args = {
					PluginShowMemory = {
						type = "toggle",
						name = L["Display Memory"],
						order = 1,
					},
					PluginShowFramerate = {
						type = "toggle",
						name = L["Display FPS"],
						order = 5,
					},
					PluginShowLatency = {
						type = "toggle",
						name = L["Display Latency"],
						order = 10,
					},
					PluginShowCPU = {
						type = "toggle",
						desc = L["Displays the CPU time on the plugin when CPU profiling is enabled (Ctrl+Click)."],
						name = L["Display CPU"],
						order = 15,
					},
				},
			},
			GroupTooltip = {
				type = "group",
				name = L["Tooltip Options"],
				order = 30,
				inline = true,
				args = {
				
				},
			},
			
		},
	};
end

function iCPU:OpenOptions()
	_G.InterfaceOptionsFrame_OpenToCategory(AddonName);
end

LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, CreateConfig);
LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName);
_G.SlashCmdList["ICPU"] = iCPU.OpenOptions;
_G["SLASH_ICPU1"] = "/icpu";