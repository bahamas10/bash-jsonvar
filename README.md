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
2. Filters out variables that start with `_jv_` since they are used internally,
   use `jsonvar -x internal ...` to allow them (see Experimental)
3. Sparse arrays are squished when exported, use `jsonvar -x sparse ...` to
   keep their indices (see Experimental)
4. Namerefs are not supported and will result in a `null` representation

Experimental
------------

Experimental features live in `experiments.bash`. If it's next to
`jsonvar.bash` they're loaded and listed in `jsonvar -h`, without it `-x`
gives an error.

``` bash
jsonvar -x types foo
jsonvar foo -x '[sparse, types, bytes]'
```

- `internal` allow variables named `_jv_*`
- `sparse` keep the indices of sparse arrays, as an object
- `types` print `true`, `false`, `null` and numbers in strings as JSON types
- `bytes` escape strings that aren't valid utf-8 byte by byte instead of `null`

`./experiments.bash merge` makes `jsonvar.exp.bash`, a single file with
`experiments.bash` put in place of where `jsonvar.bash` sources it. Lines from
`[[exp del tag start]]` to `[[exp del tag finish]]` are left out of it.

YouTube
-------

Watch me build this live on YouTube.

<a href="https://www.youtube.com/watch?v=GXw67QpDPCE"><img alt="Bash jsonvar YouTube
Thumbnail" src="https://files.daveeddy.com/ysap/bash-jsonvar-thumbnail.jpg"
/></a>

License
-------

MIT License
