-- Volcano.lua
-- Full API shim to support missing executor functions using RAPI for thread handling

local RAPI = loadstring(game:HttpGet("https://raw.githubusercontent.com/BillyAnewCoder/FunctionLib/main/RAPI.lua"))()

local Volcano = {}
Volcano.VERSION = "1.2"
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
-- 🧠 get_stack (rebuilds debug.getstack, supports foreign threads via RAPI.run_on_thread)
------------------------------------------------------------
function Volcano.API.get_stack(thread)
    local function collect_stack()
        local stack = {}
        local level = 1
        while true do
            local info = debug.getinfo(level, "nSluf")
            if not info then break end
            table.insert(stack, info)
            level += 1
        end
        return stack
    end

    if thread and coroutine.running() ~= thread then
        local result = nil
        local done = false

        RAPI.run_on_thread(function()
            result = collect_stack()
            done = true
        end)

        repeat task.wait() until done
        Volcano.SupportAvailable.get_stack = "rebuilt-foreign"
        return result
    else
        local stack = collect_stack()
        Volcano.SupportAvailable.get_stack = "rebuilt-local"
        return stack
    end
end

debug.getstack = Volcano.API.get_stack

------------------------------------------------------------
-- 🧬 set_stack (rebuilds debug.setstack for upvalues only)
------------------------------------------------------------
function Volcano.API.set_stack(thread, level, keyOrIndex, value)
    if coroutine.running() ~= thread then
        warn("[Volcano:set_stack] Cannot modify foreign thread.")
        Volcano.SupportAvailable.set_stack = "unsupported"
        return false
    end

    local info = debug.getinfo(level + 1, "f")
    if not info or type(info.func) ~= "function" then
        warn("[Volcano:set_stack] Invalid stack level.")
        return false
    end

    local func = info.func
    local success = false

    for i = 1, debug.getinfo(func, "u").nups do
        local name = debug.getupvalue(func, i)
        if not name then break end

        if (type(keyOrIndex) == "number" and i == keyOrIndex) or (type(keyOrIndex) == "string" and name == keyOrIndex) then
            debug.setupvalue(func, i, value)
            success = true
            break
        end
    end

    if success then
        Volcano.SupportAvailable.set_stack = "rebuilt-upvalue"
    else
        Volcano.SupportAvailable.set_stack = "unsupported-upvalue"
        warn("[Volcano:set_stack] Upvalue '" .. tostring(keyOrIndex) .. "' not found.")
    end

    return success
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

return Volcano
