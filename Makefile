SOURCES = $(wildcard Sources/*.m)
HEADERS = $(wildcard Sources/*.h)
BINDIR  = $(HOME)/bin
AGENT   = $(HOME)/Library/LaunchAgents/com.james.ddcvol.plist

ddcvol: $(SOURCES) $(HEADERS)
	clang -fobjc-arc -fmodules -O2 $(SOURCES) -o ddcvol \
		-framework AppKit -framework CoreAudio -framework IOKit \
		-framework ApplicationServices

install: ddcvol
	mkdir -p $(BINDIR)
	install ddcvol $(BINDIR)/ddcvol

# Install + register the volume-key daemon to start at login
install-agent: install
	sed "s|__HOME__|$(HOME)|g" com.james.ddcvol.plist > $(AGENT)
	launchctl unload $(AGENT) 2>/dev/null || true
	launchctl load $(AGENT)

uninstall:
	launchctl unload $(AGENT) 2>/dev/null || true
	rm -f $(AGENT) $(BINDIR)/ddcvol

clean:
	rm -f ddcvol

.PHONY: install install-agent uninstall clean
