-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, iCPU = ...;
LibStub("AceEvent-3.0"):Embed(iCPU);
LibStub("AceTimer-3.0"):Embed(iCPU);

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local LibCrayon = LibStub("LibCrayon-3.0");

local _G = _G; -- I always use _G.FUNC when I call a Global. Upvalueing done here.
local format = string.format;

-------------------------------
-- Registering with iLib
-------------------------------

LibStub("iLib"):Register(AddonName, nil, iCPU);

-----------------------------------------
-- Variables, functions and colors
-----------------------------------------

local UpdateTimer; -- timer when the roster is fetched again
local Mods = {};
M = Mods;

local iFramerate = 0;
local iLatencyHome = 0;
local iLatencyWorld = 0;
local iUpload = 0;
local iDownload = 0;

local TotalCPU = 0;
local TotalCPUDiff = 0;
local TotalMemory = 0;
local TotalMemoryDiff = 0;

local isProfiling;

local hugeAddonMemory = 61440; -- 60 MB
local hugeFramerate = 48;
local hugeLatency = 200;

local COLOR_GOLD = "|cfffed100%s|r";

------------------------------
-- Formatting Functions
------------------------------

local function format_memory(value, state, space)
	local v2 = value;
	
	if( value > 1024 ) then
		value = ("%.2f"..(space and "" or " ").."|cffff8100%s|r"):format((value / 1024), "mb");
	else
		value = ("%.2f"..(space and "" or " ")..COLOR_GOLD):format(value, "kb");
	end
	
	if( state == true ) then
		value = "|cffff5555"..value.."|r";
	elseif( state == false ) then
		value = "|cff00ff00"..value.."|r";
	elseif( state == 0 ) then
		value = "|cff888888"..value.."|r";
	else
		value = "|cff"..LibCrayon:GetThresholdHexColor(hugeAddonMemory - v2, hugeAddonMemory)..value.."|r";
	end
	
	return value;
end

local function format_kbs(value)
	return ("%.2f "..COLOR_GOLD):format(value, "kb/s");
end

local function format_latency(value, space)
	return ("|cff%s%d|r"..(space and "" or " ")..COLOR_GOLD):format(LibCrayon:GetThresholdHexColor(hugeLatency - value, hugeLatency), value, "ms");
end

local function format_fps(value, space)
	return ("|cff%s%.2f|r"..(space and "" or " ")..COLOR_GOLD):format(LibCrayon:GetThresholdHexColor(value, hugeFramerate), value, "fps");
end

-----------------------------
-- Setting up the LDB
-----------------------------

iCPU.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(AddonName, {
	type = "data source",
	text = "",
});

iCPU.ldb.OnClick = function(_, button)
	if( button == "LeftButton" ) then
		if( not _G.IsModifierKeyDown() ) then
			collectgarbage();
		end
	elseif( button == "RightButton" ) then
		if( not _G.IsModifierKeyDown() ) then
			iCPU:OpenOptions();
		end
	end
end

iCPU.ldb.OnEnter = function(anchor)
	if( iCPU:IsTooltip("Main") ) then
		return;
	end
	iCPU:HideAllTooltips();
	
	local tip = iCPU:GetTooltip("Main", "UpdateTooltip");
	tip:SmartAnchorTo(anchor);
	tip:SetAutoHideDelay(0.25, anchor);
	tip:Show();
end

iCPU.ldb.OnLeave = function() end -- some display addons refuse to display brokers when this is not defined

----------------------
-- Boot
----------------------

do
	local mt = {
		__index = function(t, k)
			if(     k == "name"   ) then return t[1]
			elseif( k == "active" ) then return t[2]
			elseif( k == "error"  ) then return t[3]
			elseif( k == "cpu"    ) then return t[4]
			elseif( k == "cpud"   ) then return t[5]
			elseif( k == "mem"    ) then return t[6]
			elseif( k == "memd"   ) then return t[7]
			elseif( k == "cpus"   ) then return t[5] == 0 and 0 or (t[5] > 0 and true or false)
			elseif( k == "mems"   ) then return t[7] == 0 and 0 or (t[7] > 0 and true or false)
			end
		end,
		__newindex = function(t, k, v)
			local slot;
			
			if(     k == "cpu"  ) then slot = 4
			elseif( k == "cpud" ) then slot = 5
			elseif( k == "mem"  ) then slot = 6
			elseif( k == "memd" ) then slot = 7
			end
			
			if( slot ) then
				rawset(t, slot, v);
			end
		end
	};

	function iCPU:Boot()
		self.db = LibStub("AceDB-3.0"):New("iCPUDB", self:CreateDB(), "Default").profile;
		
		-- Initialize table of addons
		local name, title, enabled, reason, _;
		local Iter = 1;
		
		for i = 1, _G.GetNumAddOns() do
			name, _, _, enabled, _, reason, _ = _G.GetAddOnInfo(i);
			
			if( _G.IsAddOnLoaded(name) ) then
				Mods[Iter] = {
					[1] = name,
					[2] = enabled and true or false,
					[3] = reason or "",
					[4] = 0, -- CPU usage
					[5] = 0, -- CPU diff
					[6] = 0, -- Mem usage
					[7] = 0, -- Mem diff
				};
				setmetatable(Mods[Iter], mt);
				
				Iter = Iter + 1;
			end
		end
		
		-- Initialize the script profiling variable
		isProfiling = _G.GetCVar("scriptProfile") == "1";
		
		-- Initialize the timer
		self:RefreshTimer(1.5);
		
		self:UnregisterEvent("PLAYER_ENTERING_WORLD");
	end
end
iCPU:RegisterEvent("PLAYER_ENTERING_WORLD", "Boot");

