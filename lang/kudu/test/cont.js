var i=0
while (i < 10) {
    i += 1
    if (i % 2 == 0) {
        print("got here")
        continue
    }
    for (i in 1..10) {
        if (i > 3) break
        print("inner:", i)
    }
    if (i == 5) break
    print(i, i % 2)
}

