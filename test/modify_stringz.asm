.ORIG x3000

    lea r0 String
    str r1 r0 #0
    str r1 r0 #1
    str r1 r0 #2

    halt

String .STRINGZ "Test"

.END
