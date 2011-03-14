local Package = { }

Package.__index = Package
Package.new = function(desc)
   local self = { name = desc.name, environ = { }, exports = { } }
   self.private.__exports__ = self.exports
   self.private.__environ__ = self.environ
   setmetatable(self.environ, {
      __index    = kudu.core.global;
      __newindex = function(e, k, v)
         self.exports[k] = v
         rawset(e, k, v)
      end
   })
   return setmetatable(self, Package)
end

return Package

