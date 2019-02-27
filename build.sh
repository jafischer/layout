#!/bin/bash

swift build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.12" && \
  cp -p ./.build/x86_64-apple-macosx10.10/debug/layout ~/bin/

