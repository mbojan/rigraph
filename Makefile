
all: igraph igraphdata

########################################################
# Data package, this is simple, it is static

DATAVERSION=$(shell grep "^Version" igraphdata/DESCRIPTION | cut -d" " -f 2)
DATAFILES = $(wildcard igraphdata/data/*.rda) igraphdata/DESCRIPTION \
	igraphdata/LICENSE $(wildcard igraphdata/man/*.Rd) \
	$(wildcard igraphdata/inst/*)

igraphdata: igraphdata_$(DATAVERSION).tar.gz

igraphdata_$(DATAVERSION).tar.gz: $(DATAFILES)
	R CMD build igraphdata

########################################################
# Main package, a lot more complicated

top_srcdir=../..
REALVERSION=$(shell $(top_srcdir)/tools/getversion.sh)
VERSION=$(shell ./tools/convertversion.sh)

# We put the version number in a file, so that we can detect
# if it changes

version_number: force
	@echo '$(VERSION)' | cmp -s - $@ || echo '$(VERSION)' > $@

# Source files from the C library, we don't need BLAS/LAPACK
# because they are included in R and ARPACK, because 
# we use the Fortran files for that. We don't need F2C, either.

CSRC := $(shell git ls-files --full-name $(top_srcdir)/src | \
	 grep -v "^src/lapack/" | grep -v "^src/f2c" | grep -v Makefile.am)
CSRC2 := $(patsubst src/%, igraph/src/%, $(CSRC))

$(CSRC2): igraph/src/%: $(top_srcdir)/src/%
	mkdir -p $(@D) && cp $< $@

# Include files from the C library

CINC := $(shell git ls-files --full-name $(top_srcdir)/include)
CINC2 := $(patsubst include/%, igraph/src/include/%, $(CINC))

$(CINC2): igraph/src/include/%: $(top_srcdir)/include/%
	mkdir -p $(@D) && cp $< $@

# Files generated by flex/bison

PARSER := $(shell git ls-files --full-name $(top_srcdir)/src | \
	    grep -E '\.(l|y)$$')
PARSER1 := $(patsubst src/%.l, igraph/src/%.c, $(PARSER))
PARSER2 := $(patsubst src/%.y, igraph/src/%.c, $(PARSER1))

YACC=bison -d
LEX=flex

%.c: %.y
	$(YACC) $<
	mv -f y.tab.c $@
	mv -f y.tab.h $(@:.c=.h)

%.c: %.l
	$(LEX) $<
	mv -f lex.yy.c $@

# C files generated by C configure

CGEN = igraph/src/igraph_threading.h igraph/src/igraph_version.h

igraph/src/igraph_threading.h: $(top_srcdir)/include/igraph_threading.h.in
	sed 's/@HAVE_TLS@/0/g' $< >$@

igraph/src/igraph_version.h: $(top_srcdir)/include/igraph_version.h.in
	sed 's/@VERSION@/'$(REALVERSION)'/g' $< >$@

# R source and doc files

RSRC := $(shell git ls-files igraph)

# ARPACK Fortran sources

ARPACK := $(shell git ls-files arpack)
ARPACK2 := $(patsubst arpack/%, igraph/src/%, $(ARPACK))

$(ARPACK2): igraph/src/%: arpack/%
	mkdir -p $(@D) && cp $< $@

# R files that are generated/copied

RGEN = igraph/R/auto.R igraph/src/rinterface.c igraph/src/rinterface.h \
	igraph/src/rinterface_extra.c igraph/src/Makevars.in \
	igraph/configure igraph/src/config.h.in igraph/src/Makevars.win \
	igraph/DESCRIPTION igraph/NAMESPACE

# GLPK

GLPK := $(shell git ls-files --full-name $(top_srcdir)/optional/glpk)
GLPK2 := $(patsubst optional/glpk/%, igraph/src/glpk/%, $(GLPK))

$(GLPK2): igraph/src/%: $(top_srcdir)/optional/%
	mkdir -p $(@D) && cp $< $@

# Simpleraytracer

RAY := $(shell git ls-files --full-name $(top_srcdir)/optional/simpleraytracer)
RAY2 := $(patsubst optional/simpleraytracer/%, \
	  igraph/src/simpleraytracer/%, $(RAY))

$(RAY2): igraph/src/%: $(top_srcdir)/optional/%
	mkdir -p $(@D) && cp $< $@

# Files generated by stimulus

igraph/NAMESPACE: ../functions.def NAMESPACE.in \
		  $(top_srcdir)/tools/stimulus.py
	$(top_srcdir)/tools/stimulus.py \
            -f ../functions.def \
            -i NAMESPACE.in \
            -o igraph/NAMESPACE \
            -l RNamespace

igraph/src/rinterface.c: $(top_srcdir)/interfaces/functions.def \
		$(top_srcdir)/interfaces/R/src/rinterface.c.in  \
		$(top_srcdir)/interfaces/R/types-C.def \
		$(top_srcdir)/tools/stimulus.py
	$(top_srcdir)/tools/stimulus.py \
           -f $(top_srcdir)/interfaces/functions.def \
           -i $(top_srcdir)/interfaces/R/src/rinterface.c.in \
           -o igraph/src/rinterface.c \
           -t $(top_srcdir)/interfaces/R/types-C.def \
           -l RC

igraph/R/auto.R: $(top_srcdir)/interfaces/functions.def auto.R.in \
		$(top_srcdir)/interfaces/R/types-R.def \
		$(top_srcdir)/tools/stimulus.py
	$(top_srcdir)/tools/stimulus.py \
           -f $(top_srcdir)/interfaces/functions.def \
           -i auto.R.in \
           -o igraph/R/auto.R \
           -t $(top_srcdir)/interfaces/R/types-R.def \
           -l RR

# configure files

igraph/configure igraph/src/config.h.in: igraph/configure.in
	cd igraph; autoheader; autoconf

# DESCRIPTION file, we re-generate it only if the VERSION number
# changes or $< changes

igraph/DESCRIPTION: src/DESCRIPTION version_number
	sed 's/^Version: .*$$/Version: '$(VERSION)'/' $<     | \
        sed 's/^Date: .*$$/Date: '`date "+%Y-%m-%d"`'/' > $@

igraph/src/rinterface.h: src/rinterface.h
	mkdir -p igraph/src
	cp $< $@

igraph/src/rinterface_extra.c: src/rinterface_extra.c
	mkdir -p igraph/src
	cp $< $@

# This is the list of all object files in the R package,
# we write it to a file to be able to depend on it.
# Makevars.in and Makevars.win are only regenerated if 
# the list of object files changes.

OBJECTS := $(shell echo $(CSRC) $(ARPACK) $(GLPK) $(RAY) | tr ' ' '\n' | \
	        grep -E '\.(c|cpp|cc|f|l|y)$$' | 			 \
		grep -F -v '/t_cholmod' | 				 \
		grep -F -v f2c/arithchk.c | grep -F -v f2c_dummy.c |	 \
		sed 's/\.[^\.][^\.]*$$/.o/' | 			 	 \
		sed 's/^src\///' | sed 's/^arpack\///' |		 \
		sed 's/^optional\///') rinterface.o rinterface_extra.o

object_files: force
	@echo '$(OBJECTS)' | cmp -s - $@ || echo '$(OBJECTS)' > $@

igraph/src/Makevars.win igraph/src/Makevars.in: igraph/src/%: src/% \
		object_files
	sed 's/@VERSION@/'$(VERSION)'/g' $< >$@
	printf "%s" "OBJECTS=" >> $@
	cat object_files >> $@

# We have everything, here we go

igraph: igraph_$(VERSION).tar.gz

igraph_$(VERSION).tar.gz: $(CSRC2) $(CINC2) $(PARSER2) $(RSRC) $(RGEN) \
			  $(CGEN) $(GLPK2) $(RAY2) $(ARPACK2)
	rm -f igraph/src/config.h
	rm -f igraph/src/Makevars
	touch igraph/src/config.h
	mkdir -p igraph/man
	find igraph/src -name "*.o" -exec rm \{\} \;
	cd igraph && Rscript -e 'library(roxygen2) ; roxygenize(roclets = "rd")'
	R CMD build igraph

#############

.PHONY: all igraph igraphdata force
