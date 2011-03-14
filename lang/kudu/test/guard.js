var n : Number = 42
for i=1, 10000000 {
    n = i
}

function doit(num :Number) {
    print("got:", num)
}
doit(42)

function timestwo(num :Number) :like { num = Number } {
    return { num = num + num }
}

print(timestwo(21).num)
var t = { answer : Number = 42 }
var g = like { answer = Number }
var t = { answer = 42 }
var a : g = t

for i=1, 10000000 {
    timestwo(i)
}

