TCLSH = tclsh

all:
	$(TCLSH) ./build.tcl
clean:
	rm -rf artifacts/*
	rm -rf build/*
