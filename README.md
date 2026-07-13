bash-jsonvar
============

Export variables in bash to JSON

Usage
-----

``` bash
. ./jsonvar.bash # source the library

foo='a'
bar='b'
baz='c'

jsonvar foo
# {
#    "foo": "a"
# }

jsonvar foo bar baz
# {
#    "foo": "a",
#    "bar": "b",
#    "baz": "c"
# }

bat=(d e f)
jsonvar bat
# {
#    "bat": ["d","e","f"]
# }

jsonvar -v foo
# "a"

jsonvar -v foo bar baz bat
# "a",
# "b",
# "c"
# ["d", "e", "f"]

jsonvar -a # show all defined variables
jsonvar -e # show only environment (exported) variables
```

Known Limitations
-----------------

1. Only handles variable names that bash considers valid
2. Filters out variables that start with `_jv_` since they are used internally
3. Sparse arrays are squished when exported

License
-------

MIT License
