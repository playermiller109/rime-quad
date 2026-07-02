-- utils.lua
local M = {}

function M.memlookup(env, sub)
  if env.cache[sub] ~= nil then return env.cache[sub] end
  if env.mem:dict_lookup(sub, false, 1) then
    for entry in env.mem:iter_dict() do
      env.cache[sub] = entry.text
      return entry.text
    end
  end
  env.cache[sub] = false
  return false
end

function M.ToggleKana(key, ctx)
  if ctx:is_composing() and key:repr() == "F9" then
    local seg = ctx.composition:back()
    if seg then
      local idx = seg.selected_index
      local state = ctx:get_property("kana_idx")

      if state == tostring(idx) then
        ctx:set_property("kana_idx", "")
      else
        ctx:set_property("kana_idx", tostring(idx))
      end

      ctx:refresh_non_confirmed_composition()

      local new_seg = ctx.composition:back()
      if new_seg then
        new_seg.selected_index = idx
      end
      return 1
    end
  end

  if not ctx:is_composing() then
    ctx:set_property("kana_idx", "")
  end
end

return M
