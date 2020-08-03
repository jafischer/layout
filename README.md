# layout 

### A tool for restoring your carefully-arranged application windows on your MacBook, after disconnecting and reconnecting external monitors. 
---

## Background

Let's face it, MacBooks are not great at managing multiple monitors, at least in the 
scenario where you are regularly unplugging them and plugging them back in.

When you come back from a meeting, and plug in your 2nd (and maybe 3rd) monitor, 
your MacBook **tries** to remember where all the windows used to be, and put them all back.
But -- at least in my case, where I have a *very* particular preference for how my 
applications' windows are arranged -- it fails miserably.

Hence this app. I wrote it because I once wrote a similar app for Windows, and I was
curious how hard it would be to write one for OSX (spoiler alert: **way** harder). 

Also I wanted to dabble in [Swift](https://swift.org/) . Which, I have to say, I really like. 

Cocoa... not so much.

## Caveats

This is a command line (a.k.a. `Terminal`) app. 

It's also in no way a polished product aimed at the masses, sorry. Not yet, at
least. It's very much a **Klunky Developer Tool** at this point (involving 
Regular Expressions no less). But you know, it works
perfectly for me now, and I love it.

## Build

I'm going to assume that you have a `bin` directory under your HOME directory, 
and that it's in your path. If you want it somewhere else, e.g. `/usr/local/bin`, 
then adjust the instructions accordingly.

To build, just run the `build.sh` script (modifying the path in the script 
from `~/bin` if necessary.)

Also you'll need to add it as an 
Accessibility application  
(System Preferences --> Security & Privacy --> Privacy 
tab --> Select the "Accessibility" entry from the list).

Catalina Update: Catalina has added a new "Screen Recording" security permission, which is needed 
to call the windows enumeration functions. However, if you call these functions you don't get the
security popup. You actually have to call one of the Screen Recording functions in order to get the
popup, even if you don't need them!

So I added a call to CGWindowListCreateImage in main. This triggers the security popup, and you 
can then add the permission.

## Usage

#### Saving your current layout 

1. First run `layout --save > ~/.layout.json` to have it save the current window layout.
1. Next (yeah this is a pretty tedious manual step) 
   edit the file you just saved (`~/.layout.json`), 
   and remove the entries for all of the windows you don't care about.  
   Example: remove entries like this:
   ```
    {
      "kCGWindowOwnerName": "SystemUIServer",
      "kCGWindowName": "",
      "displayID": 724062933,
      "kCGWindowBounds": {"X":1486,"Y":0,"Width":32,"Height":22}
    },
   ```
1. Next (and even klunkier), for all the windows whose title might change 
   over time -- for instance when the window title contains the name of the
   file being edited -- 
   then you can edit the entries for these windows and use 
   [regular expressions](https://medium.com/factory-mind/regex-tutorial-a-simple-cheatsheet-by-examples-649dc1c3f285) 
   in the window name field, by adding **`"exactMatch": false,`** to the entry.
   
   If you're not too familiar with regular expressions, the simplest one is `.*`, 
   which matches any text. 
   
   For example:
   ```
   {
     "exactMatch": false,
     "kCGWindowOwnerName": "Google Chrome",
     "kCGWindowName": ".*",
     "displayID": 724062933,
     "kCGWindowBounds": {"X":222,"Y":23,"Width":1698,"Height":1177}
   }
   ```
   More complex example (for the main window for the JetBrains CLion IDE), which will
   match the window title `layout [~/src/misc/layout] - .../README.md`:
   ```
    {
      "exactMatch": false,
      "kCGWindowName": ".* \\[.*\\] - .*",
      "kCGWindowOwnerName": "CLion",
      "displayID": 724066202,
      "kCGWindowBounds": {"X":0,"Y":23,"Width":1200,"Height":1828}
    },
   ```
   
#### Restoring your layout

Just run `layout` with no arguments.

## Author

Jonathan Fischer, 2019
