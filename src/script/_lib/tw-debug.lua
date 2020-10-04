--[[
    MIT License

    Copyright (c) 2020 Mickael Daniel

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
--]]

local inspect = require("vendors/inspect")
local inspectOptions = { depth = 4 }

local LIP = require("vendors/LIP")

local DEBUG_INI_FILEPATH = "debug.ini"

local debug = {}
debug.file = "debug.txt"
debug.hasIniFile = false

function debug.split(str, delim, maxNb)
    -- Eliminate bad cases...
    if string.find(str, delim) == nil then
       return { str }
    end
    if maxNb == nil or maxNb < 1 then
       maxNb = 0    -- No limit
    end
    local result = {}
    local pat = "(.-)" .. delim .. "()"
    local nb = 0
    local lastPos
    for part, pos in string.gfind(str, pat) do
       nb = nb + 1
       result[nb] = part
       lastPos = pos
       if nb == maxNb then
          break
       end
    end
    -- Handle the last field
    if nb ~= maxNb then
       result[nb + 1] = string.sub(str, lastPos)
    end
    return result
end

function debug.countChar(str, pattern)
    local count = 0
    for matched in string.gmatch(str, pattern) do
        count = count + 1
    end

    return count
end

function debug.slice(tbl, first, last, step)
    local sliced = {}

    for i = first or 1, last or #tbl, step or 1 do
        sliced[#sliced+1] = tbl[i]
    end

    return sliced
end

function debug.timestamp()
    return os.clock()
end

function debug.fileExists(name)
    local f=io.open(name, "r")
    if f~=nil then 
        io.close(f) 
        return true 
    end

    return false 
end

function debug.logToFile(filepath, text)
    if not debug.hasIniFile then
        return
    end
    
    local file = io.open(filepath, "a")
    file:write(text .. "\n")
    file:flush()
    file:close()
end

function debug.log(env, ...)
    local str = env.namespace .. " "

    local formatersCount = 0
    local startIndex = 1

    if type(arg[1]) == "string" then
        formatersCount = debug.countChar(arg[1], "%%[^%s]*%a")
    end

    if formatersCount ~= 0 then
        local params = debug.slice(arg, 2)

        if formatersCount == #params then
            local format = assert(string.format(arg[1], unpack(params)), "wait")
            str = str .. format
    
            startIndex = formatersCount + 2
        end
    end

    for i = startIndex, arg.n do
        local obj = arg[i]
        local separator = i == 1 and "" or " "

        if type(obj) == "string" then
            str = str .. separator .. obj
        else
            str = str .. separator .. inspect(obj, inspectOptions)
        end
    end
    
    str = str .. " +" .. env.diff

    local filepath = env.file or debug.file
    debug.logToFile(filepath, str)

    return str
end

function debug.humanize(time)
    time = string.format("%.3f", time)
    local s, ms = string.match(time, "(%d+).(%d+)")
    s = tonumber(s)
    ms = tonumber(ms)

    if s == 0 then
        return ms .. "ms"
    end

    return s .. "s"
end

function debug.setup()
    local createDebug = {}

    -- The currently active debug mode names, and names to skip
    createDebug.names = {}
    createDebug.skips = {}

    debug.hasIniFile = debug.fileExists(DEBUG_INI_FILEPATH)

    -- Enables a debug mode by namespaces. This can include modes separated by a colon and wildcards.
    --
    -- @String fileName The name of the INI file to parse. [string]
    -- @return The table containing all data from the INI file. [table]
    function createDebug.enable(namespaces)
        namespaces = type(namespaces) == "string" and namespaces or ""

        createDebug.names = {}
        createDebug.skips = {}

        local split = debug.split(namespaces, " ")

        for i = 1, #split do
            local namespace = split[i]

            -- switch wildcard characters to lua wildcard
            namespace = string.gsub(namespace, "*", ".*")
            
            -- ignore empty strings
            if namespace ~= "" then
                local first = string.sub(namespace, 1, 1)
                if first == "-" then
                    table.insert(createDebug.skips, "^" .. string.sub(namespace, 2) .. "$")
                else
                    table.insert(createDebug.names, "^" .. namespace .. "$")
                end
            end
        end
    end

    -- Load namespaces
    --
    -- @return {String} returns the previously persisted debug modes
    function createDebug.load()
        local result = ""

        if not debug.hasIniFile then
            return result
        end
        
        local options = LIP.load(DEBUG_INI_FILEPATH)
        return options.DEBUG
    end

    -- Returns true if the given mode name is enabled, false otherwise.
    --
    -- @param {String} name
    -- @return {Boolean}
    function createDebug.enabled(name)
        name = name or ""
        local last = string.sub(name, #name)

        for i = 1, #createDebug.skips do
            if string.match(name, createDebug.skips[i]) then
                return false
            end
        end

        for i = 1, #createDebug.names do
            if string.match(name, createDebug.names[i]) then
                return true
            end
        end

        return false
    end

    local function createDebug_call(namespace)
        namespace = namespace or ""

        local prevTime = nil

        local logger = {}

        logger.enabled = createDebug.enabled(namespace)
        
        local function logger_call(...)
            -- noop if disabled
            if not logger.enabled then
                return
            end


            local curr = debug.timestamp()
            local time = curr - (prevTime or curr)
            local diff = debug.humanize(time)
            local prev = prevTime
            prevTime = curr

            local log = logger.log or createDebug.log or debug.log
            local file = logger.file or createDebug.file
            local env = {
                diff = diff,
                prev = prev,
                curr = curr,
                namespace = namespace,
                file = file
            }

            return log(env, unpack(arg))
        end

        setmetatable(logger, {
            __call = function(t, ...)
                return logger_call(unpack(arg))
            end
        })

        return logger
    end

    createDebug.enable(createDebug.load())

	setmetatable(createDebug, {
        __call = function(t, namespace)
            return createDebug_call(namespace)
        end
    })

    return createDebug
end

return debug.setup()