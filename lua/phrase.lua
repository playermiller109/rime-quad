-- phrase.lua
local u_dir = rime_api.get_user_data_dir()

return {
  init = function(env)
    env.fixed_map = {}
    local file = io.open(u_dir .. "/lua/phrase.txt", "r")
    if file then
      for line in file:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then
          local code, text, pos = line:match("([^%s]+)%s+([^%s]+)%s+(%d+)")
          if code and text and pos then
            if not env.fixed_map[code] then env.fixed_map[code] = {} end
            table.insert(env.fixed_map[code], { text = text, pos = tonumber(pos) })
          end
        end
      end
      file:close()
      -- sort by target pos
      for code, rules in pairs(env.fixed_map) do
        table.sort(rules, function(a, b) return a.pos < b.pos end)
      end
    end
  end,

  func = function(input, env)
    local ctx = env.engine.context
    local code = ctx.input
    local rules = env.fixed_map[code]

    if not rules then
      for cand in input:iter() do yield(cand) end
      return
    end

    local count, idx, seen = 0, 1, {}
    local last_s, last_e = 0, #code

    for cand in input:iter() do
      count = count + 1
      last_s, last_e = cand.start, cand._end

      while idx <= #rules and rules[idx].pos == count do
        local r = rules[idx]
        yield(Candidate("fixed", cand.start, cand._end, r.text, ""))
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

    -- if candidate list is shorter than target pos
    if count == 0 and not ctx.composition:empty() then
      local seg = ctx.composition:back()
      last_s, last_e = seg.start, seg._end
    end

    while idx <= #rules do
      local r = rules[idx]
      if not seen[r.text] then
        yield(Candidate("fixed", last_s, last_e, r.text, ""))
      end
      idx = idx + 1
    end
  end
}
