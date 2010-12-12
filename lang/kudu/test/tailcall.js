
/*
function doit(whom, greet) {
    return greet("Hello", whom)
}

var a, b = doit("Felix", function(x, y) {
    return x, y
})

print(a, b)
*/

function a(x,y) {
    return x,y
}
function b() {
    return a("Hello", "Felix")
}
var x, y = b();
print(x, y)
