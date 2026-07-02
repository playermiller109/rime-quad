-- quad.lua
local ES_MAP = { ["?"] = "¿", ["!"] = "¡" }
local ES_PRE = "["
local ES_MAX_LEN = 3
local u_dir = rime_api.get_user_data_dir()
local utils = require("utils")

local M = {}

local function log(msg)
  local f = io.open(u_dir .. "/quad.log", "a")
  if f then
    f:write(os.date("%H:%M:%S ") .. msg .. "\n")
    f:close()
  end
end

M.main_proc = {
  func = function(key, env)
    if key:release() or key:alt() or key:ctrl() then return 2 end

    local ctx = env.engine.context
    local composing = ctx:is_composing()

    local res = utils.ToggleKana(key, ctx)
    if res then return res end

    if key:repr() == "Tab" and composing then
      ctx:push_input("\t")
      return 1
    end

    -- caps_lock
    if key.keycode == 0xffe5 then
      local ctx = env.engine.context
      if not composing then
        local ascii_mode = ctx:get_option("ascii_mode")
        ctx:set_option("ascii_mode", not ascii_mode)
      end
      return 2
    end

    local ch = ""
    if key.keycode > 31 and key.keycode < 127 then
      ch = string.char(key.keycode)
    end
    if ES_MAP[ch] and composing then
      local preedit = ctx.input
      if preedit:sub(-1) == ES_PRE then
        ctx:pop_input(1)
        if composing then
          ctx:confirm_current_selection()
        end
        env.engine:commit_text(ES_MAP[ch])
        return 1
      end
    end

    return 2
  end
}

M.es_trans = {
  init = function(env)
    env.mem = Memory(env.engine, env.engine.schema, "es")
    env.cache = {}
  end,

  func = function(input, seg, env)
    if not input:find(ES_PRE, 1, true) then return end

    local n, i, parts, matched = #input, 1, {}, false
    while i <= n do
      local found = false
      for len = math.min(ES_MAX_LEN, n - i + 1), 1, -1 do
        local sub = input:sub(i, i + len - 1)
        local res = utils.memlookup(env, sub)
        if res then
          table.insert(parts, res)
          i, found, matched = i + len, true, true
          break
        end
      end
      if not found then
        table.insert(parts, input:sub(i, i))
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
      for line in file:lines() do
        local s, j = line:match("([^%s]+)%s+([^%s]+)")
        if s and j then
          if not env.jp_map[s] then
            env.jp_map[s] = {}
          end
          table.insert(env.jp_map[s], j)
        end
      end
      file:close()
    end
  end,

  func = function(input, env)
    local context = env.engine.context
    local is_lookup

    if not context.composition:empty() then
      local seg = context.composition:back()
      if seg:has_tag("putonghua_to_kanji_lookup") then
        is_lookup = true
      end
    end

    for cand in input:iter() do
      if not is_lookup and (cand.text == ES_PRE) then
      elseif is_lookup then
        local targets = env.jp_map[cand.text]
        if targets then
          for _, val in ipairs(targets) do
            local new_cand = ShadowCandidate(cand, cand.type, val, "")
            yield(new_cand)
          end
        end
      else
        yield(cand)
      end
    end
  end
}

M.aux_filter = require("ext.aux_code")

return M
