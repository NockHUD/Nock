-- Tests/lib/catalog_scan.lua
-- Reads Modules/Warnings.lua and Modules/Helpers.lua as text and returns stub catalogs with the real keys, categories, severities and flags (no client APIs needed).
local function scan(path, keyIndent)
  local f = assert(io.open(path))
  local src = f:read("*a")
  f:close()
  local list, cur = {}, nil
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    local k = line:match("^" .. keyIndent .. "key%s*=%s*\"(%w+)\"")
    if k then
      cur = { key = k, description = "x", logic = "x" }
      list[#list + 1] = cur
    elseif cur then
      local cat = line:match("^%s+category%s*=%s*\"(%w+)\""); if cat then cur.category = cat end
      local nm = line:match("^%s+name%s*=%s*\"([^\"]*)\""); if nm and not cur.name then cur.name = nm end
      local sev = line:match("^%s+severity%s*=%s*\"(%w+)\""); if sev then cur.severity = sev end
      local en = line:match("^%s+enabledKey%s*=%s*\"(%w+)\""); if en then cur.enabledKey = en end
      if line:match("^%s+iconFn%s*=") or line:match("^%s+icon%s*=") then cur.hasIcon = true end
      if line:match("^%s+description%s*=") then cur.hasDescription = true end
      local mk, ml = line:match("^%s+{%s*key%s*=%s*\"(%w+)\",%s*label%s*=%s*\"([^\"]*)\",%s*mediaType%s*=%s*\"sound\"")
      if mk then cur.mediaSelectors = cur.mediaSelectors or {}; cur.mediaSelectors[#cur.mediaSelectors + 1] = { key = mk, label = ml, mediaType = "sound" } end
    end
  end
  return list
end
return {
  Warnings = { Catalog = scan("Modules/Warnings.lua", "    ") },
  Helpers = { Catalog = scan("Modules/Helpers.lua", "    ") },
}
