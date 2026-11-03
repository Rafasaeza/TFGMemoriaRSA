# Makefile to build the TFG on Unix-like environments (Linux, macOS, WSL)
.PHONY: all clean

all:
	@chmod +x build.sh
	@./build.sh

clean:
	@chmod +x build.sh
	@./build.sh clean
