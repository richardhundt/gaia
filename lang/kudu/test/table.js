var t = { }
t.answer = function() {
    print("Hello from: " ~ this)
}

t.answer()

var t = { foo : 'bar', baz : 'quux' }
for (k,v in t) {
    print(k, v)
}

