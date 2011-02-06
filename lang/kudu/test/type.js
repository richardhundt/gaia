class A { }
class B extends A { }
class C extends B { }

var b = new B()

assert("typeof:", typeof b)
assert("instanceof:", b instanceof B)
assert("instanceof:", b instanceof B)
assert("instanceof:", !(b instanceof C))
assert(typeof(typeof b))

if (typeof b == B) {
    print("Yup")
}
