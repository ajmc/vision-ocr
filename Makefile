PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

.PHONY: build test install uninstall samples clean

build:
	swift build -c release --disable-sandbox

test:
	swift test

install: build
	install -d "$(BINDIR)"
	install .build/release/vision-ocr "$(BINDIR)/vision-ocr"

uninstall:
	rm -f "$(BINDIR)/vision-ocr"

samples:
	swift Scripts/make-samples.swift examples

clean:
	rm -rf .build
