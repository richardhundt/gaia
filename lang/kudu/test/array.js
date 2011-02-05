var a = [ 'foo' ]
a[3] = 42
a.push('a')
a.push('b')
print("shift:", a.shift())
a.unshift('foo')
print("pop:", a.pop())
for (i = 0, a.length - 1) {
    print(i, a[i])
}

var greet = [ print, "Hello" ]
greet("World!")

