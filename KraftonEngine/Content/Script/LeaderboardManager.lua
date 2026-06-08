local LeaderboardManager = {}

LeaderboardManager.MaxEntries = 20
LeaderboardManager.Entries = {}
LeaderboardManager.LastRecord = nil
LeaderboardManager.NextRecordId = 1

local function to_number_or_zero(value)
    local number = tonumber(value)
    if number == nil or number < 0 then
        return 0
    end
    return number
end

local function copy_entry(entry)
    if entry == nil then
        return nil
    end

    return {
        Rank = entry.Rank,
        RecordId = entry.RecordId,
        TotalTimeSeconds = entry.TotalTimeSeconds,
        ElapsedTimeSeconds = entry.ElapsedTimeSeconds,
        PlayerName = entry.PlayerName,
        Score = entry.Score,
        ClearReason = entry.ClearReason,
        CreatedAtSeconds = entry.CreatedAtSeconds
    }
end

local function refresh_ranks(entries)
    for index, entry in ipairs(entries) do
        entry.Rank = index
    end
end

function LeaderboardManager:AddClearRecord(record)
    record = record or {}

    local entry = {
        Rank = 0,
        RecordId = self.NextRecordId,
        TotalTimeSeconds = to_number_or_zero(record.TotalTimeSeconds),
        ElapsedTimeSeconds = to_number_or_zero(record.ElapsedTimeSeconds),
        PlayerName = tostring(record.PlayerName or "Player"),
        Score = to_number_or_zero(record.Score),
        ClearReason = tostring(record.ClearReason or "ClearGame"),
        CreatedAtSeconds = to_number_or_zero(record.CreatedAtSeconds)
    }

    self.NextRecordId = self.NextRecordId + 1
    table.insert(self.Entries, entry)

    table.sort(self.Entries, function(a, b)
        if a.TotalTimeSeconds == b.TotalTimeSeconds then
            if a.Score == b.Score then
                return a.RecordId < b.RecordId
            end
            return a.Score > b.Score
        end
        return a.TotalTimeSeconds < b.TotalTimeSeconds
    end)

    while #self.Entries > self.MaxEntries do
        table.remove(self.Entries)
    end

    refresh_ranks(self.Entries)
    self.LastRecord = entry
    return copy_entry(entry)
end

function LeaderboardManager:GetEntryCount()
    return #self.Entries
end

function LeaderboardManager:GetEntry(index)
    index = math.floor(tonumber(index) or 0)
    return copy_entry(self.Entries[index])
end

function LeaderboardManager:GetEntries()
    local result = {}
    for index, entry in ipairs(self.Entries) do
        result[index] = copy_entry(entry)
    end
    return result
end

function LeaderboardManager:GetBestEntry()
    return copy_entry(self.Entries[1])
end

function LeaderboardManager:GetLastRecord()
    return copy_entry(self.LastRecord)
end

function LeaderboardManager:Reset()
    self.Entries = {}
    self.LastRecord = nil
    self.NextRecordId = 1
end

return LeaderboardManager
