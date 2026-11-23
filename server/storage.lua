-- Server-side project storage: JSON files via SaveResourceFile / LoadResourceFile.
-- SaveResourceFile cannot create folders and only returns false, so data/projects and data/takes
-- ship with KEEP files; a failed write is logged loudly with the path.
Storage = {}
local RES = GetCurrentResourceName()
local S = CineSchema

local index = nil          -- { { id, name, created, updated, bytes, shots } ... }
local counter = 0

local function log(fmt, ...)
    print(('^3[%s] ' .. fmt .. '^7'):format(RES, ...))
end

local function writeFile(path, data)
    local ok = SaveResourceFile(RES, path, data, -1)
    if ok == false or ok == nil then
        print(('^1[%s] COULD NOT WRITE %s (does the folder exist? data/projects and data/takes must ship with a KEEP file)^7'):format(RES, path))
        return false
    end
    return true
end

local function projectPath(id) return 'data/projects/' .. id .. '.json' end
local function backupPath(id) return 'data/projects/' .. id .. '.bak.json' end

local function loadIndex()
    if index then return index end
    index = {}
    local raw = LoadResourceFile(RES, 'data/index.json')
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            for i = 1, #decoded do
                local e = decoded[i]
                if type(e) == 'table' and S.Id(e.id) then
                    index[#index + 1] = {
                        id = e.id,
                        name = S.Name(e.name, 'Untitled'),
                        created = math.floor(S.Num(e.created, 0, 4e9, 0)),
                        updated = math.floor(S.Num(e.updated, 0, 4e9, 0)),
                        bytes = math.floor(S.Num(e.bytes, 0, 1e9, 0)),
                        shots = math.floor(S.Num(e.shots, 0, 1e6, 0)),
                    }
                end
            end
        else
            log('data/index.json is not valid JSON, starting with an empty index')
        end
    end
    return index
end

local function saveIndex()
    return writeFile('data/index.json', json.encode(index or {}))
end

local function find(id)
    for i, e in ipairs(loadIndex()) do
        if e.id == id then return e, i end
    end
    return nil
end

function Storage.NewId()
    loadIndex()
    local id
    repeat
        counter = counter + 1
        id = ('p_%d_%d'):format(os.time(), counter)
    until not find(id)
    return id
end

--- Copy of the index for a client list (no internals leaked by reference).
function Storage.List()
    local out = {}
    for _, e in ipairs(loadIndex()) do
        out[#out + 1] = { id = e.id, name = e.name, updated = e.updated, shots = e.shots, bytes = e.bytes }
    end
    table.sort(out, function(a, b) return a.updated > b.updated end)
    return out
end

function Storage.Exists(id)
    return find(id) ~= nil
end

--- Create an empty project. Returns id or nil, reason.
function Storage.Create(name)
    loadIndex()
    if #index >= Config.Storage.MaxProjects then return nil, 'max_projects' end
    local id = Storage.NewId()
    local now = os.time()
    local doc = S.NewProject(id, name, now)
    local enc = json.encode(doc)
    if not writeFile(projectPath(id), enc) then return nil, 'write_failed' end
    index[#index + 1] = { id = id, name = doc.name, created = now, updated = now, bytes = #enc, shots = 0 }
    if not saveIndex() then return nil, 'write_failed' end
    return id, doc
end

--- Read the raw JSON string of a project, or nil.
function Storage.Read(id)
    if not S.Id(id) or not find(id) then return nil end
    local raw = LoadResourceFile(RES, projectPath(id))
    if not raw or raw == '' then return nil end
    return raw
end

--- Validate + write a sanitized project. Returns ok, reason, bytes, savedAt.
function Storage.Save(id, rawJson)
    if not S.Id(id) then return false, 'bad_id' end
    local entry = find(id)
    if not entry then return false, 'unknown_project' end
    if type(rawJson) ~= 'string' or #rawJson == 0 then return false, 'bad_payload' end
    if #rawJson > Config.Storage.MaxProjectBytes then return false, 'too_large' end
    local ok, decoded = pcall(json.decode, rawJson)
    if not ok or type(decoded) ~= 'table' then return false, 'bad_json' end
    local doc, why = S.Project(decoded)
    if not doc then return false, why or 'bad_schema' end
    if doc.id ~= id then return false, 'id_mismatch' end

    local now = os.time()
    doc.created = entry.created
    doc.updated = now
    local enc = json.encode(doc)
    if #enc > Config.Storage.MaxProjectBytes then return false, 'too_large' end

    if Config.Storage.Backup then
        local prev = LoadResourceFile(RES, projectPath(id))
        if prev and prev ~= '' then writeFile(backupPath(id), prev) end
    end
    if not writeFile(projectPath(id), enc) then return false, 'write_failed' end

    entry.name = doc.name
    entry.updated = now
    entry.bytes = #enc
    entry.shots = #doc.shots
    saveIndex()
    return true, nil, #enc, now
end

function Storage.Rename(id, name)
    local entry = find(id)
    if not entry then return false, 'unknown_project' end
    local nm = S.Name(name, nil)
    if not nm then return false, 'bad_name' end
    local raw = Storage.Read(id)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            decoded.name = nm
            local doc = S.Project(decoded)
            if doc then
                if not writeFile(projectPath(id), json.encode(doc)) then return false, 'write_failed' end
            end
        end
    end
    entry.name = nm
    saveIndex()
    return true
end

function Storage.Duplicate(id, newName)
    local entry = find(id)
    if not entry then return nil, 'unknown_project' end
    loadIndex()
    if #index >= Config.Storage.MaxProjects then return nil, 'max_projects' end
    local raw = Storage.Read(id)
    if not raw then return nil, 'missing_file' end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil, 'bad_json' end
    local newId = Storage.NewId()
    decoded.id = newId
    decoded.name = S.Name(newName, nil) or (entry.name .. ' copy')
    local doc = S.Project(decoded)
    if not doc then return nil, 'bad_schema' end
    local now = os.time()
    doc.created, doc.updated = now, now
    local enc = json.encode(doc)
    if not writeFile(projectPath(newId), enc) then return nil, 'write_failed' end
    index[#index + 1] = { id = newId, name = doc.name, created = now, updated = now, bytes = #enc, shots = #doc.shots }
    saveIndex()
    return newId
end

--- Files cannot be removed from a resource folder through the API: the entry leaves the index and
--- the file content is emptied (an empty file is treated as missing).
function Storage.Delete(id)
    local _, i = find(id)
    if not i then return false, 'unknown_project' end
    writeFile(projectPath(id), '')
    writeFile(backupPath(id), '')
    table.remove(index, i)
    saveIndex()
    return true
end
