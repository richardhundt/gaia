var e = ( 1 + 2 * 3 ) * 1
print(e)
var t = ( 1, 2, 3, ( 4, 5 ) )
print(t, ...t)
print(t[0])
var t = (0+1,1+1)
var f = function(a,b,c) {
    print(...a)
}

f((1,2,3))

