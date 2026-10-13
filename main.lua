-- RegradeDB Main Module
local api = require("api")
local logbook = require("RegradeDB/logbook")
local statusdot = require("RegradeDB/statusdot")

local RegradeDB = {
	name = "RegradeDB",
	author = "Madpeter",
	version = "1.2.0",
	desc = "Logs regrades: who upgraded, destroyed, downgraded or anchored which item"
}

-- errors never reach chat; they are kept in RegradeDB/errors.dat
local function runSafe(fn)
	local ok, result = pcall(fn)
	if not ok then
		pcall(logbook.LogError, result)
		return nil
	end
	return result
end

local function onRegrade(characterName, resultCode, itemLink, oldGrade, newGrade)
	local entry = runSafe(function()
		return logbook.LogRegrade(characterName, resultCode, itemLink, oldGrade, newGrade)
	end)
	if entry == nil then
		return -- not saved (error already logged)
	end
	if not logbook.IsLoss(entry) then
		return -- successes are logged but leave the light alone
	end
	-- a UI problem must never stop logging
	runSafe(function()
		local state = statusdot.LOST
		if entry.result == logbook.DESTROYED then
			state = statusdot.DESTROYED
		end
		statusdot.MarkLoss(state, logbook.Describe(entry))
	end)
end

-- Addon initialization
local function OnLoad()
	-- the only chat line the addon writes
	local counts = runSafe(logbook.Counts)
	api.Log:Info("[" .. RegradeDB.name .. "] Starting version " .. RegradeDB.version
		.. (counts and (", " .. counts.regrades .. " regrades logged (" .. counts.losses .. " losses)") or ""))
	-- hidden window, only used to receive game events
	RegradeDB.eventWindow = api.Interface:CreateEmptyWindow("RegradeDBEvents")
	RegradeDB.eventWindow:Show(false)
	runSafe(function()
		statusdot.Create(logbook.Counts)
	end)
	-- attach events
	function RegradeDB:EventListener(event, ...)
		if event == "GRADE_ENCHANT_BROADCAST" then
			-- same arguments loss_porn reads
			local characterName, resultCode, itemLink, oldGrade, newGrade = ...
			onRegrade(characterName, resultCode, itemLink, oldGrade, newGrade)
		end
	end
	RegradeDB.eventWindow:SetHandler("OnEvent", RegradeDB.EventListener)
	RegradeDB.eventWindow:RegisterEvent("GRADE_ENCHANT_BROADCAST")
end

-- Addon cleanup
local function OnUnload()
	-- Unregister events
	if RegradeDB.eventWindow ~= nil then
		RegradeDB.eventWindow:ReleaseHandler("OnEvent")
		api.Interface:Free(RegradeDB.eventWindow)
		RegradeDB.eventWindow = nil
	end
	runSafe(statusdot.Free)
end

RegradeDB.OnSettingToggle = nil

RegradeDB.OnLoad = OnLoad
RegradeDB.OnUnload = OnUnload

return RegradeDB
