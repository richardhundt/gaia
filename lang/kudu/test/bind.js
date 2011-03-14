var a, b;
a, b = 1, 2

var a = { b = function(this) { print("hey from:", this) } }
a['b']()

var a, b, c = { }, { }
a.foo = { }
a.foo['bar'], c = 42, 69
print(a.foo['bar'], c)
a.foo = function(this) { print("Hey Globe from " ~ this) }
a.foo()
