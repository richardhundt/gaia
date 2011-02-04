var lambda = { x => x + x }
print(lambda(21))

var a = [ 1, 2, 3, 4, 5 ]
var o = a.grep({ v => v % 2 == 1 })

for (v in o) {
    print("got: "~v)
}
