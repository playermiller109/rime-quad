-- quad.lua
local ES_MAP = { [0x3F] = "¿", [0x21] = "¡" }
local ES_PRE = "["
local ES_PRE_CODE = string.byte(ES_PRE)
local ES_MAX_LEN = 3
local EMAIL_AT_CODE = 0x40

local M = {}

local yield = yield
local Candidate = Candidate
local ShadowCandidate = ShadowCandidate
local table_insert = table.insert
local email = require("email")
local u_dir = rime_api.get_user_data_dir()

-- debug_log_do_not_delete
local function log(msg)
  local f = io.open(u_dir .. "/quad.log", "a")
  if f then
    f:write(os.date("%H:%M:%S ") .. msg .. "\n")
    f:close()
  end
end

M.main_proc = {
  init = function(env)
    local ctx = env.engine.context
    env.notifier = ctx.option_update_notifier:connect(function(ctx, name)
      if name == "ascii_mode" and not ctx:get_option("ascii_mode") then
        ctx:set_property("caps_lock", "")
      end
    end)
    env.commit_notifier = ctx.commit_notifier:connect(function(ctx)
      local text = ctx:get_commit_text()
      if text == "" and ctx.commit_history and not ctx.commit_history:empty() then
        text = ctx.commit_history:latest_text()
      end
      if text and text:byte(-1) == EMAIL_AT_CODE then
        email.ready = true
      else
        email.ready = false
      end
    end)
  end,

  func = function(key, env)
    if key:release() or key:alt() or key:ctrl() then return 2 end

    local code = key.keycode
    local ctx = env.engine.context
    local composing = ctx:is_composing()

    if code == 0xffe5 then
      local ascii_mode = ctx:get_option("ascii_mode")

      if not ascii_mode then
        ctx:set_option("ascii_mode", true)
        ctx:set_property("caps_lock", "true")
      else
        if ctx:get_property("caps_lock") == "true" then
          ctx:set_option("ascii_mode", false)
        end
      end
      return 2
    end

    if not composing then
      if code == 0xff08 or code == 0xffff or (code >= 0xff50 and code <= 0xff57) or code == 0x20 or code == 0xff0d or code == 0xff8d or code == 0xff1b or code == 0xff09 then
        email.ready = false
      end
      return 2
    end

    if composing then
      if code == 0xff08 then
        if #ctx.input > 0 then
          ctx:pop_input(1)
          if #ctx.input == 0 then
            ctx:clear()
          end
          return 1
        end
      end

      if code == 0xff1b then
        ctx:clear()
        email.ready = false
        return 1
      end

      if code == 0xff0d or code == 0xff8d then
        env.engine:commit_text(ctx.input)
        ctx:clear()
        return 1
      end

      if code == 0xff09 then
        ctx:push_input("\t")
        return 1
      end

      if not email.ready then
        local rep = ES_MAP[code]
        if rep and ctx.input:byte(-1) == ES_PRE_CODE then
          ctx:pop_input(1)
          ctx:confirm_current_selection()
          env.engine:commit_text(rep)
          return 1
        end
      end
    end

    return 2
  end,

  fini = function(env)
    env.notifier:disconnect()
    env.commit_notifier:disconnect()
  end
}

M.email_trans = {
  func = function(input, seg, env)
    if not email.ready then return end
    local query = input:lower()
    local q_len = #query
    for _, dm in ipairs(email.DOMAINS) do
      if dm:sub(1, q_len) == query then
        local cand = Candidate("email_domain", seg.start, seg._end, dm, "")
        cand.quality = 999
        yield(cand)
      end
    end
  end
}

local function memlookup(env, text)
  if not env.mem then return nil end
  if env.cache[text] ~= nil then return env.cache[text] end
  if env.mem:dict_lookup(text, false, 1) then
    for entry in env.mem:iter_dict() do
      env.cache[text] = entry.text
      return entry.text
    end
  end
  env.cache[text] = false
  return nil
end

