.PHONY: check
check:
	bash -n jsonvar.bash

.PHONY: test
test:
	./run-tests
