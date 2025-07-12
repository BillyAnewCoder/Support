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
    local wrapper = { _connections = {} }
    function wrapper:Fire(...) firesignal(signal, ...) end
    function wrapper:Connect(func)
        local conn = signal:Connect(func)
        table.insert(self._connections, conn)
        return conn
    end
    function wrapper:Once(func)
        local conn
        conn = signal:Connect(function(...)
            func(...)
            if conn then conn:Disconnect() end
        end)
        table.insert(self._connections, conn)
        return conn
    end
    function wrapper:DisconnectAll()
        for _, conn in ipairs(self._connections) do pcall(conn.Disconnect, conn) end
        table.clear(self._connections)
    end
    Volcano.SupportAvailable.replicate_signal = "rebuilt+"
    return wrapper
end
replicatesignal = Volcano.API.replicate_signal

------------------------------------------------------------
-- 🧠 get_stack (rebuilds debug.getstack, supports foreign threads via RAPI.thread)
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

    if coroutine.running() ~= thread then
        local result, done = nil, false
        RAPI.thread(function()
            result = collect_stack()
            done = true
        end)
        repeat task.wait() until done
        Volcano.SupportAvailable.get_stack = "rebuilt-thread"
        return result
    end

    local direct = collect_stack()
    Volcano.SupportAvailable.get_stack = "rebuilt"
    return direct
end
debug.getstack = Volcano.API.get_stack

------------------------------------------------------------
-- 🧬 set_stack (rebuilds debug.setstack for upvalues only)
------------------------------------------------------------
function Volcano.API.set_stack(thread, level, key, value)
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
    for i = 1, math.huge do
        local name = debug.getupvalue(func, i)
        if not name then break end
        if name == key then
            debug.setupvalue(func, i, value)
            Volcano.SupportAvailable.set_stack = "rebuilt-upvalue"
            return true
        end
    end

    warn("[Volcano:set_stack] Upvalue '" .. key .. "' not found.")
    return false
end
debug.setstack = Volcano.API.set_stack

------------------------------------------------------------
-- 📜 get_scripts (alias for getscripts)
------------------------------------------------------------
function Volcano.API.get_scripts()
    local scripts = {}
    for _, s in ipairs(getloadedmodules()) do table.insert(scripts, s) end
    for _, s in ipairs(getrunningscripts()) do table.insert(scripts, s) end
    Volcano.SupportAvailable.get_scripts = "rebuilt"
    return scripts
end
getscripts = Volcano.API.get_scripts

------------------------------------------------------------
-- ⚙️ is_scriptable (alias for isscriptable)
------------------------------------------------------------
function Volcano.API.is_scriptable(property)
    local inst = Instance.new("Folder")
    local ok = pcall(function()
        setscriptable(inst, property, true)
    end)
    inst:Destroy()
    Volcano.SupportAvailable.is_scriptable = ok and "rebuilt-runtime" or "unsupported"
    return ok
end
isscriptable = Volcano.API.is_scriptable

return Volcano
