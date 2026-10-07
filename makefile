tags: jsonvar.bash
	ctags $^

.PHONY: test test-utf8
test: test-utf8

test-utf8:
	@echo '[1;4mRunning utf-8 tests[0m'
	@tools/validate-utf8
