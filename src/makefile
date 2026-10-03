CFLAGS ?= -O -g

MACRO11_SRCS = macro11.c \
	assemble.c assemble_globals.c assemble_aux.c	\
	extree.c listing.c macros.c parse.c rept_irpc.c symbols.c \
	mlb.c object.c stream2.c util.c rad50.c

MACRO11_OBJS = $(MACRO11_SRCS:.c=.o)

DUMPOBJ_SRCS = dumpobj.c rad50.c

DUMPOBJ_OBJS = $(DUMPOBJ_SRCS:.c=.o)

ALL_SRCS = $(MACRO11_SRCS) $(DUMPOBJ_SRCS)

all: macro11 dumpobj

tags: macro11 dumpobj
	ctags *.c *.h

macro11: $(MACRO11_OBJS) makefile
	$(CC) $(CFLAGS) -o macro11 $(MACRO11_OBJS) -lm

dumpobj: $(DUMPOBJ_OBJS) makefile
	$(CC) $(CFLAGS) -o dumpobj $(DUMPOBJ_OBJS)

$(MACRO11_OBJS) $(DUMPOBJ_OBJS): makefile

clean:
	-rm -f $(MACRO11_OBJS) $(DUMPOBJ_OBJS) macro11 dumpobj

# Every object depends on all headers; this is simple and always correct.
HEADERS = assemble.h assemble_aux.h assemble_globals.h extree.h listing.h macro11.h macros.h mlb.h object.h parse.h rad50.h rept_irpc.h stream2.h symbols.h util.h

$(MACRO11_OBJS) $(DUMPOBJ_OBJS): $(HEADERS)

# Test that all options requiring a value bail out if it's not present.
# (Uses only POSIX sh, since make runs /bin/sh.)
argtests: macro11
	@ for OPT in -e -d -m -p -o -l -ysl ; do \
	  ./macro11 tests/good.mac $$OPT     2> /dev/null; \
	  if [ $$? -eq 1 ]; then echo "PASS  $$OPT missing value"; else echo "FAIL  $$OPT missing value"; fi; \
	  ./macro11 tests/good.mac $$OPT -v  2> /dev/null; \
	  if [ $$? -eq 1 ]; then echo "PASS  $$OPT followed by option"; else echo "FAIL  $$OPT followed by option"; fi; \
	done
	@ ./macro11 tests/good.mac -x -v 2> /dev/null; \
	if [ $$? -eq 1 ]; then echo "PASS  -x must be the last option"; else echo "FAIL  -x must be the last option"; fi

# Assemble the files in tests/ and compare with the expected output.
# "sh tests/run-tests.sh -u" updates the expected output.
tests: macro11 dumpobj argtests
	@ sh tests/run-tests.sh
