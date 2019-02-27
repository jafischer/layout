# layout 
## A tool for restoring your carefully-arranged application windows on your MacBook, after unplugging and re-plugging external monitors.

### Author

Jonathan Fischer, 2019

### Background

Let's face it, MacBooks are not great at managing multiple monitors.

When you come back from a meeting, and plug in your 2nd (and maybe 3rd) monitor, 
your MacBook **tries** to remember where all the windows used to be, and put them all back.
But -- at least in my case, where I have a *very* particular preference for how my 
applications' windows are arranged -- it fails miserably.

Hence this app. I wrote it because I once wrote a similar app for Windows, and I was
curious how hard it would be to write one for OSX (spoiler alert: **way** harder). 

Also I wanted to dabble in Swift. Which, I have to say, I really like. 
Cocoa, not so much.

### Caveats

This is a command line (a.k.a. `Terminal`) app. 

It's also in no way a polished product aimed at the masses, sorry. Not yet, at
least. It's very much a **Klunky Developer Tool** at this point (involving 
Regular Expressions no less). But you know, it works
perfectly for me now, and I love it.

### Build

I'm going to assume that you have a `bin` directory under your HOME directory, 
and that it's in your path. If you want it somewhere else, e.g. `/usr/local/bin`, 
then adjust the instructions accordingly.

**One time step**: copy the framework libraries that it uses:

```bash
for f in clibc.framework SPMLibc.framework POSIX.framework Basic.framework layout.swiftmodule Utility.framework ; do
  cp -rp .build/x86_64-apple-macosx10.10/debug/$f ~/bin/
done 
```

Next, to build, just run the `build.sh` script (modifying the path from `~/bin` 
if necessary.)

Also you'll need to add it as an 
Accessibility application (System Preferences --> Security & Privacy --> Privacy 
tab --> Select the "Accessibility" entry from the list).

### Usage

#### 1: Saving your desired layout 

1. First run `layout --save > ~/.layout.json` to have it save the current window layout.
1. Next (yeah this is a klunky manual step) edit the file you just saved (`~/.layout.json`), 
   and remove the entries for all of the windows you don't care about.  
   Example:
   ```
    {
      "kCGWindowOwnerName": "SystemUIServer",
      "kCGWindowName": "",
      "displayID": 724062933,
      "kCGWindowBounds": {"X":1486,"Y":0,"Width":32,"Height":22}
    },
   ```
1. Next (and even klunkier), if you some windows whose title might change over time, 
   for instance based on what file or project is open in your IDE, then you can edit their 
   entries and use regular expressions as the window name, by adding `"exactMatch": false,`
   for example:
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
   
#### 2: Restoring your layout

Just run `layout` with no arguments.