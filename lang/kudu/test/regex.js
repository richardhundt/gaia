var rx = RegExp('(\w+) (\w+)')
var a,b = rx.match('foo bar')
print(a,b)
var m = RegExp('\s+').split('foo bar baz')
for (i,v in m) {
    print(v)
}

