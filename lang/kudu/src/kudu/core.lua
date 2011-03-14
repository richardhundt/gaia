module("kudu.core", package.seeall)

local Script   = require'kudu.script'
local Compiler = require'kudu.compiler'
local Package  = require'kudu.package'

Slot = { }
Slot.__index = Slot
Slot.new = function(desc)
   if desc.modifier == 'private' then
      desc.name = '#'..desc.name
   end
   if rawget(desc, 'guard') then
      desc.key = desc
   else
      desc.key = desc.name
   end
   if desc.default then
      desc.val = assert(loadstring('return '..desc.default))
   else
      desc.val = function() return nil end
   end
   return setmetatable(desc, Slot)
end
Slot.clone = function(self)
   local copy = { }
   for k,v in pairs(self) do copy[k] = v end
   return Slot.new(copy)
end
Slot.guard = function(...) return ... end
Slot.get = function(self, o)
   local v = rawget(o, self.key)
   if v ~= nil then return v end
   v = self.val()
   rawset(o, self.key, v)
   return v
end
Slot.set = function(self, o, v)
   local val = self.guard(v)
   rawset(o, self.key, val)
end

Proto = { }
Proto.__index = function(c, k)
   return {
      key = k;
      name = k;
      missing = true;
      get = function(_,o)
         error("AccessError [get]: no such member: "..tostring(k).." in "..tostring(o), 3)
      end;
      set = function(_,o)
         error("AccessError [set]: no such member: "..tostring(k).." in "..tostring(o), 3)
      end;
   }
end

Method = { }
Method.__index = Method
Method.new = function(desc)
   if desc.modifier == 'private' then
      desc.name = '#'..desc.name
   end
   desc.key = desc.name
   return setmetatable(desc, Method)
end
Method.get = function(self, o)
   rawset(o, self.key, self.body)
   return self.body
end

Rule = { }
Rule.__index = Rule
Rule.new = function(desc, grammar)
   if desc.modifier == 'private' then
      desc.name = '#'..desc.name
   end
   desc.key = desc.name
   local self = setmetatable(desc, Rule)
   grammar[desc.name] = self
   self.grammar = grammar
   return self
end
Rule.get = function(self, o)
   local gram = { }
   local meta = getmetatable(o)
   for name,rule in pairs(self.grammar) do
      gram[name] = rule:body(o)
   end
   gram[1] = self.name
   local patt = lpeg.P(gram)
   rawset(o, self.key, patt)
   return patt
end
Rule.clone = function(self)
   local copy = { }
   for k,v in pairs(self) do copy[k] = v end
   return Rule.new(copy)
end


Function = { }
Function.__index = Function
Function.new = function(desc)
   return setmetatable(desc, Function)
end
Function.get = function(self, o)
   return self.body
end

magic  = { }
global = { magic = magic }

magic.sys = sys
magic.yield = coroutine.yield

KWeak = { __mode = 'k' }

local STATE = setmetatable({ }, KWeak)
local GUARD = setmetatable({ }, KWeak)

magic.table = function(table, guard)
   if guard then
      local proxy = { }
      GUARD[proxy] = guard
      STATE[proxy] = table
      setmetatable(proxy, TableG)
      for k,v in pairs(table) do
         proxy[k] = v
      end
      return proxy
   end
   return setmetatable(table, Table)
end

Table = { }
Table.__tostring = function(self) return '[Table: '..sys.refaddr(self)..']' end
Table.__has = function(self, k)
   return self[k] ~= nil
