
function getinfo(level)
   local info, lsrc, line
   local skip = 0
   local l = level or 0
   while true do
      l = l + 1
      info = debug.getinfo(l, 'fSln')
      if info == nil then return nil end
      lsrc = info.source
      line = info.currentline
      if lsrc:sub(1,1) ~= '@' and lsrc:sub(1,4) ~= '=[C]' then break end
      skip = skip + 1
   end
   local o = 0
   local stop = line - 1
   local offs = 0
   while stop > 0 do
      stop = stop - 1
      o = string.find(lsrc, "\n", offs + 1, true)
      if o == nil then break end
      offs = o
   end
   local _, _, file, line = string.find(lsrc, "--%[%[(.-):(%d+)%]%]", offs + 1)
   return {
      skip     = skip,
      file     = file,
      line     = line,
      func     = info.func,
      name     = info.name,
      namewhat = info.namewhat,
      what     = info.what,
   }
end

function traceback()
   local buf = { }
   local lvl = 1
   while true do
      lvl = lvl + 1
      local info = getinfo(lvl)
      if info == nil then break end
      buf[#buf + 1] = '\t'..info.file..':'..info.line..' in '..info.name
      lvl = lvl + info.skip
   end
   return table.concat(buf, '\n')..'\n'
end

local Script = { }
Script.__index = Script
Script.new = function(source, name)
   local self = setmetatable({
      source = source;
      name   = name;
   }, Script)
   return self
end
Script.execute = function(self, code, ...)
   local args = { ... }
   local ok, rv = xpcall(function()
      local __main__ = assert(loadstring(code))
      __main__(unpack(args))
      return getfenv(__main__).__exports__
   end, function(e, ...)
      print(e, debug.traceback())
      if type(e) == 'string' then
         local m = string.match(e, [[%.%.%."%]:%d+: (.+)$]])
         if m then e = m end
      end
      local info = getinfo(2)
      io.stderr:write('kudu: '..info.file..':'..info.line..': '..tostring(e).."\n")
      io.stderr:write('stack traceback:\n')
      io.stderr:write(traceback(2))
      os.exit(255)
   end)
   return rv
end

return Script