M.es_trans = {
  init = function(env)
    env.mem = Memory(env.engine, Schema("latin"))
    env.cache = {}
  end,
  func = function(input, seg, env)
    if email.ready then return end
    local n, i, parts, matched = #input, 1, {}, false
    while i <= n do
      local found = false
      for len = math.min(ES_MAX_LEN, n - i + 1), 1, -1 do
        local sub = input:sub(i, i + len - 1)
        local res = memlookup(env, sub)
        if res then
          table_insert(parts, res)
          i, found, matched = i + len, true, true
          break
        end
      end
      if not found then
        table_insert(parts, input:sub(i, i))
        i = i + 1
      end
    end
    if matched then
      yield(Candidate("es", seg.start, seg._end, table.concat(parts), " [西]"))
    end
  end,
  fini = function(env) env.mem:disconnect() end
}

M.s2jp_filter = {
  init = function(env)
    env.jp_map = {}
    local file = io.open(u_dir .. "/lua/ext/s2jp.txt", "r")
    if file then
      for l in file:lines() do
        local s, j = l:match("([^%s]+)%s+([^%s]+)")
        if s and j then
          if not env.jp_map[s] then
            env.jp_map[s] = {}
          end
          table_insert(env.jp_map[s], j)
        end
      end
      file:close()
    end
  end,
  func = function(input, env)
    local ctx = env.engine.context
    local is_lookup = false
    if not ctx.composition:empty() then
      local seg = ctx.composition:back()
      if seg:has_tag("putonghua_to_kanji_lookup") then
        is_lookup = true
      end
    end
    for cand in input:iter() do
      if not is_lookup and (cand.text == ES_PRE) then
      elseif is_lookup then
        local tgts = env.jp_map[cand.text]
        if tgts then
          for _, val in ipairs(tgts) do
            local nc = ShadowCandidate(cand, cand.type, val, cand.comment)
            yield(nc)
          end
        end
      else
        yield(cand)
      end
    end
  end
}

local tostring = tostring
local tonumber = tonumber
local utf8_char = utf8.char
local utf8_cp = utf8.codepoint
local utf8_ptrn = utf8.charpattern

local function a_kana(s)
  if not s then return "" end
  local fs = s:gsub("う゛", "TEMP_VU"):gsub("ヴ", "う゛"):gsub("TEMP_VU", "ヴ")
  return (fs:gsub(utf8_ptrn, function(c)
    local cp = utf8_cp(c)
    if cp >= 0x3041 and cp <= 0x3096 then return utf8_char(cp + 96) end
    if cp >= 0x30A1 and cp <= 0x30F6 then return utf8_char(cp - 96) end
    return c
  end))
end

M.kana_proc = {
  func = function(key, env)
    if key:release() or key:alt() or key:ctrl() then return 2 end

    local ctx = env.engine.context

    if not ctx:is_composing() then
      ctx:set_property("kana_idx", "")
      return 2
    end

    if key:repr() == "F9" then
      local seg = ctx.composition:back()
      if seg then
        local idx = seg.selected_index
        local state = ctx:get_property("kana_idx")
        local new_state = (state == tostring(idx)) and "" or tostring(idx)
        ctx:set_property("kana_idx", new_state)
        ctx:refresh_non_confirmed_composition()
        local new_seg = ctx.composition:back()
        if new_seg then new_seg.selected_index = idx end
        return 1
      end
    end

    return 2
  end
}

M.kana_filter = {
  func = function(input, env)
    local ctx = env.engine.context
    local tgt = tonumber(ctx:get_property("kana_idx") or "-1")
    local zh_pool = {}
    local jp_pool = {}

    for cand in input:iter() do
      -- cand.type == "japanese"
      if cand.comment and cand.comment:find("\x01", 1, true) then
        table_insert(jp_pool, cand)
      else
        table_insert(zh_pool, cand)
      end
    end

    local i = 0
    local function emit(cand, is_jp)
      if is_jp then
        local text = (i == tgt) and a_kana(cand.text) or cand.text
        local cmt = cand.comment .. "*"
        yield(Candidate(cand.type, cand.start, cand._end, text, cmt))
      else
        yield(cand)
      end
      i = i + 1
    end

    local zh_idx, jp_idx = 1, 1
    local zh_size, jp_size = #zh_pool, #jp_pool

    while zh_idx <= zh_size or jp_idx <= jp_size do
      if zh_idx <= zh_size then
        emit(zh_pool[zh_idx], false)
        zh_idx = zh_idx + 1
      end
      if jp_idx <= jp_size then
        emit(jp_pool[jp_idx], true)
        jp_idx = jp_idx + 1
      end
    end
  end
}

return M
