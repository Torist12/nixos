local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local util = import("micro/util")
local time = import("time")

local contextChars = 4000
local debounceMs = 700
local chatHistory = {}
local chatBuffer = nil
local completionGeneration = 0
local completionJob = nil
local pendingSuggestion = nil

local function jsonString(value)
    local escaped = value:gsub("[%z\1-\31\\\"]", function(char)
        local replacements = {
            ["\\"] = "\\\\",
            ["\""] = "\\\"",
            ["\b"] = "\\b",
            ["\f"] = "\\f",
            ["\n"] = "\\n",
            ["\r"] = "\\r",
            ["\t"] = "\\t",
        }
        return replacements[char] or string.format("\\u%04x", string.byte(char))
    end)
    return "\"" .. escaped .. "\""
end

local function submit(operation, payload, callback)
    local request = { output = "", error = "" }

    local function onStdout(chunk, args)
        local state = args[1]
        state.output = state.output .. chunk
    end

    local function onStderr(chunk, args)
        local state = args[1]
        state.error = state.error .. chunk
    end

    local function onExit(_, args)
        local state = args[1]
        micro.After(time.Millisecond, function()
            callback(state.output, state.error)
        end)
    end

    local job
    job = shell.JobSpawn("micro-llama-request", { operation, payload }, onStdout, onStderr, onExit, request)
    return job
end

local function cancelCompletion()
    if completionJob ~= nil then
        shell.JobStop(completionJob)
        completionJob = nil
    end
end

local function requestSuggestion(bp, generation, force)
    if bp == nil or bp.Buf == nil then
        return false
    end

    local buf = bp.Buf
    local filetype = buf:FileType()
    if not force and (filetype == "" or filetype == "unknown" or filetype == "off") then
        return false
    end

    local cursor = buf:GetActiveCursor()
    local location = buffer.Loc(cursor.X, cursor.Y)
    local bufferStart = buf:Start()
    local bufferEnd = buf:End()
    local start = location:Move(-contextChars, buf):Clamp(bufferStart, bufferEnd)
    local finish = location:Move(contextChars, buf):Clamp(bufferStart, bufferEnd)
    local prefix = util.String(buf:Substr(start, location))
    local suffix = util.String(buf:Substr(location, finish))
    local prompt = "<|fim_prefix|>" .. prefix .. "<|fim_suffix|>" .. suffix .. "<|fim_middle|>"
    local payload = "{\"prompt\":" .. jsonString(prompt) .. ",\"n_predict\":32,\"temperature\":0.1,\"stream\":false}"

    completionJob = submit("completion", payload, function(output, errorText)
        completionJob = nil
        if generation ~= completionGeneration then
            return
        end

        if output == "" then
            micro.InfoBar():Message("IA local indisponivel: " .. errorText)
            return
        end

        local currentStart = start:Clamp(buf:Start(), buf:End())
        local currentLocation = location:Clamp(buf:Start(), buf:End())
        local currentFinish = finish:Clamp(buf:Start(), buf:End())
        local currentPrefix = util.String(buf:Substr(currentStart, currentLocation))
        local currentSuffix = util.String(buf:Substr(currentLocation, currentFinish))
        if currentPrefix ~= prefix or currentSuffix ~= suffix then
            micro.InfoBar():Message("Buffer alterado; sugestao descartada")
            return
        end

        local preview = output:match("[^\n]+") or output
        if #preview > 72 then
            preview = preview:sub(1, 69) .. "..."
        end
        pendingSuggestion = {
            buffer = buf,
            location = location,
            start = start,
            finish = finish,
            prefix = prefix,
            suffix = suffix,
            text = output,
        }
        micro.InfoBar():Message("IA > " .. preview .. "  [Tab]")
    end)
    return true
end

function complete(bp)
    completionGeneration = completionGeneration + 1
    cancelCompletion()
    pendingSuggestion = nil
    return requestSuggestion(bp, completionGeneration, true)
end

function accept(bp)
    local suggestion = pendingSuggestion
    if suggestion == nil or bp == nil or bp.Buf ~= suggestion.buffer then
        return false
    end

    local buf = suggestion.buffer
    local cursor = buf:GetActiveCursor()
    local location = suggestion.location
    local currentLocation = buffer.Loc(cursor.X, cursor.Y)
    local currentStart = suggestion.start:Clamp(buf:Start(), buf:End())
    local currentCursor = currentLocation:Clamp(buf:Start(), buf:End())
    local currentFinish = suggestion.finish:Clamp(buf:Start(), buf:End())

    if currentCursor.X ~= location.X or currentCursor.Y ~= location.Y
        or util.String(buf:Substr(currentStart, currentCursor)) ~= suggestion.prefix
        or util.String(buf:Substr(currentCursor, currentFinish)) ~= suggestion.suffix then
        pendingSuggestion = nil
        return false
    end

    buf:Insert(location, suggestion.text)
    cursor:GotoLoc(location:Move(util.CharacterCountInString(suggestion.text), buf))
    bp:Relocate()
    pendingSuggestion = nil
    micro.InfoBar():Message("")
    return true
end

function onRune(bp)
    if bp == nil or bp.Buf == nil then
        return
    end

    local filetype = bp.Buf:FileType()
    if filetype == "" or filetype == "unknown" or filetype == "off" then
        return
    end

    completionGeneration = completionGeneration + 1
    cancelCompletion()
    pendingSuggestion = nil
    micro.InfoBar():Message("")

    local generation = completionGeneration
    micro.After(time.Millisecond * debounceMs, function()
        if generation == completionGeneration then
            requestSuggestion(bp, generation, false)
        end
    end)
end

local function chat(bp, args)
    local prompt = table.concat(args, " ")
    if prompt == "" then
        micro.InfoBar():Message("Digite uma pergunta depois de llama-chat")
        return
    end

    if chatBuffer == nil then
        chatBuffer = buffer.NewBuffer("", "[llama-chat]")
        bp:HSplitBuf(chatBuffer)
    end

    local messages = {}
    for _, message in ipairs(chatHistory) do
        table.insert(messages, "{\"role\":" .. jsonString(message.role) .. ",\"content\":" .. jsonString(message.content) .. "}")
    end
    table.insert(messages, "{\"role\":\"user\",\"content\":" .. jsonString(prompt) .. "}")

    local payload = "{\"model\":\"micro-local\",\"messages\":[" .. table.concat(messages, ",") .. "],\"max_tokens\":192,\"temperature\":0.3,\"stream\":false}"
    chatBuffer:Insert(chatBuffer:End(), "Voce: " .. prompt .. "\nIA: ")
    micro.InfoBar():Message("IA local: aguardando resposta...")

    submit("chat", payload, function(output, errorText)
        if output == "" then
            chatBuffer:Insert(chatBuffer:End(), "indisponivel: " .. errorText .. "\n\n")
            micro.InfoBar():Message("IA local indisponivel")
            return
        end

        table.insert(chatHistory, { role = "user", content = prompt })
        table.insert(chatHistory, { role = "assistant", content = output })
        chatBuffer:Insert(chatBuffer:End(), output .. "\n\n")
        micro.InfoBar():Message("Resposta local recebida")
    end)
end

function init()
    config.TryBindKey("F4", "lua:llama_ai.complete", true)
    config.TryBindKey("Tab", "lua:llama_ai.accept|Autocomplete|IndentSelection|InsertTab", true)
    config.TryBindKey("F8", "command-edit:llama-chat ", true)
    config.MakeCommand("llama-chat", chat, config.NoComplete)
end