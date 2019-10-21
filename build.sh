#!/bin/bash

swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.12" && \
  cp -p ./.build/debug/layout ~/bin/binaries/

