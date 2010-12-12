module("gaia.util", package.seeall)

function kpairs(t)
   local k
   if #t > 0 then k = #t end
   return function()
      k, v = next(t, k)
      return k, v
   end
end

local ignore = { locn = true; tag = true; parent = true }
local LEVEL = 1
function dump(node, seen)
   if not seen then seen = { } end
   if type(node) == "string" then
      return '"'..node..'"'
   end
   if type(node) == "number" then
      return node
   end
   if type(node) == "boolean" then
      return tostring(node)
   end
   if type(node) == "function" then
      return "<function>"
   end
   if seen[node] then
      return seen[node]
   end
   seen[node] = "#ref"

   local buff = { }
   local dent = string.rep("  ", LEVEL)
   local tput = table.insert

   tput(buff, "<"..(node.tag or "")..">")
   if node.locn then
      local locn = node.locn
      tput(buff, " @["..locn[1]..".."..locn[2].."]:"..tostring(locn.line))
   end

   tput(buff, " {")
   LEVEL = LEVEL + 1
   for k,data in kpairs(node) do
      if not ignore[k] then
         tput(buff, "\n"..dent..'"'..k..'" = '..dump(data, seen)..",")
      end
   end
   for i,data in ipairs(node) do
      tput(buff, "\n"..dent.."["..i.."] = "..dump(data, seen)..",")
   end
   LEVEL = LEVEL - 1;

   tput(buff, "\n"..string.rep("  ", LEVEL - 1).."}")
   local out = table.concat(buff, "")
   seen[node] = "#ref:"..out
   return out
end

local IDGEN = 0
function genid()
   IDGEN = IDGEN + 1
   return "_"..IDGEN
end

