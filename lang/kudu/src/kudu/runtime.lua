local _G = _G
module("kudu.runtime", package.seeall)

require "sys"
require "marshal"
require "kudu.compiler"

local rawget, rawset, type = rawget, rawset, type
local getfenv, setfenv, assert = getfenv, setfenv, assert
local getmetatable, setmetatable = getmetatable, setmetatable
local pairs, ipairs, rawequal, next = pairs, ipairs, rawequal, next

function kpairs(t)
   local k
   if #t > 0 then k = #t end
   return function()
      k, v = next(t, k)
      return k, v
   end
end

local _M = _M
_M.global = { }

kudu.null = newproxy(true)

local null = kudu.null
local null_arith = function()
   error("attempt to perform arithmetic on a null value")
end
local null_meta = getmetatable(null)
null_meta.__add = null_arith;
null_meta.__sub = null_arith;
null_meta.__mul = null_arith;
null_meta.__pow = null_arith;
null_meta.__div = null_arith;
null_meta.__mod = null_arith;
null_meta.__tostring = function() return "null" end;

Type = { }
Type.__index = Type
Type.__tostring = function(self) return self.name end
function Type.new(name, check)
   local self = { name = name, check = check }
   return setmetatable(self, Type)
end
function Type:assertTypeOf(value, level)
   if self.check(value) then
      return value
   else
      error("TypeError: "..tostring(value).." is not a "..self.name, (level or 1) + 2)
   end
end
function Type:isTypeOf(value)
   return self.check(value)
end

Any     = Type.new("Any", function(v) return v ~= null end)
Null    = Type.new("Null", function(v) return v == null end)
Number  = Type.new("Number", function(v) return type(v) == "number" end)
String  = Type.new("String", function(v) return type(v) == "string" end)
Boolean = Type.new("Boolean", function(v) return type(v) == "boolean" end)

MetaClass = {
   __tostring = function(self) return self.name end;
   __newindex = function()
      error("attempt to decorate a class", 2)
   end
}

Class = { }
Class.isTypeOf = function(class, value)
   local meta = getmetatable(value)
   while meta do
      if meta == class then
         return true
      end
      meta = meta.parent
   end
end
Class.assertTypeOf = function(class, value)
   if class:isTypeOf(value) then
      return value
   else
      local ty = value == null and "null" or type(value)
      error("TypeError: expected "..class.name.." but got "..ty, (level or 1) + 2)
   end
end
setmetatable(Class, MetaClass)

Role = { }
Role.isTypeOf = function(role, value)
   local meta = getmetatable(value)
   while meta do
      if meta.roles[role] then
         return true
      end
      meta = meta.parent
   end
end
Role.assertTypeOf = function(class, value)
   if class:isTypeOf(value) then
      return value
   else
      local ty = value == null and "null" or type(value)
      error("TypeError: expected "..class.name.." but got "..ty, 3)
   end
end
setmetatable(Role, MetaClass)

Method = { }
Method.new = function(spec)
   spec.call = function(call, ...) return call(...) end;
   return setmetatable(spec, {
      __metatable = Method;
      __call      = function(func, ...) return spec.body(...) end;
      name        = spec.name;
      info        = spec.info;
      body        = spec.body;
   })
end

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
   local class = { }
   local meta  = {
      name    = name;
      attribs = attrs;
      methods = meths;
      static  = cdata;
      parent  = { };
      __metatable = Class;
      __index     = cdata;
      __tostring  = function(class) return name end;
      __call      = function(class, _, ...)
         local self = { }
         setmetatable(self, class)
         local constructor = meths.this
         if constructor then constructor(self, ...) end
         return self
      end;
   }
   setmetatable(class, meta)
   local rawget, rawset = rawget, rawset
   local function __index(obj, key)
      if obj[key] ~= nil then return obj[key] end
      local attr = attrs[key]
      if attr then
         if attr.default ~= nil then
            val = attr.default
            if type(val) == "table" then
               local tmp = val
               val = table.clone(tmp)
               setmetatable(val, getmetatable(tmp))
            end
         else
            val = null
         end
         obj[key] = val
         return val
      end
      local meth = meths[key]
      if meth then
         rawset(obj, key, val)
         return meth
      end
      if key == '__meta__' then
         return meta
      end
      error("AccessError: attempt to get '"..tostring(key).."' in "..name, 2)
   end
   local function __newindex(obj, key, val)
      local attr = attrs[key]
      if attr ~= nil then
         return rawset(obj, key, val)
      end
      if meths[key] ~= nil then
         if type(val) == "function" then
            return rawset(obj, key, val)
         end
      end
      error("AccessError: attempt to set '"..tostring(key).."' in "..name, 2)
   end

   class.__index = meths
   meths.__get_member = __index;
   meths.__set_member = __newindex;
   meths.__to_string = function(obj) return "["..name..": "..sys.refaddr(obj).."]" end
   class.__tostring = function(obj) return obj:__to_string() end

   kudu.package.current:define(name, class)

   return class
