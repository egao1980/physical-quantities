#!/bin/bash

sbcl	--noinform \
	--disable-ldb \
	--lose-on-corruption \
	--end-runtime-options \
	--no-sysinit \
	--no-userinit \
	--disable-debugger \
	--eval '(require :asdf)' \
	--eval '(asdf:test-system :physical-quantities)' \
	--quit \
	--end-toplevel-options