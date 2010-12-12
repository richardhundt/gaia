var i=0
while (i < 10) {
    i += 1
    if (i % 2 == 0) {
        print("got here")
        continue
    }
    print(i, i % 2)
}