----------------------
-- RefreshTimer
----------------------

function iCPU:RefreshTimer(timeToPass)
	if( UpdateTimer ) then
		self:CancelTimer(UpdateTimer);
		UpdateTimer = nil;
	end
	
	if( not timeToPass ) then
		timeToPass = self.db.UpdateTimer;
	end
	
	UpdateTimer = self:ScheduleRepeatingTimer("UpdateData", timeToPass);
	self:UpdateData();
end

----------------------
-- UpdateBroker
----------------------

function iCPU:UpdateBroker()
	self.ldb.text = format_memory(TotalMemory, nil, true).." "..format_fps(iFramerate, true).." "..format_latency(iLatencyWorld, true);
end

------------------
-- SortData
------------------

local function SortModsData(a, b)
	if( isProfiling ) then
		if( a.cpu > b.cpu ) then
			return true;
		elseif( a.cpu < b.cpu ) then
			return false;
		else
			return a.name < b.name;
		end
	else
		if( a.mem > b.mem ) then
			return true;
		elseif( a.mem < b.mem ) then
			return false;
		else
			return a.name < b.name;
		end
	end
end

--------------------
-- UpdateData
--------------------

function iCPU:UpdateData()	
	if( isProfiling ) then	
		_G.UpdateAddOnCPUUsage();
	end
	_G.UpdateAddOnMemoryUsage();
	
	TotalCPU = 0;
	TotalCPUDiff = 0;
	TotalMemory = 0;
	TotalMemoryDiff = 0;
	
	local cpu, mem;
	for _,addon in ipairs(Mods) do
		cpu = isProfiling and _G.GetAddOnCPUUsage(addon.name) or 0;
		mem = _G.GetAddOnMemoryUsage(addon.name) or 0;
		
		addon.cpud = cpu - addon.cpu;
		addon.memd = mem - addon.mem;
		addon.cpu = cpu;
		addon.mem = mem;
		
		TotalCPU = TotalCPU + cpu;
		TotalCPUDiff = TotalCPUDiff + addon.cpud;
		TotalMemory = TotalMemory + mem;
		TotalMemoryDiff = TotalMemoryDiff + addon.memd;
	end
	table.sort(Mods, SortModsData);
	
	iFramerate = _G.GetFramerate();
	iDownload, iUpload, iLatencyHome, iLatencyWorld = _G.GetNetStats();
	
	if( self:IsTooltip("Main") ) then
		self:CheckTooltips("Main");
	end
	
	self:UpdateBroker();
end

-----------------------
-- UpdateTooltip
-----------------------

function iCPU:UpdateTooltip(tip)
	local firstDisplay = tip:GetLineCount() == 0;
	if( firstDisplay ) then
		tip:SetColumnLayout(isProfiling and 6 or 4, "RIGHT", "LEFT", "RIGHT", "RIGHT", "RIGHT", "RIGHT");
	end
	
	local line;
	
	if( firstDisplay ) then
		for i = 1, self.db.DisplayNumAddons do
			tip:AddLine((COLOR_GOLD):format(i));
		end
		
		tip:AddLine(" ");
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format("Total"), nil, "LEFT", 2);
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format("Total & Blizzard"), nil, "LEFT", -2);
		
		tip:AddLine(" ");
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format("Framerate"), nil, "LEFT", -2);
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format("Latency"), nil, "LEFT", -2);
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format("Download"), nil, "LEFT", -2);
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format("Upload"), nil, "LEFT", -2);
		
		if( LibStub("iLib"):IsUpdate(AddonName) ) then
			tip:AddSeparator();
			line = tip:AddLine("");
			tip:SetCell(line, 1, "|cffff0000"..L["Addon update available!"].."|r", nil, "CENTER", 0);
		end
	end
	
	for i = 1, self.db.DisplayNumAddons do
		tip:SetCell(i, 2, Mods[i].name);
		
		if( isProfiling ) then
			tip:SetCell(i, 3, Mods[i].cpu);
			tip:SetCell(i, 4, Mods[i].cpud);
		end
		
		tip:SetCell(i, isProfiling and 5 or 3, format_memory(Mods[i].mem, Mods[i].mems));
		tip:SetCell(i, isProfiling and 6 or 4, Mods[i].memd == 0 and "" or format_memory(Mods[i].memd, Mods[i].mems));
	end
	
	if( isProfiling ) then
		tip:SetCell(self.db.DisplayNumAddons + 2, 3, TotalCPU);
		tip:SetCell(self.db.DisplayNumAddons + 2, 4, TotalCPUDiff);
	end
	
	tip:SetCell(self.db.DisplayNumAddons + 2, isProfiling and 5 or 3, format_memory(TotalMemory));
	tip:SetCell(self.db.DisplayNumAddons + 2, isProfiling and 6 or 4, format_memory(TotalMemoryDiff));
	
	tip:SetCell(self.db.DisplayNumAddons + 3, isProfiling and 5 or 3, format_memory(collectgarbage("count")));
	
	tip:SetCell(self.db.DisplayNumAddons + 5, isProfiling and 5 or 3, format_fps(iFramerate), nil, "RIGHT", 2);
	tip:SetCell(self.db.DisplayNumAddons + 6, isProfiling and 5 or 3, format_latency(iLatencyWorld), nil, "RIGHT", 2);
	tip:SetCell(self.db.DisplayNumAddons + 7, isProfiling and 5 or 3, format_kbs(iDownload), nil, "RIGHT", 2);
	tip:SetCell(self.db.DisplayNumAddons + 8, isProfiling and 5 or 3, format_kbs(iUpload), nil, "RIGHT", 2);
end