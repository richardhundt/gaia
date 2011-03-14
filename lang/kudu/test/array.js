var a = [ 'foo' ]
a[3] = 42
a.push('a')
a.push('b')
print("shift:", a.shift())
a.unshift('foo')
print("pop:", a.pop())

for i = 0, a.size - 1 {
    print(i, a[i])
}
for i, v in a {
    print(i, v)
}

var a = [ ]
for i=1, 10000000 {
    a.size = 0
    a.push(i)
    a.push(i)
    //a.pop(i)
    //a.pop(i)
}

for i, v in a {
    print(i, v)
}

var a = [ 0, 1, 2, 3, 4 ]
a.splice(1, 1, "foo")
print("splice delta == 0")
for i, v in a {
    print(i, v)
}

var a = [ 0, 1, 2, 3, 4 ]
a.splice(0, 0, "foo", "bar")
print("splice delta == 2")
for i, v in a {
    print(i, v)
}

var a = [ 0, 1, 2, 3, 4 ]
a.splice(0, 0, "a","b","c")
for i, v in a {
    print(i, v)
}

