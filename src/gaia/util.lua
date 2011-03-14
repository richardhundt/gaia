module("gaia.util", package.seeall)

local ignore = { locn = true; tag = true; parent = true }
local LEVEL = 1
function dump(node, seen)
   if not seen then seen = { } end
   if type(node) == 'userdata' then
      return tostring(node)
   end
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
   local i_seen = { }
   local i_buff = { }
   for i,data in ipairs(node) do
      i_seen[i] = true
      tput(i_buff, "\n"..dent.."["..i.."] = "..dump(data, seen)..",")
   end
   local p_buff = { }
   for k,data in pairs(node) do
      if not ignore[k] and not i_seen[k] then
         tput(p_buff, "\n"..dent..'['..dump(k)..'] = '..dump(data, seen)..",")
      end
   end
   tput(buff, table.concat(p_buff))
   tput(buff, table.concat(i_buff))
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

