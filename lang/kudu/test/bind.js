var a, b, c = { }, { }
a.foo = function() { return function() { return b } }
a.foo()()['bar'], c = 42, 69
print(b.bar, c)
