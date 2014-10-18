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

local hugeAddonMemory = 61440; -- 60 MB = red colors, everything lower colors it green
local hugeFramerate = 48; -- at 24fps, the fps becomes yellow, higher values color it green, lower values red
local hugeLatency = 200; -- at 100ms, the latency becomes yellow, lower than 100ms colors it green, higher values red

local UpdateTimer;
local Mods = {};

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

local COLOR_GOLD = "|cfffed100%s|r";

------------------------------
-- Formatting Functions
------------------------------

local function format_memory(value, state, space)
	local v2 = value;
	
	if( value > 1024 ) then
		value = ("%."..iCPU.db.DecimalDigits.."f"..(space and "" or " ").."|cffff8100%s|r"):format((value / 1024), L["mb"]);
	else
		value = ("%."..iCPU.db.DecimalDigits.."f"..(space and "" or " ")..COLOR_GOLD):format(value, L["kb"]);
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

local function format_cpu(value, state, space)	
	if( state ) then
		value = ("|cff00ffff%."..iCPU.db.DecimalDigits.."f|r"..(space and "" or " ")..COLOR_GOLD):format(value, L["ms"]);
	else
		value = ("|cffee33ff%."..iCPU.db.DecimalDigits.."f|r"..(space and "" or " ")..COLOR_GOLD):format(value, L["ms"]);
	end
		
	return value;
end

local function format_kbs(value)
	return ("%."..iCPU.db.DecimalDigits.."f "..COLOR_GOLD):format(value, L["kb/s"]);
end

local function format_latency(value, space)
	return ("|cff%s%d|r"..(space and "" or " ")..COLOR_GOLD):format(LibCrayon:GetThresholdHexColor(hugeLatency - value, hugeLatency), value, L["ms"]);
end

local function format_fps(value, space)
	return ("|cff%s%."..iCPU.db.DecimalDigits.."f|r"..(space and "" or " ")..COLOR_GOLD):format(LibCrayon:GetThresholdHexColor(value, hugeFramerate), value, L["fps"]);
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
		else
			if( _G.IsControlKeyDown() ) then
				_G.SetCVar("scriptProfile", tostring( 1 - tonumber(_G.GetCVar("scriptProfile")) ));
				_G.ReloadUI();
			end
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
	
	if( iCPU.db.TooltipUseScroller ) then
		tip:UpdateScrolling(iCPU.db.TooltipMaxSize);
	end
	
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
			elseif( k == "cpus"   ) then return not(t[5] == 0)
			elseif( k == "mems"   ) then return t[7] == 0 and 0 or (t[7] > 0 and true or false)
			elseif( k == "grdn"   ) then return t[8]
			end
		end,
		__newindex = function(t, k, v)
			local slot;
			
			if(     k == "cpu"  ) then slot = 4
			elseif( k == "cpud" ) then slot = 5
			elseif( k == "mem"  ) then slot = 6
			elseif( k == "memd" ) then slot = 7
			elseif( k == "grdn" ) then slot = 8
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
					[8] = (_G.GetAddOnMetadata(name, "Author") == "grdn")
				};
				setmetatable(Mods[Iter], mt);
				
				Iter = Iter + 1;
			end
		end
		
		-- Initialize the script profiling variable
		isProfiling = _G.GetCVar("scriptProfile") == "1";
		
		-- Initialize the timer
		self:RefreshTimer();
		
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
		timeToPass = self.db.UpdateInterval;
	end
	
	UpdateTimer = self:ScheduleRepeatingTimer("UpdateData", timeToPass);
	self:UpdateData();
end

----------------------
-- UpdateBroker
----------------------

function iCPU:UpdateBroker()
	if( not self.db.PluginShowMemory and not self.db.PluginShowFramerate and not self.db.PluginShowLatency
			and not (isProfiling and not self.db.PluginShowCPU)) then
		self.ldb.text = "|cffffff00"..AddonName.."|r";
	else		
		self.ldb.text =
			(isProfiling and self.db.PluginShowCPU and format_cpu(TotalCPU, true, true).." " or "")..
			(self.db.PluginShowMemory and format_memory(TotalMemory, nil, true).." " or "")..
			(self.db.PluginShowFramerate and format_fps(iFramerate, true).." " or "")..
			(self.db.PluginShowLatency and format_latency(iLatencyWorld, true).." " or "")
		;
	end
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
	
	self:CheckTooltips("Main");
	self:UpdateBroker();
end

-----------------------
-- UpdateTooltip
-----------------------

