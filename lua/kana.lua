-- kana.lua
local M = {}

local function a_kana(s)
  if not s then return "" end

  s = s:gsub("う゛", "TEMP_VU"):gsub("ヴ", "う゛"):gsub("TEMP_VU", "ヴ")

  return (s:gsub(utf8.charpattern, function(c)
    local cp = utf8.codepoint(c)

    -- hira
    if cp >= 0x3041 and cp <= 0x3096 then
      return utf8.char(cp + 96)

    -- kata
    elseif cp >= 0x30A1 and cp <= 0x30F6 then
      return utf8.char(cp - 96)
    end

    return c
  end))
end

M.kana_filter = {
  func = function(input, env)
    local target = tonumber(env.engine.context:get_property("kana_idx") or "-1")
    local i = 0
    for cand in input:iter() do
      if i == target then
        yield(Candidate(cand.type, cand.start, cand._end, a_kana(cand.text), cand.comment))
      else
        yield(cand)
      end
      i = i + 1
    end
  end
}

return M
