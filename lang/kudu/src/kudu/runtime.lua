local _G = _G
module("kudu.runtime", package.seeall)

require "sys"
require "sys.sock"
require "marshal"
require "kudu.compiler"

local rawget, rawset, type = rawget, rawset, type
local getfenv, setfenv, assert = getfenv, setfenv, assert
local getmetatable, setmetatable = getmetatable, setmetatable
local pairs, ipairs, rawequal, next = pairs, ipairs, rawequal, next

local _M = _M
_M.global = { }

do
   local string_meta = getmetatable("")
   local string_table = string_meta.__index
   string_meta.__index = function(self, key)
      if key == 'length' then return #self end
      return string_table[key]
   end
end

MetaClass = {
   __tostring = function(self) return self.__name__ end;
   __newindex = function()
      error("attempt to decorate a class", 2)
   end
}

Class = { __name__ = 'Class' }
setmetatable(Class, MetaClass)

Role = { __name__ = 'Role' }
setmetatable(Role, MetaClass)

Module = { }
Module.__index = { }
Module.__index.export = function(self, key)
   self.exports[#self.exports + 1] = key
end

Module.__index.import = function(self, path, env)
   local pkg,sym = path:match"^(.-)%.([^.]+)$"
   local mod = _G.require(pkg)
   env[sym] = mod.environ[sym]
end
Module.__index.define = function(self, sym, val)
   self.environ[sym] = val
end
Module.__index.lookup = function(self, sym)
   local val = self.environ[sym]
   if val == nil then
      error(("%q is not defined in %q"):format(sym, self.name), 2)
   end
   return val
end
Module.new = function(name)
   local self = setmetatable({
      exports = { };
      imports = { };
      environ = { };
      name    = name;
   }, Module)
   setmetatable(self.environ, { __index = _M.global })
   self.environ.__package__ = self
   return self
end

kudu.package = { }
kudu.package.create = function(name)
   local mod = Module.new(name)
   kudu.package.current = mod
   setfenv(2, mod.environ)
   return mod
end
kudu.package.export = function(key)
   kudu.package.current:export(key)
end
kudu.package.import = function(from)
   local into = getfenv(2)
   kudu.package.current:import(from, into)
end

kudu.package.current = Module.new("__main__")

kudu.class = { }
kudu.class.create = function(name)
   local attrs = { }
   local meths = { }
   local roles = { }
   local cdata = setmetatable({ }, { __index = Class })
   local class = { __name__ = name or '<anon>' }

   local private   = { attribs = { }, methods = { }, getters = { }, setters = { } }
   local protected = { attribs = { }, methods = { }, getters = { }, setters = { } }
   local public    = { attribs = { }, methods = { }, getters = { }, setters = { } }

   local meta  = {
      name    = name;
      static  = cdata;

      public    = public;
      private   = private;
      protected = protected;

      parent  = { };
      __metatable = Class;
      __index     = cdata;
      __tostring  = function(class) return name end;
      __call      = function(class, ...)
         local self = { }
         setmetatable(self, class)
         local constructor = meths.this
         if constructor then constructor(self, ...) end
         return self
      end;
   }
   setmetatable(class, meta)

   local rawget, rawset = rawget, rawset

   local attrs = private.attribs
   local meths = private.methods
   local getts = private.getters
   local setts = private.setters

   local function __index(obj, key)
      local attr = attrs[key]
      if attr then
         local val = rawget(obj, attr)
         if val == nil and attr.default ~= nil then
            val = attr.default
            if type(val) == "table" then
               local tmp = val
               val = table.clone(tmp)
               setmetatable(val, getmetatable(tmp))
            end
            rawset(obj, attr, val)
         end
         return val
      end
      local meth = meths[key]
      if meth then
         rawset(obj, key, meth)
         return meth
      end
      if key == '__meta__' then
         return meta
      end
      local get = getts[key]
      if get then return get(obj) end

      error("AccessError: attempt to get '"..tostring(key).."' in "..name, 2)
   end
   local function __newindex(obj, key, val)
      local attr = attrs[key]
      if attr ~= nil then
         return rawset(obj, attr, val)
      end
      local meth = meths[key]
      if meth then
         if type(val) == "function" then
            return rawset(obj, key, val)
         end
      end
      local set = setts[key]
      if set then return set(obj, val) end
      error("AccessError: attempt to set '"..tostring(key).."' in "..name, 2)
   end

   class.__index = __index
   class.__newindex = __newindex;
   class.__tostring = function(obj) return "["..name..": "..sys.refaddr(obj).."]" end

   kudu.package.current:define(name, class)

   return class
end

kudu.instanceof = function(this, that)
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

local visibility = {
   private   = 1,
   protected = 2,
   public    = 3,
   ['']      = 3,
}

kudu.class.add_method = function(class, name, body, modifier, attribute)
   local meta = debug.getmetatable(class)
   if modifier == 'static' then
      meta.static[name] = body
   else
      local short_name = name
      if attribute ~= nil and attribute ~= '' then
         name = '__'..attribute..'_'..name
      end
      meta.private.methods['!'..name] = body
      if attribute == 'set' then
         meta.private.setters[short_name] = body
      elseif attribute == 'get' then
         meta.private.getters[short_name] = body
      end
      if visibility[modifier] > visibility['private'] then
         meta.protected.methods['!'..name] = body
         if attribute == 'set' then
            meta.protected.setters[short_name] = body
         elseif attribute == 'get' then
            meta.protected.getters[short_name] = body
         end
      end
      if visibility[modifier] > visibility['protected'] then
         meta.public.methods['!'..name] = body
         meta.public.methods[name] = body
         meta.private.methods[name] = body
         meta.protected.methods[name] = body
         if attribute == 'set' then
            meta.public.setters[short_name] = body
         elseif attribute == 'get' then
            meta.public.getters[short_name] = body
         end
      end
   end
end
kudu.class.add_attrib = function(class, name, default, modifier)
   local meta = debug.getmetatable(class)
   if modifier == 'static' then
      meta.static[name] = default
   else
      local attr = { name = name, default = default, modifier = modifier }
      meta.private.attribs['!'..name] = attr
      if visibility[modifier] > visibility['private'] then
         meta.protected.attribs['!'..name] = attr
      end
      if visibility[modifier] > visibility['protected'] then
         meta.public.attribs['!'..name] = attr
         meta.public.attribs[name] = attr
      end
   end
end
kudu.class.add_classdata = function(class, name, info)
   local meta = debug.getmetatable(class)
   meta.static[name] = info
end
kudu.class.extend = function(class, base)
   local meta  = debug.getmetatable(class)
   meta.parent = base
   local base_meta = debug.getmetatable(base)

   setmetatable(meta.private.attribs, { __index = base_meta.protected.attribs })
   setmetatable(meta.private.methods, { __index = base_meta.protected.methods })
   setmetatable(meta.static, { __index = base_meta.static })

   return base_meta.protected.methods
end
kudu.class.mixin = function(class, role)
   local meta = debug.getmetatable(role)
   for name,info in pairs(meta.attribs) do
      kudu.class.add_attrib(class, name, info.default, info.modifier)
   end
   for name,func in pairs(meta.methods) do
      kudu.class.add_method(class, name, func, meta.method_modifiers[func])
   end
end

kudu.alloc = function(class, ...)
   if class == nil then
      error("class is nil", 2)
   end
   local meta = debug.getmetatable(class)
   if meta.alloc then return meta.alloc() end
   local self = { }
   setmetatable(self, class)
   local constructor = meta.private.methods.this
   if constructor then constructor(self, ...) end
   return self
end

kudu.role = { }
kudu.role.create = function(name)
   local attrs = { }
   local meths = { }
   local roles = { }
   local cdata = setmetatable({ }, { __index = Role })
   local role  = { __name__ = name or '<anon>' }
   local meta  = {
      name    = name;
      attribs = attrs;
      methods = meths;
      static  = cdata;
      method_modifiers = { };
      parent  = { };
      __metatable = Role;
      __index     = function(o,k)
         local attr = attrs[k]
         if attr then return attr.default end
         local meth = meths[k]
         if meth then return meth end
         local data = cdata[k]
         if data ~= nil then return data end
         error("AccessError: attempt to get '"..k.."' in "..name, 2)
      end;
      __newindex = function(o, k, v)
         local attr = attrs[k]
         if attr then return rawset(o, attr, v) end
         error("AccessError: attempt to set '"..k.."' in "..name, 2)
      end;
      __tostring  = function(role) return name end;
   }
   setmetatable(role, meta)
   kudu.package.current:define(name, role)
   return role
end
kudu.role.add_method = function(role, name, body, modifier)
   local meta = debug.getmetatable(role)
   if modifier == 'static' then
      meta.static[name] = body
   else
      local meth = body
      meta.methods['!'..name] = meth
      if modifier ~= 'private' then
         meta.methods[name] = meth
      end
   end
end
kudu.role.add_attrib = function(role, name, default, modifier)
   local meta = debug.getmetatable(role)
   if modifier == 'static' then
      meta.static[name] = default
   else
      local attr = { name = name, default = default, modifier = modifier }
      meta.attribs['!'..name] = attr
      if modifier ~= 'private' then
         meta.attribs[name] = attr
      end
   end
end
kudu.role.add_classdata = function(role, name, info)
   local meta = debug.getmetatable(role)
   meta.static[name] = info
end
kudu.role.mixin = function(role, with)
   local meta = debug.getmetatable(with)
   for name,info in pairs(meta.attribs) do
      kudu.role.add_attrib(role, name, info.default, info.modifier)
   end
   for name,func in pairs(meta.methods) do
      kudu.role.add_method(role, name, func, meta.method_modifiers[func])
   end
end

Table = { }
Table.__index = function(self, key)
   if key == 'length' then return #self end
   return Table[key]
end
Table.__tostring = function(self) return '[Table: '..sys.refaddr(self)..']' end
Table.__each = function(self)
   local k
   return function()
      k = next(self, k)
      return k, self[k]
   end
end
Table.__get_index = function(self, key)
   return self[key]
end
Table.__set_index = function(self, key, val)
   self[key] = val
end

function kudu.table(table)
   return setmetatable(table, Table)
end

Array = { }
Array.__index = Array
Array.__call = function(self, ...)
   if type(self.data[0]) == 'function' then
      local args = { unpack(self.data) }
      for i=1, select('#', ...) do
         args[#args + 1] = select(i, ...)
      end
      return self.data[0](unpack(args))
   end
   error("Array is not callable", 2)
end
Array.__get_index = function(self, key)
   return self.data[key]
end
Array.__set_index = function(self, key, val)
   if key >= self.length then self.length = key + 1 end
   self.data[key] = val
end
Array.__each = function(self)
   local i = 0
   local t = self.data
   local l = self.length
   return function()
      if i >= l then return nil end
      local k = i
      local v = t[k]
      i = i + 1
      return k, v
   end
end
Array.push = function(self, val)
   self.data[self.length] = val
   self.length = self.length + 1
end
Array.pop = function(self)
   if self.length < 1 then return nil end
   self.length = self.length - 1
   local val = self.data[self.length]
   self.data[self.length] = nil
   return val
end
Array.shift = function(self)
   if self.length < 1 then return nil end
   local val = self.data[0]
   self.length = self.length - 1
   for i=0, self.length do
      self.data[i] = self.data[i + 1]
   end
   self.data[self.length] = nil
   return val
end
Array.unshift = function(self, val)
   for i=self.length, 0, -1 do
      self.data[i] = self.data[i-1]
   end
   self.length = self.length + 1
   self.data[0] = val
end
Array.grep = function(self, func)
   local out = kudu.array{ }
   for i, v in self:__each() do
      if func(v) == true then
         out:push(v)
      end
   end
   return out
end
Array.map = function(self, func)
   local out = kudu.array{ }
   for i, v in self:__each() do
      out:push(func(v))
   end
   return out
end
Array.each = function(self, func)
   for i, v in self:__each() do
      func(i, v)
   end
end

kudu.array = function(data)
   local self = { data = data or { } }
   self.length = #self.data
   self.data[0] = table.remove(self.data, 1)
   return setmetatable(self, Array)
end

Enum = { }
Enum.__index = Enum
kudu.enum = function(table)
   local enum = { }
   for i,v in ipairs(table) do
      enum[v] = i
   end
   return setmetatable(enum, Enum)
end

Range = { }
Range.__index = Range
Range.__each = function(self)
   local cur = self[1] - 1
   local max = self[2]
   return function()
      cur = cur + 1
      if cur <= max then
         return cur
      end
   end
end

kudu.range = function(min, max)
   return setmetatable({ min, max }, Range)
end
kudu.throw = error
kudu.try_catch = function(try, catch, finally)
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

kudu.path = "./?.js;./lib/?.js;./src/?.js"
package.loaders[#package.loaders + 1] = function(modname)
   local filename = modname:gsub("%.", "/")
   for path in kudu.path:gmatch"([^;]+)" do
      if path ~= "" then
         local filepath = path:gsub("?", filename)
         local file = io.open(filepath, "r")
         if file then
            local source = file:read("*a")
            local chunk = kudu.compiler.compile(source, filepath, { })
            local modfunc = loadstring(chunk)
            local modenv = getfenv(modfunc)
            local mod
            if modenv and modenv.__package__ then
               mod = modenv.__package__
            else
               mod = Module.new(modname)
               setfenv(modfunc, mod.environ)
            end
            package.loaded[modname] = mod
            return modfunc
         end
      end
   end
end
kudu.runfile = function(filename, options)
   local source = io.open(filename):read("*a")
   local chunk = kudu.compiler.compile(source, filename, options)
   local main = assert(loadstring(chunk, "="..filename))
   setfenv(main, _M.global)
   main()
end

kudu.init = function() end

local bit = require"bit"
_M.global["__bor__"] = bit.bor
_M.global["__band__"] = bit.band
_M.global["__bnot__"] = bit.bnot
_M.global["__bxor__"] = bit.bxor
_M.global["__lshift__"] = bit.lshift
_M.global["__rshift__"] = bit.rshift
_M.global["__arshift)"] = bit.arshift
_M.global["__alloc__"] = kudu.alloc
_M.global["__table__"] = kudu.table
_M.global["__array__"] = kudu.array
_M.global["__range__"] = kudu.range
_M.global["__class_create__"] = kudu.class.create
_M.global["__class_extend__"] = kudu.class.extend
_M.global["__class_add_meth__"] = kudu.class.add_method
_M.global["__class_add_attr__"] = kudu.class.add_attrib
_M.global["__class_mixin__"] = kudu.class.mixin
_M.global["__role_create__"] = kudu.role.create
_M.global["__role_add_meth__"] = kudu.role.add_method
_M.global["__role_add_attr__"] = kudu.role.add_attrib
_M.global["__role_mixin__"] = kudu.role.mixin
_M.global["__throw__"] = kudu.throw
_M.global["__try_catch__"] = kudu.try_catch
_M.global["__select__"] = select
_M.global["__unpack__"] = unpack
_M.global["__package_create__"] = kudu.package.create
_M.global["__package_export__"] = kudu.package.export
_M.global["__package_import__"] = kudu.package.import
_M.global["__init__"] = kudu.init
_M.global["__typeof__"] = getmetatable
_M.global["__instanceof__"] = kudu.instanceof
_M.global["__invoke_late__"] = function(base, meth, this, ...)
   local func = base[meth]
   this = this == nil and base or this
   return func(this, ...)
end
_M.global.assert = _G.assert
_M.global.magic = _G
_M.global.print = _G.print
_M.global.require = _G.require
_M.global.select  = _G.select
_M.global.kudu = kudu

function kudu.load()
   setfenv(2, kudu.package.current.environ)
end

_M.global.RegExp = require'std.regexp'.RegExp