end
Table.__spread = function(self)
   local keys = { }
   for k in pairs(self) do
      keys[#keys + 1] = k
   end
   return unpack(keys)
end

TableG = { }
TableG.__tostring = Table.__tostring
TableG.__metatable = Table
TableG.__index = function(self, k)
   return STATE[self][k]
end
TableG.__newindex = function(self, k, v)
   local g = GUARD[self][k]
   if g then v = g(v) end
   STATE[self][k] = v
end
TableG.__has = function(self, k)
   return STATE[self][k] ~= nil
end
TableG.__pairs = function(self)
   return pairs(STATE[self])
end

magic.array = function(array, guard)
   return setmetatable(array, Array)
end

Array = { }
Array.__tostring = function(self) return '[Array: '..sys.refaddr(self)..']' end
Array.__index = function(self, k)
   if k == 'size' then return self['#size'] end
   return Array[k]
end
Array.__newindex = function(self, k, v)
   if type(k) == 'number' and math.floor(k) == k then
      if k >= self['#size'] then self["#size"] = k + 1 end
   elseif k == 'size' then
      if type(v) == 'number' and v >= 0 and math.floor(v) == v then
         k = '#size'
      end
   end
   rawset(self, k, v)
end
Array.__pairs = function(self)
   local i = 0
   local t = self
   local l = self["#size"]
   return function()
      if i >= l then return nil end
      local k = i
      local v = t[k]
      i = i + 1
      return k, v
   end
end
Array.__has = function(self, v)
   for i=0, self['#size'] - 1 do
      if self[i] == v then return true end
   end
   return false
end
Array.__spread = function(self)
   return unpack(self, 0, self['#size'] - 1)
end
Array.push = function(self, v)
   local e, c = self, self['#size']
   e[c] = v
   self['#size'] = c + 1
end
Array.pop = function(self)
   local e, c, v = self, self['#size']
   if c < 1 then return nil end
   c = c - 1
   v, e[c] = e[c], nil
   self['#size'] = c
   return v
end
Array.shift = function(self)
   local e, c, v = self, self['#size']
   if c < 1 then return nil end
   v = e[0]
   for i=0, c do
      e[i] = e[i + 1]
   end
   e[c] = nil
   self['#size'] = c - 1
   return v
end
Array.unshift = function(self, v)
   local e, c = self, self['#size']
   for i=c, 0, -1 do
      e[i] = e[i-1]
   end
   e[0] = v
   self['#size'] = c + 1
end
Array.splice = function(self, ofs, cnt, ...)
   local len = self['#size']
   local rep = select('#', ...)
   local out = magic.array{ }
   local del = rep - cnt
   if del > 0 then
      for i=len - 1, -del + ofs + cnt, -1 do
         self[i + del] = self[i]
      end
   elseif del < 0 then
      for i=ofs + cnt, -del + ofs + cnt do
         out:push(self[i])
      end
      for i=ofs + cnt, len - 1 do
         self[i + del] = self[i]
      end
   end
   local arg = 0
   for i=ofs, ofs + rep - 1 do
      arg = arg + 1
      self[i] = select(arg, ...)
   end
   self['#size'] = len + del
   return out
end
Array.grep = function(self, grep)
   local out = magic.array{ }
   for i, v in Array.__pairs(self) do
      if grep(v) == true then
         out:push(v)
      end
   end
   return out
end
Array.map = function(self, map)
   local out = magic.array{ }
   for i, v in Array.__pairs(self) do
      out:push(map(v))
   end
   return out
end
Array.each = function(self, each)
   for i, v in Array.__pairs(self) do
      each(i, v)
   end
end
Array.join = function(self, sep)
   local b = { }
   self:each(function(i,v) b[#b + 1] = (v == nil and '' or tostring(v)) end)
   return table.concat(b, sep)
end

Enum = { }
Enum.__index = Enum

Range = { }
Range.__index = Range
Range.__pairs = function(self)
   local cur = self[1] - 1
   local max = self[2]
   return function()
      cur = cur + 1
      if cur <= max then
         return cur
      end
   end
end

magic.tuple = function(...)
   return setmetatable({ size=select('#', ...), [0]=select(1,...), select(2,...) }, Tuple)
end

Tuple = { }
Tuple.__index = Tuple
Tuple.__newindex = function(o,k,v) error("AccessError: are immutable!") end
Tuple.__guard = function(self, that)
   assert(getmetatable(that) == Tuple, 'TypeError: not a Tuple - '..tostring(that), 2)
   return that
end
Tuple.__tostring = function(self)
   return '[Tuple: '..sys.refaddr(self)..']'
end
Tuple.insert = function(self, idx, ...)
   local num = select('#', ...)
   local len = self.size
   for i=len - 1, idx, -1 do
      self[i + num] = self[i]
   end
   for i=1, num do
      self[idx] = select(i, ...)
      idx = idx + 1
   end
   self.size = len + num
end
Tuple.append = function(self, ...)
   return self:insert(self.size, ...)
end
Tuple.remove = function(self, idx, num)
   num = num or 1
   local len = self.size
   if len == 0 then return end
   local out = magic.tuple(self:unpack(idx, math.min(idx + num - 1, len)))
   for i=idx, len do
      self[i] = self[i + num]
   end
   for i=len, len - num + 1, -1 do
      self[i] = nil
   end
   self.n = len - num
   return out:unpack()
end
Tuple.unpack = function(self, ofs, len)
   return unpack(self, ofs or 0, len or self.size - 1)
end
Tuple.contains = function(self, m)
   for i,v in pairs(self) do
      if v == m then return i end
   end
   return false
end
Tuple.reverse = function(self)
   local l = self.size
   for i=0, math.floor(self.size / 2) do
      self[i], self[l-i] = self[l-i], self[i]
   end
   return self
end
Tuple.concat = function(self, ...)
   return table.concat(self, ...)
end
Tuple.__spread = function(self)
   return unpack(self, 0, self.size - 1)
end
Tuple.__newindex = function(self, key, val)
   if type(key) == "number" and key > self.size then
      self.size = key
   end
   rawset(self, key, val)
end
Tuple.__pairs = function(self)
   return function(obj, idx)
      idx = idx + 1
      if idx < obj.size then
         return idx, obj[idx]
      end
   end, self, -1
end
Tuple.__eq = function(self, that)
   if self.size ~= that.size then return false end
   for i=0, self.size - 1 do
      if self[i] ~= that[i] then return false end
   end
   return true
end
Tuple.__add = function(self, that)
   local out = magic.tuple(self:unpack())
   out:append(Tuple.unpack(that))
   return out
end
Tuple.__sub = function(self, that)
   local out = magic.tuple()
   for i,v in pairs(self) do
      if not that:contains(v) then
         out:append(v)
      end
   end
   return out
end
Tuple.__mul = function(self, that)
   local out = magic.tuple()
   for i,v in pairs(self) do
      out:append(magic.tuple(v, that[i]))
   end
   return out
end

global.Table = Table;
global.Array = Array;
global.Range = Range;
global.Tuple = Tuple;
global.Enum  = Enum;
global.print = print;
global.require = require;
global.select = select;
global.unpack = unpack;
global.assert = assert;

magic.range = function(min, max)
   return setmetatable({ min, max }, Range)
end

magic.enum = function(table)
   local enum = { }
   for i,v in ipairs(table) do
      enum[v] = i
   end
   return setmetatable(enum, Enum)
end

magic.new = function(class, ...)
   local self = class.__alloc()
   local constructor = class.__proto.this
   local retv
   if not constructor.missing then retv = constructor:get(self)(self, ...) end
   if retv ~= nil then return retv end
   return self
end

magic.throw = error
magic.try_catch = function(try, catch, finally)
   local ret
   if catch then
      ret = { select(2, xpcall(try, catch)) }
   else
      ret = { select(2, pcall(try)) }
   end
   if finally then
      if #ret == 0 then
         ret = { finally() }
      else
         finally()
      end
   end
   return ret
end

global.bless = setmetatable
magic.typeof = getmetatable

magic.has = function(this, key)
   if rawget(this, key) ~= nil then return true end
   local meta = getmetatable(this)
   if meta.__has then return meta.__has(this, key) end
   return meta.__proto[key] ~= nil
end
magic.instanceof = function(this, that)
   local base = getmetatable(this)
   local meta
   while base do
      if base == that then return true end
      meta = debug.getmetatable(base)
      if meta then
         base = rawget(meta, 'parent')
      else
         break
      end
   end
   return false
end

local bit = require"bit"
for _,m in ipairs{ "bor","band","bnot","bxor","lshift","rshift","arshift" } do
   magic[m] = bit[m]
end

magic.type = type
magic.rawget = rawget
magic.rawset = rawset
magic.select = select
magic.unpack = unpack
magic.tostring = tostring
magic.toboolean = function(obj)
   if type(obj) == 'boolean' then return obj end
   local meta = getmetatable(obj)
   if meta then
      local __toboolean = rawget(meta, '__toboolean')
      return __toboolean(obj)
   end
   return not(not obj)
end

magic.spread = function(obj)
   local meta = getmetatable(obj)
   if meta then
      local __spread = rawget(meta, '__spread')
      if __spread then return __spread(obj) end
   end
   return unpack(obj)
end

if not _G.jit then
   local _pairs = pairs
   pairs = function(obj)
      local meta = getmetatable(obj)
      if meta and meta.__pairs then return meta.__pairs(obj) end
      return _pairs(obj)
   end
end

magic.each = function(obj)
   if type(obj) == 'function' then return obj end
   return pairs(obj)
end
magic.cat = function(a, b)
   return tostring(a)..tostring(b)
end
magic.send = function(base, name, ...)
   return base[name](base, ...)
end
magic.pattern = function(patt)
   return re.compile(patt)
end
magic.regexp = function(patt, ...)
   return RegExp.new(patt, ...)
end

magic.package = function(desc)
   local curr = global
   for i=1, #desc.path - 1 do
      local frag = desc.path[i]
      local base = rawget(curr, frag)
      if not base then
         base = { }
         rawset(curr, frag, base)
      elseif type(curr) ~= "table" then
         error(string.format("name conflict for namespace '%s'", table.concat(path, '.')))
         break
      end
      curr = base
   end

   local pckg = Package.new(desc)
   curr[desc.name] = pckg.exports
   setfenv(2, pckg.environ)
   return pckg
end
magic.object = function(desc)
   local name = desc.name or '<anon>'
   local object = { __name = name }
   local proto = setmetatable({ }, Proto)
   object.__proto = proto

   local getmetatable = getmetatable

   object.__index = function(o, k)
      local k_m = getmetatable(k)
      if k_m and k_m.__getindex then
         return k_m.__getindex(k, o)
      else
         return object.__getvalue(o, proto[k])
      end
   end
   object.__newindex = function(o, k, v)
      local k_m = getmetatable(k)
      if k_m and k_m.__setindex then
         k_m.__setindex(k, o, v)
      else
         object.__setvalue(o, proto[k], v)
      end
   end

   object.__getvalue = function(o, k)
      return k:get(o)
   end
   object.__setvalue = function(o, k, v)
      k:set(o, v)
   end

   object.__tostring = function(o)
      return '[object '..name..': '..sys.refaddr(o)..']'
   end

   for i,trait in ipairs(desc.traits) do
      for k,v in pairs(trait.object.__proto) do
         if trait.spec.__elems__[k] then
            k = trait.spec.__elems__[k]
            v = v:clone()
            v.key = k
         end
         if proto[k].missing then
            proto[k] = v
         else
            error("TypeError: conflict in trait composition for "..tostring(k), 2)
         end
      end
   end

   for k,v in pairs(desc.slots) do
      local slot = Slot.new(v)
      if slot.modifier == 'static' then
         rawset(object, slot.key, slot.val())
      else
         proto[slot.name] = slot
      end
   end

   local environ = setmetatable({ }, { __index = getfenv(2) })
   for i,v in ipairs(desc.methods) do
      local meth = Method.new(v)
      local attr = v.attribute
      if attr ~= "" then
         local prev
         if i > 1 then
            prev = rawget(proto, desc.methods[i - 1].name)
         end
         local getset
         if attr == "get" then
            getset = function(self, obj)
               return meth.body(obj)
            end
         else
            getset = function(self, obj, val)
               meth.body(obj, val)
            end
         end
         if prev then
            prev[attr] = getset
         else
            meth[attr] = getset
         end
      end
      if meth.modifier == 'static' then
         rawset(object, meth.name, meth.body)
      else
         proto[meth.name] = meth
      end
      setfenv(meth.body, environ)
   end


   local rules = { }
   for k,v in pairs(desc.rules) do
      local rule = Rule.new(v, rules)
      proto[k] = rule
   end

   setmetatable(object, object)
   return object
end

magic.class = function(desc)
   local name = desc.name
   local class = { name = name }
   local proto = setmetatable({ }, Proto)
   class.__proto = proto

   local getmetatable = getmetatable

   class.__index = function(o, k)
      local k_m = getmetatable(k)
      if k_m and k_m.__getindex then
         return k_m.__getindex(k, o)
      else
         return class.__getvalue(o, proto[k])
      end
   end
   class.__newindex = function(o, k, v)
      local k_m = getmetatable(k)
      if k_m and k_m.__setindex then
         k_m.__setindex(k, o, v)
      else
         class.__setvalue(o, proto[k], v)
      end
   end

   class.__getvalue = function(o, k)
      return k:get(o)
   end
   class.__setvalue = function(o, k, v)
      k:set(o, v)
   end

   class.__tostring = function(o)
      return '['..name..': '..sys.refaddr(o)..']'
   end
   class.__alloc = function()
      return setmetatable({ }, class)
   end

   local environ = setmetatable({ }, { __index = getfenv(2) })
   if desc.parent then
      local base = desc.parent
      for k,v in pairs(base.__proto) do
         if rawget(proto,k) == nil then proto[k] = v end
         if getmetatable(v) == Method then
            desc.super[v.name] = v.body
         end
      end
      environ.super = desc.super
   end

   for i,trait in ipairs(desc.traits) do
      for k,v in pairs(trait.object.__proto) do
         if trait.spec.__elems__[k] then
            k = trait.spec.__elems__[k]
            v = v:clone()
            v.key = k
         end
         if proto[k].missing then
            proto[k] = v
         else
            error("TypeError: conflict in trait composition for "..tostring(k), 2)
         end
      end
   end

   for k,v in pairs(desc.slots) do
      local slot = Slot.new(v)
      if slot.modifier == 'static' then
         rawset(class, slot.key, slot.val())
      else
         proto[slot.name] = slot
      end
   end

   for i,v in ipairs(desc.methods) do
      local meth = Method.new(v)
      local attr = v.attribute
      if attr ~= "" then
         local prev
         if i > 1 then
            prev = rawget(proto, desc.methods[i - 1].name)
         end
         local getset
         if attr == "get" then
            getset = function(self, obj)
               return meth.body(obj)
            end
         else
            getset = function(self, obj, val)
               meth.body(obj, val)
            end
         end
         if prev then
            prev[attr] = getset
         else
            meth[attr] = getset
         end
      end
      if meth.modifier == 'static' then
         rawset(class, meth.name, meth.body)
      else
         proto[meth.name] = meth
      end
      setfenv(meth.body, environ)
   end

   local rules = { }
   for k,v in pairs(desc.rules) do
      proto[k] = Rule.new(v, rules)
   end

   return class
end

Like = { }
Like.__call = function(self, that)
   return self.body(that)
end
magic.like = function(spec)
   local fenv = setmetatable({ }, { __index = _G })
   local body = { 'local that=...' }
   for k,v in pairs(spec) do
      fenv[k] = v
      local n = string.format('%q', k)
      body[#body + 1] = 'that['..n..']='..k..'(that['..n..'])'
   end
   body[#body + 1] = 'return that'

   table.insert(body, 2, [[
if type(that) ~= "table" then
   error("TypeError: cannot coerce "..tostring(that).." to structure", 1)
end
]])

   body = assert(loadstring(table.concat(body, ';'), '=like'))
   setfenv(body, fenv)
   return setmetatable({ spec = spec, body = body }, Like)
end
magic.with = function(this, trait)
   local ometa = getmetatable(this)
   local proxy = { }
   local pmeta = { }
   local proto = { }
   if ometa.__proto then
      setmetatable(proto, { __index = ometa.__proto })
   else
      setmetatable(proto, Proto)
   end

   pmeta.__index = function(o, k)
      local k_m = getmetatable(k)
      if k_m and k_m.__getindex then
         return k_m.__getindex(k, o)
      else
         return pmeta.__getvalue(o, proto[k])
      end
   end
   pmeta.__newindex = function(o, k, v)
      local k_m = getmetatable(k)
      if k_m and k_m.__setindex then
         k_m.__setindex(k, o, v)
      else
         pmeta.__setvalue(o, proto[k], v)
      end
   end

   pmeta.__getvalue = function(o, k)
      return k:get(o)
   end
   pmeta.__setvalue = function(o, k, v)
      k:set(o, v)
   end

   pmeta.__tostring = rawget(ometa, '__tostring')
   pmeta.__concat   = rawget(ometa, '__concat')
   pmeta.__call     = rawget(ometa, '__call')
   pmeta.__add      = rawget(ometa, '__add')
   pmeta.__sub      = rawget(ometa, '__sub')
   pmeta.__mul      = rawget(ometa, '__mul')
   pmeta.__div      = rawget(ometa, '__div')
   pmeta.__mod      = rawget(ometa, '__mod')
   pmeta.__pow      = rawget(ometa, '__pow')

   if type(this) == 'string' then
      pmeta.__tostring = function(_) return tostring(this) end
      pmeta.__concat   = function(_, b) return tostring(this)..tostring(b) end
   end
   if type(this) == 'function' then
      pmeta.__call = function(_, ...) return this(...) end
   end
   if type(this) == 'number' then
      pmeta.__add = function(_, b) return this + b end
      pmeta.__sub = function(_, b) return this - b end
      pmeta.__mul = function(_, b) return this * b end
      pmeta.__div = function(_, b) return this / b end
      pmeta.__mod = function(_, b) return this % b end
      pmeta.__pow = function(_, b) return this ^ b end
   end

   for k,v in pairs(trait.object.__proto) do
      if trait.spec.__elems__[k] then
         k = trait.spec.__elems__[k]
         v = v:clone()
         v.key = k
      end
      if proto[k].missing then
         proto[k] = v
      else
         error("TypeError: conflict in trait composition for "..tostring(k), 2)
      end
   end

   return setmetatable(proxy, pmeta)
end

global.Any = function(...) return ... end
global.Number = function(val)
   val = tonumber(val)
   if type(val) == 'number' then return val end
   error('TypeError: cannot coerce to Number')
end
global.Integer = function(val)
   if type(val) ~= 'number' then val = assert(tonumber(val), 'TypeError: '..tostring(val)) end
   if math.floor(val) == val then return val end
   error("TypeError: cannot coerce to Integer")
end

global.String = getmetatable("")
global.String.__index = function(s, k)
   if k == 'length' then return #s end
   return string[k]
end
setmetatable(global.String, {
   __call = function(val)
      return tostring(val)
   end
})

global.Boolean = function(val)
   return not(not val)
end
global.Void = function(...)
   if select('#', ...) > 0 then
      error('TypeError: Void context')
   end
   return ...
end
global.LPeg = require'lpeg'
global.Lua  = _G

for k,v in pairs(magic) do
   global['__'..k..'__'] = v
end

global.Function = { }
global.Function.__index = { call = function(callee, ...) return callee(...) end }
global.Function.__coerce = function(obj)
   if type(obj) == 'function' then return obj end
   error("TypeError: cannot coerce "..tostring(obj).." to Function", 2)
end
debug.setmetatable(function() end, global.Function)

local rex = require"rex_onig"
RegExp = { }
RegExp.new = function(patt, ...)
   local self = { ['#pattern'] = rex.new(patt, ...) }
   return setmetatable(self, RegExp)
end
RegExp.__index = {
   match = function(self, ...) return self['#pattern']:match(...) end;
   gmatch = function(self, subj, ...) return rex.gmatch(subj, self['#pattern'], ...) end;
}

PATH = "./?.js;./lib/?.js;./src/?.js"
kudu.core.require = function(modname)
   local filename = modname:gsub("%.", "/")
   for path in PATH:gmatch"([^;]+)" do
      if path ~= "" then
         local filepath = path:gsub("?", filename)
         local file = io.open(filepath, "r")
         if file then
            local source = file:read("*a")
            local script   = Script.new(source, modname)
            local compiler = Compiler.new()
            local luacode  = compiler:compile(script)
            return script:execute(luacode)
         end
      end
   end
   error("LOADING FAILED! "..modname)
end

function init()
   local outer = getfenv(2) or { }
   setmetatable(outer, { __index = global })
   setfenv(2, outer)
end