local pos;
function iCPU:UpdateTooltip(tip)
	local firstDisplay = tip:GetLineCount() == 0;
	if( firstDisplay ) then
		tip:SetColumnLayout(isProfiling and 6 or 4, "LEFT", "LEFT", "RIGHT", "RIGHT", "RIGHT", "RIGHT");
	end
	
	local line;
	
	local numAddons = self.db.DisplayNumAddons > #Mods and #Mods or self.db.DisplayNumAddons;
	local addonPos = 0; -- if the update notice is displayed, addonPos is increased by 1
	
	if( firstDisplay ) then
		if( LibStub("iLib"):IsUpdate(AddonName) ) then
			line = tip:AddHeader("");
			tip:SetCell(line, 1, "|cffff0000"..L["Addon update available!"].."|r", nil, "CENTER", 0);
			addonPos = 1;
		end
		
		if( self.db.DisplayNumAddons > 0 ) then
			for i = 1, numAddons do
				tip:AddLine((COLOR_GOLD):format(i));
			end
			
			tip:AddLine(" ");
		end
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format(_G.TOTAL), nil, "LEFT", 2);
		
		line = tip:AddLine(" ");
		tip:SetCell(line, 1, (COLOR_GOLD):format(L["Blizz UI"]), nil, "LEFT", -2);
		
		if( self.db.TooltipShowFramerate or self.db.TooltipShowLatency or self.db.TooltipShowStreaming ) then
			tip:AddLine(" ");
			
			if( self.db.TooltipShowFramerate ) then
				line = tip:AddLine(" ");
				tip:SetCell(line, 1, (COLOR_GOLD):format(L["Framerate"]), nil, "LEFT", -2);
			end
			
			if( self.db.TooltipShowLatency ) then
				line = tip:AddLine(" ");
				tip:SetCell(line, 1, (COLOR_GOLD):format(L["Latency"]), nil, "LEFT", -2);
			end
			
			if( self.db.TooltipShowStreaming ) then
				line = tip:AddLine(" ");
				tip:SetCell(line, 1, (COLOR_GOLD):format(L["Stream (U/D)"]), nil, "LEFT", -2);
			end
		end
	end
	
	if( self.db.DisplayNumAddons > 0 ) then
		for i = 1, numAddons do
			if( Mods[i].name == AddonName ) then
				tip:SetCell(addonPos + i, 2, "|cff11bbbb"..Mods[i].name.."|r");
			else
				if( Mods[i].grdn ) then
					tip:SetCell(addonPos + i, 2, "|cffffff66"..Mods[i].name.."|r");
				else
					tip:SetCell(addonPos + i, 2, Mods[i].name);
				end
			end
			
			if( isProfiling ) then
				tip:SetCell(addonPos + i, 3, format_cpu(Mods[i].cpu, Mods[i].cpus));
				tip:SetCell(addonPos + i, 4, Mods[i].cpud == 0 and "" or format_cpu(Mods[i].cpud, Mods[i].cpus));
			end
			
			tip:SetCell(addonPos + i, isProfiling and 5 or 3, format_memory(Mods[i].mem, Mods[i].mems));
			tip:SetCell(addonPos + i, isProfiling and 6 or 4, Mods[i].memd == 0 and "" or format_memory(Mods[i].memd, Mods[i].mems));
		end
	else
		numAddons = -1;
	end
	
	numAddons = numAddons + addonPos;
	
	if( isProfiling ) then
		tip:SetCell(numAddons + 2, 3, format_cpu(TotalCPU, true));
		tip:SetCell(numAddons + 2, 4, format_cpu(TotalCPUDiff, true));
	end
	
	tip:SetCell(numAddons + 2, isProfiling and 5 or 3, format_memory(TotalMemory));
	tip:SetCell(numAddons + 2, isProfiling and 6 or 4, format_memory(TotalMemoryDiff));
	
	tip:SetCell(numAddons + 3, isProfiling and 5 or 3, format_memory(collectgarbage("count") - TotalMemory));
	
	pos = 5;
	if( self.db.TooltipShowFramerate ) then
		tip:SetCell(numAddons + pos, isProfiling and 5 or 3, format_fps(iFramerate), nil, "RIGHT", 2);
		pos = pos + 1;
	end
	
	if( self.db.TooltipShowLatency ) then
		tip:SetCell(numAddons + pos, isProfiling and 5 or 3, format_latency(iLatencyWorld), nil, "RIGHT", 2);
		pos = pos + 1;
	end
	
	if( self.db.TooltipShowStreaming ) then
		tip:SetCell(numAddons + pos, isProfiling and 5 or 3, format_kbs(iUpload).." / "..format_kbs(iDownload), nil, "RIGHT", 2);
		--pos = pos + 1; <- haha, I don't think we need this here. Lets save 0,000001 ns CPU using :D
	end
	
	-- check visibility of tooltip and if yes, update scrollbar
	if( iCPU.db.TooltipUseScroller and tip:IsVisible() ) then
		tip:UpdateScrolling(self.db.TooltipMaxSize);
	end
end