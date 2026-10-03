.PHONY: test test-installed

test:
	./tests/run.sh

test-installed:
	TT_DIR="$$HOME/.local/share/tt" ./tests/run.sh
