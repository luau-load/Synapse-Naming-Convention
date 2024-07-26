--[[
     _____ _   _ _____ 
    /  ___| \ | /  __ \
    \ `--.|  \| | /  \/
     `--. \ . ` | |    
    /\__/ / |\  | \__/\
    \____/\_| \_/\____/
                   
    Written at 25.07.24
]]

local FORCE_CONSOLE_OUTPUT = getgenv().FORCE_CONSOLE_OUTPUT
if FORCE_CONSOLE_OUTPUT == nil then
    FORCE_CONSOLE_OUTPUT = false
end

local EXECUTE_IN_ORDER = getgenv().EXECUTE_IN_ORDER
if EXECUTE_IN_ORDER == nil then
    EXECUTE_IN_ORDER = false
end

local print = print
local warn = warn

local output_file = "SNC-Results.txt"
if writefile and appendfile and not FORCE_CONSOLE_OUTPUT then
    writefile(output_file, "")
    function print(...)
        local t = {...}
        for i = 1, #t do
            t[i] = tostring(t[i])
        end
        appendfile(output_file, "[INFO] " .. table.concat(t, " ") .. "\n")
    end

    function warn(...)
        local t = {...}
        for i = 1, #t do
            t[i] = tostring(t[i])
        end
        appendfile(output_file, "[WARN] " .. table.concat(t, " ") .. "\n")
    end
end

local running = 0
local count, passed, missing = 0, 0, 0

local env = getfenv(0)
local function getGlobal(list)
    local f, m, ff = nil, {}, {}
    for _, n in pairs(list) do
        local s = n:split(".")

        local i = 1
        local g = env
        while g and s[i] do
            g = g[s[i]]
            i += 1
        end

        if g then
            f = g
            table.insert(ff, n)
        else
            table.insert(m, n)
        end
    end
    return f, m, ff
end

local test
if EXECUTE_IN_ORDER then
    function test(a1, callback)
        count += 1
        running += 1
        a1 = type(a1) == "table" and a1 or {a1}
        local f, m, ff = getGlobal(a1)
        if f then
            if callback then
                local success, msg
                local ran = false
                task.spawn(function()
                    success, msg = pcall(callback, f)
                    ran = true
                end)
                local start = os.clock()
                while not ran and os.clock() - start < 10 do
                    task.wait(0.1)
                end
                if not ran then
                    warn("⛔ " .. table.concat(ff, ", ") .. " timeout 10 seconds")
                elseif success then
                    passed += 1
                    print("✅ " .. table.concat(ff, ", ") .. " " .. (msg or ""))
                else
                    warn("⛔ " .. table.concat(ff, ", ") .. " " .. msg)
                end
            else
                passed += 1
            end
        else
            warn("⛔ " .. table.concat(a1, ", "))
        end
        if #m > 0 then
            warn("⚠️ " .. table.concat(m, ", "))
            missing += #m
        end
        running -= 1
    end
else
    function test(a1, callback)
        task.spawn(function()
            count += 1
            running += 1
            a1 = type(a1) == "table" and a1 or {a1}
            local f, m, ff = getGlobal(a1)
            if f then
                if callback then
                    local success, msg
                    local ran = false
                    task.spawn(function()
                        success, msg = pcall(callback, f)
                        ran = true
                    end)
                    local start = os.clock()
                    while not ran and os.clock() - start < 10 do
                        task.wait(0.1)
                    end
                    if not ran then
                        warn("⛔ " .. table.concat(ff, ", ") .. " timeout 10 seconds")
                    elseif success then
                        passed += 1
                        print("✅ " .. table.concat(ff, ", ") .. " " .. (msg or ""))
                    else
                        warn("⛔ " .. table.concat(ff, ", ") .. " " .. msg)
                    end
                else
                    passed += 1
                end
            else
                warn("⛔ " .. table.concat(a1, ", "))
            end
            if #m > 0 then
                warn("⚠️ " .. table.concat(m, ", "))
                missing += #m
            end
            running -= 1
        end)
    end
end

-- Environment APIs

test("getgenv", function(f)
    local env = f()
    assert(env.getgenv, "environment doesnt contain getgenv")
end)

test("getrenv", function(f)
    local renv = f()
    assert(renv._G ~= env._G, "env._G is identical to renv._G")
    assert(renv.shared ~= env.shared, "env.shared is identical to renv.shared")
end)

test({"getreg", "debug.getregistry"}, function(f)
    local reg = f()
    for i, v in pairs(reg) do
        if type(v) == "thread" then
            return
        end
    end
    error("registry doesnt contain usual value type")
end)

test("getgc", function(f)
    local gc = f(true)
    for i, v in pairs(gc) do
        if type(v) == "function" or type(v) == "table" then
            return
        end
    end
    error("gc doesnt contain usual value type")
end)

test("getinstances", function(f)
    local instances = f()
    assert(typeof(instances[1]) == "Instance", "first value in instances is not an Instance")
end)

test("getnilinstances", function(f)
    local instances = f()
    assert(typeof(instances[1]) == "Instance", "first value in nil instances is not an Instance")
    assert(not instances[1].Parent, "first value in nil instances is not parented to nil")
end)

test("getscripts", function(f)
    local instances = f()
    assert(typeof(instances[1]) == "Instance", "first value in scripts is not an Instance")

    assert(instances[1]:IsA("LuaSourceContainer"), "first value in scripts is not a script")
end)

test("getloadedmodules", function(f)
    local instances = f()
    assert(typeof(instances[1]) == "Instance", "first value in loaded module scripts is not an Instance")
    assert(instances[1]:IsA("ModuleScript"), "first value in loaded module scripts is not a module script")
end)

test("fireclickdetector", function(f)
    local click_detector = Instance.new("ClickDetector")

    local is_valid = false
    click_detector.MouseClick:Once(function(plr)
        is_valid = plr == game:GetService("Players").LocalPlayer
    end)
    f(click_detector, "MouseClick")
    task.wait(0.1)

    assert(is_valid, "did not fire ClickDetector.MouseClick even locally")
end)

test("fireproximityprompt", function(f)
    local proximity = Instance.new("ProximityPrompt", Instance.new("Part", workspace))

    local is_valid = false
    proximity.Triggered:Once(function()
        is_valid = true
    end)
    f(proximity)
    task.wait(0.1)

    proximity.Parent:Destroy()

    assert(is_valid, "did not fire ProximityPrompt.Triggered even locally")
end)

test("firetouchinterest", function(f)
    local part1 = Instance.new("Part")
    local part2 = Instance.new("Part")
    part1.Position = Vector3.new(10, 0, 0)
    part2.Position = Vector3.new(-10, 0, 0)
    part1.Parent = workspace
    part2.Parent = workspace

    local is_valid = false
    part1.Touched:Connect(function(part)
        if part == part2 then
            is_valid = true
        end
    end)

    f(part1, part2, true)
    task.wait(0.1)
    f(part1, part2, false)
    task.wait(0.2)

    part1:Destroy()
    part2:Destroy()

    assert(is_valid, "did not fire Part.Touched even locally")
end)

-- Filessystem APIs

test({"readfile", "readfileasync"}, function(f)
    (writefile or writefileasync)("rf.test", "test")
    assert(f("rf.test") == "test", "did not return \"test\"")
    if delfile then
        delfile("rf.test")
    end
end)

test({"writefile", "writefileasync"}, function(f)
    f("wf.test", "test")
    assert((readfile or readfileasync)("wf.test") == "test", "did not write \"test\"")
    if delfile then
        delfile("wf.test")
    end
end)

test({"appendfile", "appendfileasync"}, function(f)
    (writefile or writefileasync)("af.test", "te")
    f("af.test", "st")
    assert((readfile or readfileasync)("af.test") == "test", "did not write \"test\"")
    if delfile then
        delfile("af.test")
    end
end)

test({"loadfile", "loadfileasync"}, function(f)
    (writefile or writefileasync)("lf.test", "return \"test\"")
    assert(f("lf.test")() == "test", "did not return \"test\"")
    if delfile then
        delfile("lf.test")
    end
end)

test("listfiles", function(f)
    makefolder("lf")
;   (writefile or writefileasync)("lf/test1", "test1")
;   (writefile or writefileasync)("lf/test2", "test2")
    local test1, test2 = false, false
    for i, v in pairs(f("lf")) do
        if v:find("test1") then
            test1 = true
        elseif v:find("test2") then
            test2 = true
        end
    end
    assert(test1, "did not list lf/test1 as a file")
    assert(test2, "did not list lf/test2 as a file")
    if delfolder then
        delfolder("lf")
    end
end)

test("isfile", function(f)
    (writefile or writefileasync)("if.test", "test")
    assert(f("if.test"), "did not return true for a file")
    if delfile then
        delfile("if.test")
    end
end)

test("isfolder", function(f)
    makefolder("if")
    assert(f("if"), "did not return true for a folder")
    if delfolder then
        delfolder("if")
    end
end)

test("makefolder", function(f)
    f("mf")
    assert(isfolder("mf"), "did not create a folder")
    if delfolder then
        delfolder("mf")
    end
end)

test("delfolder", function(f)
    makefolder("df")
    f("df")
    assert(not isfolder("df"), "did not delete the folder")
end)

test("delfile", function(f)
    (writefile or writefileasync)("df.test", "test")
    f("df.test")
    assert(not isfile("df.test"), "did not delete the file")
end)

test({"getcustomasset", "getsynasset"}, function(f)
    (writefile or writefileasync)("gca.test", "test")
    assert(f("gca.test"):find("rbxasset://") == 1, "did not return \"Content\"")
    if delfile then
        delfile("gca.test")
    end
end)

test("saveinstance")

test("saveplace")

-- Hooking APIs

test("setstackhidden", function(f)
    local curr_func = debug.info(1, "f")
    f(curr_func, true)
    assert(debug.info(1, "f") ~= curr_func, "did not hide current function")
end)

test("newcclosure", function(f)
    local cc = f(function(arg)
        task.wait()
        return arg
    end)
    assert(debug.info(cc, "s") == "[C]", "did not return a cclosure")
    assert(cc("test") == "test", "did not return correct value")
end)

test("clonefunction", function(f)
    local function f1()
        return "test"
    end
    local cf1 = f(f1)
    assert(f1 ~= cf1, "functions should not match")
    assert(cf1() == "test", "cloned function did not return correct value")
    if newcclosure then
        f1 = newcclosure(f1)
        cf1 = f(f1)
        assert(f1 ~= cf1, "functions should not match")
        assert(cf1() == "test", "cloned function did not return correct value")
    else
        return "skipped cclosure check"
    end
end)

test({"hookfunction", "replaceclosure"}, function(f)
    local function f1()
        return "not test"
    end
    local function f2()
        return "test"
    end
    local o = f(f1, f2)
    assert(f1() == "test", "did not hook function")
    assert(o() == "not test", "original function did not return correct value")
    if newcclosure then
        local function f1()
            return "not test"
        end
        local function f2()
            return "test"
        end
        f1 = newcclosure(f1)
        f2 = newcclosure(f2)
        o = f(f1, f2)
        assert(f1() == "test", "did not hook function")
        assert(o() == "not test", "original function did not return correct value")
    else
        return "skipped cclosure check"
    end
end)

test("hookproto", function(f)
    local function f1()
        local function f2()
            return "not test"
        end
        return f2()
    end
    local function f2()
        return "test"
    end
    local p = debug.getproto(f1, 1)
    f(p, f2)
    assert(f1() == "test", "did not hook proto")
end)

test("hookmetamethod", function(f)
    local u = newproxy(true)
    local mt = getmetatable(u)
    local function f1()
        return "not test"
    end
    mt.__index = f1
    mt.__metatable = "nope"

    local function f2()
        return "test"
    end
    local o = f(u, "__index", f2)
    assert(u[1] == "test", "did not hook metamethod")
    assert(o(u, 1) == "not test", "orignal metamethod did not return correct value")
    assert(mt.__index ~= f2, "dangerous hookmetamethod")
end)

test("restorefunction", function(f)
    local function f1()
        return "test"
    end
    local function f2()
        return "not test"
    end
    local o = (hookfunction or replaceclosure)(f1, f2)
    assert(f1() == "not test", "did not hook function")
    assert(o() == "test", "original function did not return correct value")
    f(f1)
    assert(f1() == "test", "did not restore function")
    if newcclosure then
        local function f1()
            return "test"
        end
        local function f2()
            return "not test"
        end
        f1 = newcclosure(f1)
        f2 = newcclosure(f2)
        o = (hookfunction or replaceclosure)(f1, f2)
        assert(f1() == "not test", "did not hook function")
        assert(o() == "test", "original function did not return correct value")
        f(f1)
        assert(f1() == "test", "did not restore function")
    else
        return "skipped cclosure check"
    end
end)

test("isfunctionhooked", function(f)
    local function f1()
        return "not test"
    end
    local function f2()
        return "test"
    end
    local o = (hookfunction or replaceclosure)(f1, f2)
    assert(f1() == "test", "did not hook function")
    assert(o() == "not test", "original function did not return correct value")
    assert(isfunctionhooked(f1), "did not return true for a hooked function")
end)

test("restoreproto", function(f)
    local function f1()
        local function f2()
            return "not test"
        end
        return f2()
    end
    local function f2()
        return "test"
    end
    local p = debug.getproto(f1, 1)
    hookproto(p, f2)
    assert(f1() == "test", "did not hook proto")
    f(p)
    assert(f1() == "not test", "did not restore proto")
end)

test("hooksignal", function(f)
    local part = Instance.new("Part")
    local ran = false
    local success, message = true, ""
    part.Changed:Connect(function(prop)
        if success and prop ~= "test" then
            success = false
            message = "did not hook property argument"
        end
    end)
    f(part.Changed, function(info, prop)
        ran = true
        if success then
            if type(info) ~= "table" and type(info) ~= "userdata" then
                success = false
                message = "did not pass info table as first argument"
                return
            end
            if not info.Connection then
                success = false
                message = "info table did not contain Connection"
                return
            end
            if not info.Function then
                success = false
                message = "info table did not contain Function"
                return
            end
            if not info.Index then
                success = false
                message = "info table did not contain Index"
                return
            end
            if prop ~= "Name" then
                success = false
                message = "invalid second argument"
                return 
            end
        end
        return true, "test"
    end)
    part.Name = ""
    task.wait(0.1)
    assert(ran, "did not call the signal hook")
    assert(success, message)
end)

test("restoresignal", function(f)
    local part = Instance.new("Part")
    local ran = false
    local success, message = true
    part.Changed:Connect(function(prop)
        if success and prop ~= "test" then
            success = false
            message = "did not hook property argument"
        end
    end)
    hooksignal(part.Changed, function(info, prop)
        ran = true
        if success then
            if type(info) ~= "table" and type(info) ~= "userdata" then
                success = false
                message = "did not pass info table as first argument"
                return
            end
            if not info.Connection then
                success = false
                message = "info table did not contain Connection"
                return
            end
            if not info.Function then
                success = false
                message = "info table did not contain Function"
                return
            end
            if not info.Index then
                success = false
                message = "info table did not contain Index"
                return
            end
            if prop ~= "Name" then
                success = false
                message = "invalid second argument"
                return 
            end
        end
        return true, "test"
    end)
    part.Name = ""
    task.wait(0.1)
    assert(ran, "did not call the signal hook")
    assert(success, message)
    f(part.Changed)
    ran = false
    part.Name = ""
    assert(not ran, "did not restore hooked signal")
end)

test("issignalhooked", function(f)
    local part = Instance.new("Part")
    hooksignal(part.Changed, function(...)
        return true, ...
    end)
    assert(f(part.Changed), "did not return true for hooked signal")
end)

-- Input APIs

test("iswindowactive", function(f)
    assert(type(f()) == "boolean", "did not return a boolean")
end)

test("keypress")

test("keyrelease")

test("keyclick")

test("mouse1press")

test("mouse1release")

test("mouse1click")

test("mouse2press")

test("mouse2release")

test("mouse2click")

test("mousescroll")

test("mousemoverel")

test("mousemoveabs")

test("iskeydown")

test("iskeytoggled")

-- Miscellaneous APIs

test({"setclipboard", "setrbxclipboard"})

test("setfflag")

test("getfflag")

test({"identifyexecutor", "getexecutorname"}, function(f)
    local name, version = f()
    assert(name, "did not return executor name")
    if not version then
        return "did not return executor version"
    end
end)

test("messagebox")

test("gethui", function(f)
    assert(typeof(f()) == "Instance", "did not return an Instance")
end)

test("cloneref", function(f)
    local part = Instance.new("Part")
    local cpart = cloneref(part)
    assert(part ~= cpart, "cloned reference should not match")
    cpart.Name = "test"
    assert(part.Name == "test", "did not set Name property")
end)

test("queue_on_teleport")

test("clear_teleport_queue")

test({"getidentity", "getthreadidentity", "getthreadcontext", "get_thread_identity"}, function(f)
    assert(type(f()) == "number", "did not return a number")
end)

test({"setidentity", "getthreadidentity", "setthreadcontext", "set_thread_identity"}, function(f)
    local o = (getidentity or getthreadidentity or getthreadcontext or get_thread_identity)()
    local ti = o == 7 and 8 or 7
    f(ti)
    assert((getidentity or getthreadidentity or getthreadcontext or get_thread_identity)() == ti, "did not change identity")
    local success = pcall(function()
        return game:GetService("Players").LocalPlayer:GetGameSessionID()
    end)
    assert(success, "did not change capabilities")
    f(o)
end)

test("protect_gui")

test("unprotect_gui")

-- Network APIs

test("isnetworkowner", function(f)
    local part = Instance.new("Part")
    assert(type(f(part)) == "boolean", "did not return a boolean")
end)

-- Reflection APIs

test("setscriptable", function(f)
    local fire = Instance.new("Fire")
    local was = f(fire, "size_xml", true)
    assert(not was, "did not return false for non scriptable property")
    assert(type(fire.size_xml) == "number", "property did not return a number")
    local fire1 = Instance.new("Fire")
    local success = pcall(function()
        return fire1.size_xml
    end)
    assert(not success, "setscriptable applies to every instance")
    f(fire, "size_xml", false)
end)

test("gethiddenproperty", function(f)
    local fire = Instance.new("Fire")
    assert(type(f(fire, "size_xml")) == "number", "property did not return a number")
end)

test("sethiddenproperty", function(f)
    local fire = Instance.new("Fire")
    f(fire, "size_xml", 0xFB1)
    assert(gethiddenproperty(fire, "size_xml") == 0xFB1, "did not set property")
end)

test("getproperties", function(f)
    for i, v in pairs(f(game)) do
        if v == "PlaceId" then
            return
        end
    end
    error("properties did not contain PlaceId")
end)

test("gethiddenproperties", function(f)
    for i, v in pairs(f(game)) do
        if v == "UniqueId" then
            return
        end
    end
    error("hidden properties did not contain UniqueId")
end)

-- Script APIs

test("loadstring", function(f)
    assert(f("return ...")("test") == "test", "did not return correct value")
end)

test("checkcaller", function(f)
    assert(f(), "did not return true")
end)

test("checkcallstack", function(f)
    assert(f(), "did not return true")
end)

test({"isexecutorclosure", "is_our_closure", "checkclosure", "issynapsefunction"}, function(f)
    assert(f(f), "did not return true for itself")
    assert(f(function()end), "did not return true for lua function")
end)

test("islclosure", function(f)
    assert(f(function()end), "did not return true for lua function")
    if newcclosure then
        assert(not f(newcclosure(function()end)), "did not return false for cclosure")
    else
        return "skipped cclosure check"
    end
end)

test("decompile")

test("getscriptthread", function(f)
    for i, v in pairs(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerScripts"):GetDescendants()) do
        if v:IsA("LocalScript") and v.Enabled then
            assert(type(f(v)) == "thread", "did not return a thread")
            break
        end
    end
end)

test("getsenv", function(f)
    for i, v in pairs(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerScripts"):GetDescendants()) do
        if v:IsA("LocalScript") and v.Enabled then
            local e = f(v)
            assert(type(e) == "table", "did not return environment")
            assert(e.script == v, "incorrect environment script field")
            break
        end
    end
end)

test({"getscriptclosure", "getscriptfunction"}, function(f)
    for i, v in pairs(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerScripts"):GetDescendants()) do
        if v:IsA("LocalScript") and v.Enabled then
            assert(type(f(v)) == "function", "did not return a function")
            break
        end
    end
end)

test({"getscriptbytecode", "dumpbytecode"}, function(f)
    for i, v in pairs(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerScripts"):GetDescendants()) do
        if v:IsA("LocalScript") and v.Enabled then
            local b = f(v)
            assert(type(b) == "string" and b:byte(1, 1) >= 3 and b:byte(1, 1) <= 10--[[will break when luau bytecode version 11 will be created.]], "did not return valid bytecode")
            break
        end
    end
end)

test("getscripthash", function(f)
    for i, v in pairs(game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerScripts"):GetDescendants()) do
        if v:IsA("LocalScript") and v.Enabled then
            assert(type(f(v)) == "string", "did not return a hash")
            break
        end
    end
end)

test("getfunctionhash", function(f)
    local function f1()
        return "test"
    end
    local fc = f1
    local function f1()
        return "test"
    end
    assert(type(f(f1)) == "string", "did not return a hash")
    assert(f(fc) == f(f1), "did not return same hashes")
    assert(f(fc) ~= f(f), "returned same hashes for different functions")
end)

test("getcallingscript")

test("getconnections", function(f)
    local event = Instance.new("BindableEvent")
    local ran = false
    local function f1()
        ran = true
    end
    event.Event:Connect(f1)
    local con = f(event.Event)[1]
    assert(type(con) == "table" or type(con) == "userdata", "did not return table of tables or userdatas")
    assert(con.Function == f1, "invalid Function field")
    assert(con.Thread == coroutine.running(), "invalid Thread field")
    assert(con.Enabled, "invalid Enabled field")
    assert(type(con.ForeignState) == "boolean", "invalid ForeignState field")
    assert(con.LuaConnection, "invalid LuaConnection field")

    con:Fire()
    task.wait()
    assert(ran, "Fire did not fire the connection")
    ran = false

    con:Defer()
    task.wait()
    assert(ran, "Defer did not fire the connection")
    ran = false

    con:Disable()
    event:Fire()
    task.wait()
    assert(not ran, "Disable did not disable the connection")

    con:Enable()
    event:Fire()
    task.wait()
    assert(ran, "Enable did not enable the connection")
end)

test("firesignal", function()
    local event = Instance.new("BindableEvent")
    local ran = false
    event.Event:Connect(function()
        ran = true
    end)
    firesignal(event.Event)
    task.wait()
    assert(ran, "did not fire the connection")
end)

test("cfiresignal")

test("replicatesignal")

test("cansignalreplicate", function(f)
    assert(type(f(game.Changed)) == "boolean", "did not return a boolean")
end)

-- Table APIs

test({"getrawmetatable", "debug.getmetatable"}, function(f)
    local mt = {
        __metatable = "nope"
    }
    local t = {}
    setmetatable(t, mt)
    assert(f(t) == mt, "did not return correct metatable")
end)

test({"setrawmetatable", "debug.setmetatable"}, function(f)
    local mt = {
        __metatable = "not test"
    }
    local t = {}
    setmetatable(t, mt)
    f(t, {
        __metatable = "test"
    })
    assert(getmetatable(t) == "test", "did not set metatable")
end)

test("setreadonly", function(f)
    local t = {}
    f(t, true)
    local success = pcall(function()
        t[1] = true
    end)
    assert(not success, "did not set readonly to true")
    f(t, false)
    success = pcall(function()
        t[1] = true
    end)
    assert(success, "did not set readonly to false")
end)

test("setuntouched")

test("isuntouched", function(f)
    assert(not f({}), "returned true for a normal table")
end)

test("makewriteable", function(f)
    local t = {}
    table.freeze(t)
    local success = pcall(function()
        t[1] = true
    end)
    assert(not success, "did not set readonly to true")
    f(t)
    success = pcall(function()
        t[1] = true
    end)
    assert(success, "did not set readonly to false")
end)

test("makereadonly", function(f)
    local t = {}
    f(t)
    local success = pcall(function()
        t[1] = true
    end)
    assert(not success, "did not set readonly to true")
end)

-- Websocket Library

test("WebSocket.connect", function(f)
    local websocket = f("ws://echo.websocket.events")
    assert(type(websocket) == "table" or type(websocket) == "userdata", "did not return a table or userdata")
    assert(websocket.Url == "ws://echo.websocket.events")
    assert(type(websocket.Send) == "function", "invalid Send field")
    websocket:Send("hello")
    
    assert(type(websocket.OnMessage) == "table" or type(websocket.OnMessage) == "userdata", "invalid OnMessage field")
    assert(type(websocket.OnClose) == "table" or type(websocket.OnClose) == "userdata", "invalid OnClose field")
    local ran = false 
    websocket.OnClose:Connect(function()
        ran = true
    end)

    assert(type(websocket.Close) == "function", "invalid Close field")
    websocket:Close()

    task.wait()
    assert(ran, "did not fire OnClose after closing websocket")
end)

-- Drawing Library

test("Drawing.new", function(f)
    local obj = f("Line")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Line object")
    obj:Remove()
    obj = f("Text")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Text object")
    obj:Remove()
    obj = f("Image")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Image object")
    obj:Remove()
    obj = f("Circle")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Circle object")
    obj:Remove()
    obj = f("Square")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Square object")
    obj:Remove()
    obj = f("Triangle")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Triangle object")
    obj:Remove()
    obj = f("Quad")
    assert(type(obj) == "table" or type(obj) == "userdata", "invalid Quad object")
    obj:Remove()
end)

-- Console APIs

test({"rconsoleprint", "printconsole"})

test("rconsoleinfo")

test("rconsolewarn")

test("rconsoleerr")

test({"rconsoleclear", "clearconsole"})

test("rconsolename")

test("rconsoleinput")

-- HTTP APIs

test({"request", "http_request", "http.request"}, function(f)
    local res = f({
        Url = "https://httpbin.org/user-agent",
        Method = "GET"
    })
    assert(res.StatusCode == 200, "request failed")
    assert(res.Success, "request failed")
    assert(type(res.Body) == "string", "invalid Body field")
    assert(type(res.Headers) == "table", "invalid Headers field")
    assert(type(res.Cookies) == "table", "invalid Cookies field")

    local data = game:GetService("HttpService"):JSONDecode(res.Body)
    if not data then
        return "failed to parse json"
    end
    if data["user-agent"] then
        return "user-agent: " .. data["user-agent"]
    end
end)

-- Synapse Library

test("run_on_actor", function(f)
    local actor = Instance.new("Actor", game:GetService("Players").LocalPlayer)
    actor.Name = "run_on_actor"

    f(actor, [[
        Instance.new("Folder", game:GetService("Players").LocalPlayer.run_on_actor).Name = "test"
    ]])

    task.wait()

    assert(actor:FindFirstChild("test"), "did not create an Instance")

    task.wait()
    actor:Destroy()
end)

-- Debug Library

test({"debug.validlevel", "debug.isvalidlevel"}, function(f)
    assert(f(1), "did not return true for current level")
end)

test("debug.getcallstack", function(f)
    local curr_func = debug.info(1, "f")
    assert(f()[1] == curr_func, "did not return current function at index 1")
end)

test("debug.getprotos", function(f)
    local function f1()
        local function f2()
            return "test"
        end
        return f2
    end
    local cl = f(f1)[1]
    if cl ~= f1() and cl() ~= "test" then
        return "not sure"
    end
end)

test("debug.getproto", function(f)
    local function f1()
        local function f2()
            return "test"
        end
        return f2
    end
    local cl = f(f1, 1, true)[1]
    if cl ~= f1() and cl() ~= "test" then
        return "not sure"
    end
end)

test("debug.getstack", function(f)
    local _1 = "te" .. "st"
    assert(f(1)[2] == "test", "did not return valid first value")
    assert(f(1, 2) == "test", "did not return valid stack value")
end)

test("debug.setstack", function(f)
    local _1 = "not " .. "test"
    f(1, 2, "test")
    assert(_1 == "test", "did not set first stack value")
end)

test("debug.getupvalues", function(f)
    local upv = math.random(1, 100)
    local function f1()
        return upv
    end
    assert(f(f1)[1] == upv, "did not return correct first upvalue")
end)

test("debug.getupvalue", function(f)
    local upv = math.random(1, 100)
    local function f1()
        return upv
    end
    assert(f(f1, 1) == upv, "did not return correct upvalue")
end)

test("debug.setupvalue", function(f)
    local upv = math.random(1, 100)
    local function f1()
        return upv
    end
    f(f1, 1, 101)
    assert(f1() == 101, "did not set first upvalue")
end)

test("debug.getconstants", function(f)
    local function f1()
        return "test"
    end
    assert(f(f1)[1] == "test", "did not return correct first constant value")
end)

test("debug.getconstant", function(f)
    local function f1()
        return "test"
    end
    assert(f(f1, 1) == "test", "did not return correct constant value")
end)

test("debug.setconstant", function(f)
    local function f1()
        return "not test"
    end
    f(f1, 1, "test")
    assert(f1() == "test", "did not set first constant value")
end)

-- Cache Library

test("cache.invalidate", function(f)
    local f1 = Instance.new("Folder")
    local f2 = Instance.new("Folder", f1)
    f(f1:FindFirstChild("Folder"))
    assert(f2 ~= f1:FindFirstChild("Folder"), "did not invalidate cached instance")
end)

test("cache.iscached", function(f)
    local f1 = Instance.new("Folder")
    assert(f(f1), "did not return true for cached instance")
    if cache.invalidate then
        cache.invalidate(f1)
        assert(not f(f1), "did not return false for non-cached instance")
    else
        return "skipped cache.invalidate check"
    end
end)

test("cache.replace", function(f)
    local f1 = Instance.new("Folder")
    local f2 = Instance.new("Folder")
    f(f1, f2)
    assert(f1 ~= f2, "did not replace instance in cache")
end)

test("cloneref", function(f)
    local f1 = Instance.new("Folder")
    local cf = cloneref(f1)
    assert(f1 ~= cf, "returned same instance")
    cf.Name = "test"
    assert(f1.Name == "test", "did not update instance name")
end)

test("compareinstances", function(f)
    local f1 = Instance.new("Folder")
    local f2 = Instance.new("Folder")
    assert(not f(f1, f2), "did not return false for different instances")
    assert(f(f1, f1), "did not return true for same instancce")
    if cloneref then
        f2 = cloneref(f1)
        assert(f(f1, f2), "did not return true for cloned reference of instance")
    else
        return "skipped cloneref check"
    end
end)

-- Misc APIs

test("getrunningscripts", function(f)
    local instances = f()
    assert(typeof(instances[1]) == "Instance", "first value in running scripts is not an Instance")
    assert((instances[1]:IsA("LocalScript") or instances[1]:IsA("ModuleScript")), "first value in running scripts is not a local or module script")
end)

repeat task.wait() until running == 0

print()
print(string.format("✅ SNC Score: %d out of %d (%d%%)", passed, count, math.floor((passed / count) * 100)))
warn(string.format("⚠️ %d globals missing aliases", missing))