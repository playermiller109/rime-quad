-- phrase.lua
local u_dir = rime_api.get_user_data_dir()
local txt_path = u_dir .. "/lua/phrase.txt"

local function load_rules()
  local map = {}
  local file = io.open(txt_path, "r")
  if not file then return map end
  for line in file:lines() do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local text, code, pos = line:match("([^%s]+)%s+([^%s]+)%s+(%d+)")
      if text and pos then
        if not map[code] then map[code] = {} end
        table.insert(map[code], { text = text, pos = tonumber(pos) })
      end
    end
  end
  file:close()

  for _, rules in pairs(map) do
    table.sort(rules, function(a, b) return a.pos < b.pos end)
  end
  return map
end

return {
  init = function(env)
    env.fixed_map = load_rules()
    env.last_check = 0
  end,

  func = function(input, env)
    local ctx = env.engine.context
    if ctx.composition:empty() then
      for cand in input:iter() do yield(cand) end
      return
    end

    local now = os.time()
    if now - env.last_check >= 6 then
      env.last_check = now
      local f = io.open(txt_path, "r")
      if f then
        f:close()
        env.fixed_map = load_rules()
      end
    end

    local seg = ctx.composition:back()
    local code = ctx.input:sub(seg.start + 1, seg._end)
    local rules = env.fixed_map[code]

    if not rules then
      for cand in input:iter() do yield(cand) end
      return
    end

    local count, idx, seen = 0, 1, {}
    local seg_start, seg_end = seg.start, seg._end

    for cand in input:iter() do
      count = count + 1

      while idx <= #rules and rules[idx].pos == count do
        local r = rules[idx]
        yield(Candidate("fixed", seg_start, seg_end, r.text, ""))
        seen[r.text] = true
        idx = idx + 1
        count = count + 1
      end

      if not seen[cand.text] then
        yield(cand)
      -- suppressed duplicates
      else
        count = count - 1
      end
    end

    while idx <= #rules do
      local r = rules[idx]
      if not seen[r.text] then
        yield(Candidate("fixed", seg_start, seg_end, r.text, ""))
      end
      idx = idx + 1
    end
  end
}
