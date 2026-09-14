-- ref @github HowcanoeWang/rime-lua-aux-code
local AuxFilter = {}

local parse_aux_input
local escape_lua_pattern
local split_aux_input
local has_non_alpha_after_aux

local function normalize_trigger(token, fallback)
  if token == nil or token == "" then return fallback end
  return token
end

local function is_multi_char_text(text)
  if not text or text == "" then return false end
  local count = 0
  for _ in utf8.codes(text) do
    count = count + 1
    if count > 1 then return true end
  end
  return false
end

local function to_commit_only_candidate(cand)
  local rebuilt = Candidate(cand.type, cand.start, cand._end, cand.text, cand.comment)
  rebuilt.preedit = cand.preedit
  rebuilt.quality = cand.quality
  return rebuilt
end

local function get_aux_code(env, text)
  if not env.rev then return nil end
  if env.aux_cache[text] ~= nil then return env.aux_cache[text] end

  local code = env.rev:lookup(text)
  if code and code ~= "" then
    env.aux_cache[text] = code
    return code
  end

  env.aux_cache[text] = false
  return nil
end

local function find_phrase_match(env, word, auxStr)
  if auxStr == "" or not word or word == "" then return nil end

  local pos = 0
  for _, codePoint in utf8.codes(word) do
    pos = pos + 1
    local char = utf8.char(codePoint)
    local code = get_aux_code(env, char)
    if code and code:sub(1, #auxStr) == auxStr then
      return { pos = pos, char = char, full_code = code }
    end
  end
  return nil
end

function AuxFilter.init(env)

  env.rev = ReverseLookup("stroke")
  env.aux_cache = {}

  local engine = env.engine
  local config = engine.schema.config

  env.learn_trigger = normalize_trigger(config:get_string("key_binder/aux_code_learn_trigger"), nil)
    or normalize_trigger(config:get_string("key_binder/aux_code_trigger"), nil)
    or "\t"
  env.no_learn_trigger = normalize_trigger(config:get_string("key_binder/aux_code_no_learn_trigger"), "")

  if env.no_learn_trigger == env.learn_trigger then
    env.no_learn_trigger = ""
  end

  env.triggers = {
    { mode = "no_learn", token = env.no_learn_trigger },
    { mode = "learn", token = env.learn_trigger },
  }

  local active_triggers = {}
  for _, item in ipairs(env.triggers) do
    if item.token ~= "" then
      table.insert(active_triggers, item)
    end
  end
  env.triggers = active_triggers
  table.sort(env.triggers, function(a, b) return #a.token > #b.token end)

  env.show_aux_notice = config:get_string("key_binder/show_aux_notice") ~= 'false'

  env.notifier = engine.context.select_notifier:connect(function(ctx)
    local mode, _, trigger_token = parse_aux_input(ctx.input, env)
    if mode == "none" then return end

    local preedit = ctx:get_preedit()
    local removeAuxInput, _, after_aux = split_aux_input(ctx.input, trigger_token)
    local reeditTextFront = preedit.text:match("^(.-)" .. escape_lua_pattern(trigger_token))

    if not removeAuxInput then return end

    if reeditTextFront and reeditTextFront:match("[a-z]") then
      ctx.input = removeAuxInput .. trigger_token .. after_aux
    else
      ctx.input = removeAuxInput .. after_aux
      ctx:commit()
    end
  end)
end

escape_lua_pattern = function(text)
  return text:gsub("%W", "%%%1")
end

has_non_alpha_after_aux = function(input_code, env)
  for _, item in ipairs(env.triggers) do
    local token = item.token
    if token ~= "" then
      local token_pattern = escape_lua_pattern(token)
      if input_code:match(token_pattern .. "[a-z]+([^a-z].*)$") then return true end
    end
  end
  return false
end

split_aux_input = function(input_code, trigger_token)
  local trigger_pattern = escape_lua_pattern(trigger_token)
  local front, aux, after_aux = input_code:match("^(.-)" .. trigger_pattern .. "([a-z]*)(.*)$")
  if after_aux then
    after_aux = after_aux:match("^" .. trigger_pattern .. "[a-z]+(.*)$") or after_aux
  end
  return front, aux, after_aux or ""
end

parse_aux_input = function(input_code, env)
  if input_code == "" then return "none", "", "" end
  for _, item in ipairs(env.triggers) do
    local token = item.token
    if token ~= "" then
      local token_pattern = escape_lua_pattern(token)
      if input_code:find(token, 1, true) then
        local local_split = input_code:match(token_pattern .. "([a-z]+)")
        if not local_split then return item.mode, "", token end
        return item.mode, string.sub(local_split, 1, 2), token
      end
    end
  end
  return "none", "", ""
end

function AuxFilter.func(input, env)
  local context = env.engine.context
  local inputCode = context.input

  local mode, auxStr, _ = parse_aux_input(inputCode, env)

  if mode == "none" or has_non_alpha_after_aux(inputCode, env) then
    for cand in input:iter() do yield(cand) end
    return
  end

  local first_exact_bucket = {}
  local full_aux_bucket = {}

  local function to_yield_candidate(cand)
    if mode == "no_learn" then return to_commit_only_candidate(cand) end
    return cand
  end

  for _cand in input:iter() do
    local cand = _cand
    local auxCodes = get_aux_code(env, cand.text)

    if not env.rev then
      cand.comment = (cand.comment or "") .. " (⚠️)"
      yield(to_yield_candidate(cand))
      goto continue
    end

    if env.show_aux_notice and auxCodes and auxCodes ~= "" then
      local codeComment = " " .. auxCodes:sub(1, 4)
      if cand:get_dynamic_type() == "Shadow" then
        local shadowText = cand.text
        local shadowComment = cand.comment or ""
        local originalCand = cand:get_genuine()
        cand = ShadowCandidate(
          originalCand,
          originalCand.type,
          shadowText,
          (originalCand.comment or "") .. shadowComment .. codeComment
        )
      else
        cand.comment = (cand.comment or "") .. codeComment
      end
    end

    if #auxStr == 0 then
      if auxCodes and auxCodes ~= "" then
        yield(to_yield_candidate(cand))
      end
    else
      local is_phrase = is_multi_char_text(cand.text)

      if is_phrase then
        local matched = find_phrase_match(env, cand.text, auxStr)
        if matched then
          local hint = " (" .. matched.char .. ":" .. auxStr .. ")"
          if cand:get_dynamic_type() == "Shadow" then
            local original = cand:get_genuine()
            cand = ShadowCandidate(original, original.type, cand.text, (cand.comment or "") .. hint)
          else
            cand.comment = (cand.comment or "") .. hint
          end

          if matched.pos == 1 then
            table.insert(first_exact_bucket, cand)
          else
            table.insert(full_aux_bucket, cand)
          end
        end
      else
        if auxCodes and auxCodes:sub(1, #auxStr) == auxStr then
          table.insert(first_exact_bucket, cand)
        end
      end
    end
    ::continue::
  end

  local seen = {}
  local function yield_bucket(bucket)
    for _, cand in ipairs(bucket) do
      local key = cand.type .. "\t" .. cand.start .. "\t" .. cand._end .. "\t" .. cand.text
      if not seen[key] then
        seen[key] = true
        yield(to_yield_candidate(cand))
      end
    end
  end

  yield_bucket(first_exact_bucket)
  yield_bucket(full_aux_bucket)
end

function AuxFilter.fini(env)
  if env.notifier then env.notifier:disconnect() end
end

return AuxFilter
