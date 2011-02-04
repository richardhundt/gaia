var a, b, c = { }, { }
a.foo = { }
a.foo['bar'], c = 42, 69
print(a.foo['bar'], c)
a.foo = function() { print("Hey Globe from " ~ this) }
a.foo()