end
kudu.class.add_method = function(class, name, body)
   local meta = debug.getmetatable(class)
   local fenv = setmetatable({ }, { __index = getfenv(body) })
   local parent_methods
   if meta.parent then
      local parent_meta = debug.getmetatable(meta.parent)
      parent_methods = parent_meta and parent_meta.methods or { }
   end
   fenv.super = parent_methods
   setfenv(body, fenv)
   meta.methods[name] = body
end
kudu.class.add_attrib = function(class, name, default)
   local meta = debug.getmetatable(class)
   meta.attribs[name] = { default = default == nil and null or default }
end
kudu.class.add_classdata = function(class, name, info)
   local meta = debug.getmetatable(class)
   meta.static[name] = info
end
kudu.class.extend = function(class, base)
   local base_meta = debug.getmetatable(base)
   local meta  = debug.getmetatable(class)
   meta.parent = base
   setmetatable(meta.attribs, { __index = base_meta.attribs })
   setmetatable(meta.methods, { __index = base_meta.methods })
   setmetatable(meta.static,  { __index = base_meta.static  })
end
kudu.class.mixin = function(class, role)
   local meta = debug.getmetatable(role)
   for name,info in pairs(meta.attribs) do
      kudu.class.add_attrib(class, name, info)
   end
   for name,func in pairs(meta.methods) do
      kudu.class.add_method(class, name, func)
   end
end

kudu.alloc = function(class, ...)
   if class == nil then
      error("class is nil", 2)
   end
   local self = { }
   setmetatable(self, class)
   local constructor = debug.getmetatable(class).methods.this
   if constructor then constructor(self, ...) end
   return self
end

kudu.role = { }
kudu.role.create = function(name)
   local attrs = { }
   local meths = { }
   local roles = { }
   local cdata = setmetatable({ }, { __index = Role })
   local role  = { }
   local meta  = {
      name    = name;
      attribs = attrs;
      methods = meths;
      static  = cdata;
      parent  = { };
      __metatable = Role;
      __index     = cdata;
      __tostring  = function(role) return name end;
   }
   setmetatable(role, meta)
   kudu.package.current:define(name, role)
   return role
end
kudu.role.add_method = function(role, name, body, info)
   local meta = debug.getmetatable(role)
   local fenv = setmetatable({ }, { __index = getfenv(body) })
   fenv.super = setmetatable({ }, {
      __index = function(role, key) return debug.getmetatable(meta.parent)[key] end
   })
   setfenv(body, fenv)
   meta.methods[name] = body
end
kudu.role.add_attrib = function(role, name, info)
   local meta = debug.getmetatable(role)
   meta.attribs[name] = info
end
kudu.role.add_classdata = function(role, name, info)
   local meta = debug.getmetatable(role)
   meta.static[name] = info
end
kudu.role.mixin = function(role, with)
   local meta = debug.getmetatable(with)
   for name,info in pairs(meta.attribs) do
      kudu.role.add_attrib(role, name, info)
   end
   for name,func in pairs(meta.methods) do
      local func_meta = debug.getmetatable(func)
      kudu.role.add_method(role, name, func_meta.body, func_meta.info)
   end
end

kudu.type_assert = function(value, vtype, nullable)
   if value == nil then value = null end
   if nullable and value == null then return value end
   if not vtype:isTypeOf(value) then
      local got_type
      if value == null then
         got_type = "null value"
      else
         got_type = type(value)
      end
      error("TypeError: expected "..tostring(vtype).." but got a "..got_type, 2)
   end
   return value
end

Table = { }
Table.__index = Table
Table.getKeyValueIterator = function(self)
   local k, v
   if #self > 0 then self = #self end
   return function(t)
      k, v = next(t, k)
      return k, v
   end, self
