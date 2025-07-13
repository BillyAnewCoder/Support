-- Volcano.lua
-- Full API shim to support missing executor functions using RAPI for thread handling

local RAPI = loadstring(game:HttpGet("https://raw.githubusercontent.com/BillyAnewCoder/FunctionLib/main/RAPI.lua"))()

local Volcano = {}
Volcano.VERSION = "1.3-threaded"
Volcano.API = {}
Volcano.SupportAvailable = {}

------------------------------------------------------------
-- 🔁 replicate_signal (alias for replicatesignal)
------------------------------------------------------------
function Volcano.API.replicate_signal(signal)
    local event = (typeof(signal) == "Instance" and signal:IsA("BindableEvent")) and signal.Event or signal
    if typeof(event) ~= "RBXScriptSignal" then
        warn("[Volcano:replicate_signal] Invalid signal passed")
        return nil
    end

    local wrapper = { _connections = {} }

    function wrapper:Fire(...)
        if typeof(signal) == "Instance" and signal:IsA("BindableEvent") then
            signal:Fire(...)
        elseif typeof(firesignal) == "function" then
            firesignal(event, ...)
        else
            warn("[Volcano:Fire] Cannot fire signal")
        end
    end

    function wrapper:Connect(func)
        local conn = event:Connect(func)
        table.insert(self._connections, conn)
        return conn
    end

    function wrapper:Once(func)
        local conn
        conn = event:Connect(function(...)
            func(...)
            if conn then conn:Disconnect() end
        end)
        table.insert(self._connections, conn)
        return conn
    end

    function wrapper:DisconnectAll()
        for _, conn in ipairs(self._connections) do
            pcall(conn.Disconnect, conn)
        end
        table.clear(self._connections)
    end

    Volcano.SupportAvailable.replicate_signal = "rebuilt+"
    return wrapper
end

------------------------------------------------------------
-- 🧠 get_stack (thread-aware using RAPI)
------------------------------------------------------------
function Volcano.API.get_stack(thread)
    local stack = nil
    if thread and thread ~= coroutine.running() then
        local done = false
        RAPI.run_on_thread(function()
            stack = {}
            local level = 1
            while true do
                local info = debug.getinfo(level, "nSluf")
                if not info then break end
                table.insert(stack, info)
                level += 1
            end
            done = true
        end, thread)
        repeat task.wait() until done
        Volcano.SupportAvailable.get_stack = "threaded"
        return stack
    else
        stack = {}
        local level = 1
        while true do
            local info = debug.getinfo(level, "nSluf")
            if not info then break end
            table.insert(stack, info)
            level += 1
        end
        Volcano.SupportAvailable.get_stack = "local"
        return stack
    end
end

debug.getstack = Volcano.API.get_stack

------------------------------------------------------------
-- 🧬 set_stack (thread-aware using RAPI)
------------------------------------------------------------
function Volcano.API.set_stack(thread, level, key, value)
    local result = false

    local function attempt_set(func)
        if not func or type(func) ~= "function" then
            warn("[Volcano:set_stack] Provided func is invalid.")
            return false
        end

        if type(key) == "number" then
            local name = debug.getupvalue(func, key)
            if name then
                debug.setupvalue(func, key, value)
                return true
            else
                warn("[Volcano:set_stack] getupvalue failed on index", key)
            end
        elseif type(key) == "string" then
            local max = debug.getinfo(func, "u").nups
            for i = 1, max do
                local name = debug.getupvalue(func, i)
                if name == key then
                    debug.setupvalue(func, i, value)
                    return true
                end
            end
        end
        return false
    end

    if thread and thread ~= coroutine.running() then
        local done = false
        RAPI.run_on_thread(function()
            local info = debug.getinfo(thread, level, "f")
            if info and info.func then
                result = attempt_set(info.func)
            else
                warn("[Volcano:set_stack] Failed to get stack info in foreign thread.")
            end
            done = true
        end, thread)
        repeat task.wait() until done
    else
        local info = debug.getinfo(level, "f")
        if info and info.func then
            result = attempt_set(info.func)
        else
            warn("[Volcano:set_stack] Failed to get stack info.")
        end
    end

    if result then
        Volcano.SupportAvailable.set_stack = "rebuilt-upvalue"
    else
        Volcano.SupportAvailable.set_stack = "unsupported-upvalue"
        warn("[Volcano:set_stack] Upvalue '" .. tostring(key) .. "' not found or failed to set.")
    end

    return result
end

debug.setstack = Volcano.API.set_stack
------------------------------------------------------------
-- 📜 get_scripts (filters core scripts, alias for getscripts)
------------------------------------------------------------
function Volcano.API.get_scripts()
    local scripts = {}
    local seen = {}

    for _, s in ipairs(getloadedmodules()) do
        if not s:IsDescendantOf(game:GetService("CoreGui")) then
            seen[s] = true
            table.insert(scripts, s)
        end
    end

    for _, s in ipairs(getrunningscripts()) do
        if not s:IsDescendantOf(game:GetService("CoreGui")) and not seen[s] then
            table.insert(scripts, s)
        end
    end

    Volcano.SupportAvailable.get_scripts = "rebuilt-filtered"
    return scripts
end

getscripts = Volcano.API.get_scripts

------------------------------------------------------------
-- ⚙️ is_scriptable (fixes detection issue with setscriptable)
------------------------------------------------------------
function Volcano.API.is_scriptable(property)
    local inst = Instance.new("Folder")
    local ok, err = pcall(function()
        setscriptable(inst, property, true)
    end)
    inst:Destroy()

    if ok then
        Volcano.SupportAvailable.is_scriptable = "rebuilt-runtime"
    else
        Volcano.SupportAvailable.is_scriptable = "unsupported"
    end

    return ok
end

isscriptable = Volcano.API.is_scriptable

Volcano.replicatesignal = Volcano.API.replicate_signal
Volcano.getstack        = Volcano.API.get_stack
Volcano.setstack        = Volcano.API.set_stack
Volcano.getscripts      = Volcano.API.get_scripts
Volcano.isscriptable    = Volcano.API.is_scriptable

_G.Volcano = Volcano

return Volcano
