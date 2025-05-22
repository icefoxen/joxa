VSN=0.1.0
ERL=/usr/local/bin/erl
ERLC=/usr/local/bin/erlc
REBAR=$(abspath $(CURDIR)/rebar)

# well this test doesn't seem to work
ifeq ($(REBAR),)
	$(error "Rebar not available on this system")
endif
# Project Directories (local to $(CURDIR))

SRCDIR=$(abspath $(CURDIR)/src)
TESTDIR=$(abspath $(CURDIR)/test)
PRIVDIR=$(abspath $(CURDIR)/priv)

# Build Directories In Build
APPDIR=$(CURDIR)
BEAMDIR=$(APPDIR)/ebin

# Bootstrap Directories In Build
JOXA_BOOTSTRAP_DIR=$(abspath .bootstrap)

# Location of the support makefiles
BUILD_SUPPORT=$(CURDIR)/build-support
.SUFFIXES:
.SUFFIXES:.jxa

include $(BUILD_SUPPORT)/core-build.mkf
include $(BUILD_SUPPORT)/doc.mkf

clean: jxa-clean doc-clean

distclean: jxa-distclean doc-distclean