end
Table.getKeyIterator = function(self)
   local k
   if #self > 0 then self = #self end
   return function(t)
      k = next(t, k)
      return k
   end, self
end
Table.getValueIterator = function(self)
   local k
   if #self > 0 then self = #self end
   return function(t)
      k, v = next(t, k)
      return v
   end, self
end
Table.__get_member = function(self, key)
   return self[key]
end
Table.__set_member = function(self, key, val)
   self[key] = val
end
Table.__get_index = function(self, key)
   return self[key]
end
Table.__set_index = function(self, key, val)
   self[key] = val
end
--[[ currently abandoned, for consideration
Table.__get_symbol = function(self, key)
   return self[key]
end
Table.__set_symbol = function(self, key, val)
   self[key] = val
end
--]]

function kudu.table(table)
   for k,v in pairs(table) do
      print("table => ", k, v)
   end
   return setmetatable(table, Table)
end

Array = { }
Array.__index = Array
Array.__get_index = function(self, key)
   return self.data[key]
end
Array.__set_index = function(self, key, val)
   self.data[key] = val
end
Array.__get_member = function(self, key)
   if key == "length" then
      return #self.data + 1
   else
      return Array[key]
   end
end

--[[
Array.__index = function(self, key)
   if key == "length" then
      return #self + 1
   else
      return Array[key]
   end
end
--]]
Array.getKeyValueIterator = function(self)
   local i = 0
   return function(t)
      local v = t[i]
      local k = i
      i = i + 1
      if v ~= nil then
         return k, v
      else
         return nil
      end
   end, self
end
Array.getValueIterator = function(self)
   local i =  0
   return function(t)
      local v = t[i]
      i = i + 1
      return v
   end, self
end
Array.push = function(self, val)
   if val == nil then val = null end
   self.data[#self.data + 1] = val
end
Array.pop = function(self)
   return table.remove(self.data)
end

kudu.array = function(data)
   local self = { data = data or { } }
   self.data[0] = table.remove(self.data, 1)
   return setmetatable(self, Array)
end

Range = { }
Range.__index = Range
Range.getKeyValueIterator = function(self)
   return self:getValueIterator()
end
Range.getKeyIterator = function(self)
   return self:getValueIterator()
end
Range.getValueIterator = function(self)
   local cur = self[1] - 1
   local max = self[2]
   return function(t)
      cur = cur + 1
      if cur <= max then
         return cur
      end
   end, self
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
   local main = loadstring(chunk)
   setfenv(main, _M.global)
   main()
end

kudu.init = function() end

local bit = require"bit"
_M.global["(bor)"] = bit.bor
_M.global["(band)"] = bit.band
_M.global["(bnot)"] = bit.bnot
_M.global["(bxor)"] = bit.bxor
_M.global["(lshift)"] = bit.lshift
_M.global["(rshift)"] = bit.rshift
_M.global["(arshift)"] = bit.arshift
_M.global["(null)"] = kudu.null
_M.global["(alloc)"] = kudu.alloc
_M.global["(table)"] = kudu.table
_M.global["(array)"] = kudu.array
_M.global["(range)"] = kudu.range
_M.global["(type_assert)"] = kudu.type_assert
_M.global["(class_create)"] = kudu.class.create
_M.global["(class_extend)"] = kudu.class.extend
_M.global["(class_add_meth)"] = kudu.class.add_method
_M.global["(class_add_attr)"] = kudu.class.add_attrib
_M.global["(class_mixin)"] = kudu.class.mixin
_M.global["(role_create)"] = kudu.role.create
_M.global["(role_add_meth)"] = kudu.role.add_method
_M.global["(role_add_attr)"] = kudu.role.add_attrib
_M.global["(role_mixin)"] = kudu.role.mixin
_M.global["(throw)"] = kudu.throw
_M.global["(try_catch)"] = kudu.try_catch
_M.global["(select)"] = select
_M.global["(unpack)"] = unpack
_M.global["(package_create)"] = kudu.package.create
_M.global["(package_export)"] = kudu.package.export
_M.global["(package_import)"] = kudu.package.import
_M.global["(init)"] = kudu.init
_M.global.magic = _G
_M.global.print = function(_, ...)
   return print(...)
end
_M.global.require = function(...) return _G.require(...) end
_M.global.kudu = kudu

function kudu.load()
   setfenv(2, kudu.package.current.environ)
end

