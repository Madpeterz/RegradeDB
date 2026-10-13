local api = require("api")

local logbook = {}

local REGRADES_DIR = "RegradeDB/Regrades/"
local COUNT_PATH = REGRADES_DIR .. "_count.dat"
-- errors go here instead of chat; only the newest are kept
local ERRORS_PATH = "RegradeDB/errors.dat"
local MAX_ERRORS = 20

-- GRADE_ENCHANT_BROADCAST result codes (same values loss_porn uses)
local RESULT_BREAK = 0
local RESULT_DOWNGRADE = 1
local RESULT_FAIL = 2
local RESULT_SUCCESS = 3
local RESULT_GREAT_SUCCESS = 4

-- result code -> stored name; unknown codes are ignored
local RESULT_NAMES = {
	[RESULT_BREAK] = "destroyed",
	[RESULT_DOWNGRADE] = "downgraded",
	[RESULT_FAIL] = "anchored",
	[RESULT_SUCCESS] = "upgraded",
	[RESULT_GREAT_SUCCESS] = "great_success",
}

-- stored names that count as a loss; the rest count as a success
local LOSSES = {
	destroyed = true,
	downgraded = true,
	anchored = true,
}

-- how a result reads in Describe
local RESULT_VERBS = {
	great_success = "great-success upgraded",
}

-- grade ids as loss_porn names them
local GRADE_NAMES = {
	[1] = "Basic",
	[2] = "Grand",
	[3] = "Rare",
	[4] = "Arcane",
	[5] = "Heroic",
	[6] = "Unique",
	[7] = "Celestial",
	[8] = "Divine",
	[9] = "Epic",
	[10] = "Legendary",
	[11] = "Mythic",
}

local function safeCall(fn)
	local ok, result = pcall(fn)
	if not ok then
		return nil
	end
	return result
end

local function numberToString(value)
	if value == math.floor(value) then
		return string.format("%.0f", value)
	end
	return string.format("%.14g", value)
end

-- ---------------------------------------------------------------------------
-- Time
-- api.Time:GetLocalTime() is unix seconds (UTC).
-- ---------------------------------------------------------------------------

local function currentTime()
	return tonumber(safeCall(function() return api.Time:GetLocalTime() end))
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

-- item links read like "|i<itemType>,...": the item type is the number after "|i"
local function itemTypeFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	return tonumber(string.match(string.sub(link, 3), "^(%d+)"))
end

local function itemName(itemType)
	if itemType == nil then
		return nil
	end
	local info = safeCall(function() return api.Item:GetItemInfoByType(itemType) end)
	if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
		return info.name
	end
	return nil
end

local function gradeName(gradeId)
	return GRADE_NAMES[tonumber(gradeId)]
end

-- ---------------------------------------------------------------------------
-- Storage
-- Regrades are split into one file per first two letters of the character (as PlayerDB does),
-- e.g. al.dat; names that don't start with two letters/digits go to _other.dat. _count.dat keeps the totals.
-- ---------------------------------------------------------------------------

local function characterPath(name)
	local prefix = string.lower(string.sub(name, 1, 2))
	if not string.find(prefix, "^%w%w$") then
		prefix = "_other"
	end
	return REGRADES_DIR .. prefix .. ".dat"
end

local function readList(path)
	local list = api.File:Read(path)
	if type(list) ~= "table" then
		return {}
	end
	return list
end

local function readCounts()
	local stats = api.File:Read(COUNT_PATH)
	local counts = { regrades = 0, losses = 0, successes = 0 }
	for _, name in pairs(RESULT_NAMES) do
		counts[name] = 0
	end
	if type(stats) ~= "table" then
		return counts
	end
	for key in pairs(counts) do
		counts[key] = tonumber(stats[key]) or 0
	end
	return counts
end

local function writeCounts(counts)
	local out = {}
	for key, value in pairs(counts) do
		out[key] = numberToString(value)
	end
	api.File:Write(COUNT_PATH, out)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- Saves one GRADE_ENCHANT_BROADCAST, failed or not. Returns the saved entry, or nil.
function logbook.LogRegrade(characterName, resultCode, itemLink, oldGrade, newGrade)
	local result = RESULT_NAMES[tonumber(resultCode)]
	if result == nil then
		logbook.LogError("unknown regrade result " .. tostring(resultCode) .. " by " .. tostring(characterName))
		return nil
	end
	local seen = currentTime()
	if seen == nil then
		logbook.LogError("no local time, regrade by " .. tostring(characterName) .. " not saved")
		return nil
	end
	local itemType = itemTypeFromLink(itemLink)

	local entry = {
		character = tostring(characterName),
		result = result,
		item = itemName(itemType),
		old_grade = gradeName(oldGrade),
		new_grade = gradeName(newGrade),
		old_grade_id = tonumber(oldGrade) and numberToString(tonumber(oldGrade)) or nil,
		new_grade_id = tonumber(newGrade) and numberToString(tonumber(newGrade)) or nil,
		time = numberToString(seen),
	}

	local path = characterPath(entry.character)
	local list = readList(path)
	list[#list + 1] = entry
	api.File:Write(path, list)

	local counts = readCounts()
	counts.regrades = counts.regrades + 1
	if LOSSES[result] then
		counts.losses = counts.losses + 1
	else
		counts.successes = counts.successes + 1
	end
	counts[result] = counts[result] + 1
	writeCounts(counts)
	return entry
end

logbook.DESTROYED = RESULT_NAMES[RESULT_BREAK]

function logbook.IsLoss(entry)
	return LOSSES[entry.result] == true
end

-- short description of a saved entry, e.g. "Bob destroyed Hiram Cloak (Celestial)"
-- or "Bob upgraded Hiram Cloak (Celestial -> Divine)"
function logbook.Describe(entry)
	local item = entry.item or "an item"
	local grade = entry.old_grade
	if grade ~= nil and entry.new_grade ~= nil and entry.new_grade ~= grade then
		grade = grade .. " -> " .. entry.new_grade
	end
	return entry.character .. " " .. (RESULT_VERBS[entry.result] or entry.result) .. " " .. item
		.. (grade and (" (" .. grade .. ")") or "")
end

-- keeps the newest MAX_ERRORS messages in ERRORS_PATH
function logbook.LogError(message)
	local list = readList(ERRORS_PATH)
	local seen = currentTime()
	list[#list + 1] = {
		time = seen and numberToString(seen) or nil,
		message = tostring(message),
	}
	while #list > MAX_ERRORS do
		table.remove(list, 1)
	end
	api.File:Write(ERRORS_PATH, list)
end

-- totals: regrades, losses, successes, and one per result name
function logbook.Counts()
	return readCounts()
end

return logbook
