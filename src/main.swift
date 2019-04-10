import Cocoa
import Utility
import Rainbow


var debugLogging: Bool = false


func debugLog(_ message: String) {
    if debugLogging {
        print(message.blue.bold)
    }
}

/// Fetches the info for all desktop windows.
///
/// - returns: the CGWindowList, an array of dictionaries.
func getCgWindowList() -> [[String: AnyObject]] {
    let listOptions = CGWindowListOption(arrayLiteral: CGWindowListOption.excludeDesktopElements,
                                                       CGWindowListOption.optionOnScreenOnly)
    let cgWindowList: NSArray = CGWindowListCopyWindowInfo(listOptions, CGWindowID(0))!
    return cgWindowList as NSArray as! [[String:AnyObject]]
}


/// Saves the positions of all screens.
///
/// This is needed so that we can save each window's layout as relative to its current screen.
/// Then, if the screen positions are ever adjusted, we can still restore the window to the same
/// position on the screen.
func saveScreenBounds() {
    print("  \"screens\": [")
    
    for screen in NSScreen.screens {
        print("    {")
        print("      \"displayName\": \"\(screen.displayName)\",")
        print("      \"displayID\": \(screen.displayID),")
        print("      \"frame\": { " +
            "\"X\":\(Int32(screen.frame.origin.x))," +
            "\"Y\":\(Int32(screen.frame.origin.y))," +
            "\"Width\":\(Int32(screen.frame.size.width))," +
            "\"Height\":\(Int32(screen.frame.size.height))}")
        print("    },")
    }
    
    print("  ],")
}


/// Determines which screen the given window resides on.
///
/// - parameter windowBounds: the window's rectangle
///
/// - returns: the display ID and the rectangle for the window's screen.
func screenOriginForWindow(windowBounds: CGRect) -> (CGDirectDisplayID, CGRect) {
    let mainScreenRect = NSScreen.screens.first!.frame
    for screen in NSScreen.screens {
        var screenRect: CGRect = screen.frame
        
        // Unbelievably, NSScreen coordinates are different from CGWindow coordinates! NSScreen 0,0 is bottom-left,
        // and CGWindow is top-left. O.o
        screenRect.origin.y = NSMaxY(mainScreenRect) - NSMaxY(screenRect)

        if screenRect.contains(windowBounds.origin) {
            return (screen.displayID, screenRect)
        }
    }
    
    return (0, CGRect())
}


/// Saves (prints to stdout) the layout of all windows.
func saveWindowLayouts() {
    print("  \"windows\": [")
    
    for window in getCgWindowList() {
        var windowBounds = CGRect(dictionaryRepresentation: window["kCGWindowBounds"] as! CFDictionary)!
        let (displayID, screenBounds) = screenOriginForWindow(windowBounds: windowBounds)
        
        if displayID != 0 {
            windowBounds.origin.x = windowBounds.origin.x - screenBounds.origin.x
            windowBounds.origin.y = windowBounds.origin.y - screenBounds.origin.y

            print("    {")
            print("      \"kCGWindowOwnerName\": \"\(window["kCGWindowOwnerName"] as! String)\",")
            print("      \"kCGWindowName\": \"\(window["kCGWindowName"] as! String)\",")
            print("      \"displayID\": \(displayID),")
            print("      \"kCGWindowBounds\": {" +
                "\"X\":\(Int(NSMinX(windowBounds)))," +
                "\"Y\":\(Int(NSMinY(windowBounds)))," +
                "\"Width\":\(Int(NSWidth(windowBounds)))," +
                "\"Height\":\(Int(NSHeight(windowBounds)))}")
            print("    },")
        }
    }
    
    print("  ]")
}


/// Reads the ~/.layout.json file.
///
/// - returns: A tuple containing: a dictionary of information for each screen,
///            followed by an array of dictionaries containing information
///            about each desired window layout.
func readLayoutConfig() -> ([UInt32: [String: AnyObject]], [[String: AnyObject]]) {
    var screenLayouts = [UInt32: [String: AnyObject]]()
    var desiredWindowLayouts = [[String: AnyObject]]()

    do {
        let jsonString = try String(contentsOfFile: "/Users/jafischer/.layout.json", encoding: String.Encoding.utf8)
        let data: Data = jsonString.data(using: String.Encoding.utf8)!
        
        let jsonObj = try JSONSerialization.jsonObject(with: data, options: .mutableLeaves)
        guard let config = jsonObj as? Dictionary<String, AnyObject> else {
            throw NSError(domain: "Error parsing config file", code: 1)
        }
        
        for screen in config["screens"] as! Array<[String: AnyObject]> {
            screenLayouts[screen["displayID"] as! UInt32] = screen
        }
        
        for window in config["windows"] as! Array<[String: AnyObject]> {
            desiredWindowLayouts.append(window)
        }
    } catch {
        print("Error reading layout config:\n\(error)".red.bold)
    }
    
    return (screenLayouts, desiredWindowLayouts)
}


/// Determines if a position is "close" to another (within 4 pixels).
///
/// - parameter x1: X coordinate of the first position.
/// - parameter y1: Y coordinate of the first position.
/// - parameter x2: X coordinate of the second position.
/// - parameter y2: Y coordinate of the second position.
///
/// - returns: true or false to indicate closeness.
func isClose(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) -> Bool {
    return abs(x1 - x2) < 4 && abs(y1 - y2) < 4;
}


/// Converts screen-relative coordinates to absolute (i.e. relative to the primary screen).
///
/// - parameter windowPos: CGPoint containing the relative coordinates of the window.
/// - parameter savedDisplayID: the ID of the original screen that the coordinates are relative to.
/// - parameter screenLayouts: the saved screen layouts.
///
/// - returns: a CGPoint containing the absolute coordinates.
func convertRelativeCoordsToAbsolute(windowPos: CGPoint,
                                     savedDisplayID: UInt32,
                                     screenLayouts: [UInt32: [String: AnyObject]]) throws -> CGPoint {
    let mainScreenRect = NSScreen.screens.first!.frame
    var targetScreen: NSScreen? = nil
    for screen in NSScreen.screens {
        if screen.displayID == savedDisplayID {
            targetScreen = screen
            break
        }
    }
    
    var screenRect: CGRect
    
    if targetScreen == nil {
        screenRect = try findClosestScreen(savedScreenFrame: screenLayouts[savedDisplayID]!["frame"] as! [String : AnyObject])
    } else {
        screenRect = targetScreen!.frame
    }
    
    // Unbelievably, NSScreen coordinates are different from CGWindow coordinates! NSScreen 0,0 is bottom-left, and
    // CGWindow is top-left. O.o
    screenRect.origin.y = NSMaxY(mainScreenRect) - NSMaxY(screenRect)

    return CGPoint(x: windowPos.x + CGFloat(screenRect.origin.x),
                   y: windowPos.y + CGFloat(screenRect.origin.y))
}


func findClosestScreen(savedScreenFrame: [String: AnyObject]) throws -> CGRect {
    let savedScreenRect = CGRect(dictionaryRepresentation: savedScreenFrame as CFDictionary)!
    var closestScreenRect = CGRect(x: -9999, y: -9999, width: 1, height: 1)
    
    for screen in NSScreen.screens {
        let screenRect: CGRect = screen.frame
        if screenRect.equalTo(savedScreenRect) {
            return screenRect
        } else if screenRect.size.equalTo(savedScreenRect.size) {
            let currentClosest = hypotf(Float(abs(closestScreenRect.origin.x - savedScreenRect.origin.x)),
                                        Float(abs(closestScreenRect.origin.y - savedScreenRect.origin.y)))
            let distanceToThisScreen = hypotf(Float(abs(screenRect.origin.x - savedScreenRect.origin.x)),
                                              Float(abs(screenRect.origin.y - savedScreenRect.origin.y)))
            if distanceToThisScreen < currentClosest {
                closestScreenRect = screenRect
            }
        }
    }
    
    if closestScreenRect.origin.x == -9999 {
        throw NSError(domain: "Failed to find target screen", code: 2)
    }
    
    return closestScreenRect
}


/// Finds the AXUI window that matches the given CGWindow.
///
/// - parameter cgWindow: a CGWindow dictionary.
/// - parameter useRegex: indicates whether to use exact match or regex on the window title.
/// - parameter regex: the NSRegularExpression for the window title, if applicable.
/// - parameter windowName: the exact window title, if applicable.
///
/// - returns: an AXUIElement for the window, or nil if not found.
func findAXUIWindow(cgWindow: [String: AnyObject], useRegex: Bool, regex: NSRegularExpression, windowName: String)
        -> AXUIElement? {
    // Get an AXUI handle to the window's process.
    guard let windowPid = cgWindow["kCGWindowOwnerPID"] as? Int32 else { 
        print("Failed to determine pid for window.".red.bold)
        return nil
    }

    // Access the process via the AXUI API.
    let axuiApp = AXUIElementCreateApplication(windowPid)
    
    // Get the list of the process's windows.
    var value: AnyObject?
    var result: AXError = AXUIElementCopyAttributeValue(axuiApp, kAXWindowsAttribute as CFString, &value)
    
    if result != .success {
        print("AXUIElementCopyAttributeValue(kAXWindowsAttribute) failed: \(result.rawValue)".red.bold)
        return nil
    }
    
    guard let axuiWindowList = value as? [AXUIElement] else {
        print("Failed to enumerate windows for process \(windowPid).".red.bold)
        return nil
    }

    // Enumerate through the axuiWindowList to find the matching window(s).
    for axuiWindow in axuiWindowList {
        var value2: AnyObject?
        result = AXUIElementCopyAttributeValue(axuiWindow, kAXTitleAttribute as CFString, &value2)
        
        if result != .success {
            print("AXUIElementCopyAttributeValue(kAXTitleAttribute) failed: \(result.rawValue)".red.bold)
            continue
        }
        
        guard let windowTitle = value2 as? String else { continue }

        //
        // Interesting note: this AXUI window title does not always equal the title returned by the CG API above!
        // For example, Chrome seems to append " - Chrome" to the window title when returning it to the AXUI...
        //
        if windowTitle == windowName || windowTitle == windowName + " - Chrome" {
            // Can't just compare names, because some apps will have multiple windows with the same name
            // (e.g. the "Project" window in IntelliJ).
            var axuiPos = CGPoint()
            var axuiSize = CGSize()

            var value3: AnyObject?
            var result = AXUIElementCopyAttributeValue(axuiWindow, kAXPositionAttribute as CFString, &value3)

            if result != .success {
                print("     AXUIElementCopyAttributeValue(kAXPositionAttribute) failed: \(result.rawValue)".red.bold)
                continue
            }

            AXValueGetValue(value3 as! AXValue, AXValueType.cgPoint, &axuiPos)
            result = AXUIElementCopyAttributeValue(axuiWindow, kAXSizeAttribute as CFString, &value3)
            AXValueGetValue(value3 as! AXValue, AXValueType.cgSize, &axuiSize)

            if result != .success {
                print("     AXUIElementCopyAttributeValue(kAXSizeAttribute) failed: \(result.rawValue)".red.bold)
                continue
            }
            
            let cgWindowBounds = CGRect(dictionaryRepresentation: cgWindow["kCGWindowBounds"] as! CFDictionary)!

            if axuiPos.equalTo(cgWindowBounds.origin) && axuiSize.equalTo(cgWindowBounds.size) {
                return axuiWindow
            }
        }
    } // for axuiWindow

    return nil
}


/// Restores the layout for a window.
///
/// - parameter cgWindow: the CGWindow dictionary.
/// - parameter layoutsToRestore: the saved list of desired window layouts.
/// - parameter screenLayouts: the saved list of screen coordinates.
func restoreLayoutForWindow(cgWindow: [String: AnyObject],
                             layoutsToRestore: [[String: AnyObject]],
                             screenLayouts: [UInt32: [String: AnyObject]]) {
    guard let cgOwnerName = cgWindow["kCGWindowOwnerName"] as? String else { return }
    guard var cgWindowName = cgWindow["kCGWindowName"] as? String else { return }

    debugLog("Checking [\(cgOwnerName)]\(cgWindowName)")

    for savedWindowLayout in layoutsToRestore {
        do {
            if savedWindowLayout["kCGWindowOwnerName"] as! String != cgOwnerName {
                continue
            }
            
            var doesMatch = false
            var regex = NSRegularExpression()
            
            var useRegex = true
            if let exactMatch = savedWindowLayout["exactMatch"] as? Bool {
                useRegex = !exactMatch
            }
            
            if useRegex {
                regex = try NSRegularExpression(pattern: savedWindowLayout["kCGWindowName"] as! String, options: [])
                doesMatch = regex.numberOfMatches(in: cgWindowName,
                                                  options: [],
                                                  range: NSRange(location: 0,
                                                                 length: (cgWindowName as NSString).length)) != 0
            } else {
                doesMatch = cgWindowName == savedWindowLayout["kCGWindowName"] as! String
            }
            
            if doesMatch {
                //
                // One complication here is that we have to enumerate all desktop windows using the CGWindowList API,
                // and yet we have to use an entirely different API (the Accessibility API) to actually move the
                // windows. (There's no way to enumerate all desktop windows with the Accessibility API -- well,
                // at least not easily).
                //
                // OK so we've found a window that we want to move. So now we have to use the Accessibility API
                // to find the same window.
                //
                guard let axuiWindow = findAXUIWindow(cgWindow: cgWindow,
                                                      useRegex: useRegex,
                                                      regex: regex,
                                                      windowName: cgWindowName)
                    else { return }
                
                if cgWindowName.count > 40 {
                    cgWindowName = String(cgWindowName[..<String.Index(encodedOffset: 40)]) + "..."
                }
                
                let desiredBounds = savedWindowLayout["kCGWindowBounds"]!
                
                // desiredBounds is in screen-relative coordinates. So first we need to find the corresponding screen,
                // and then make the coordinates absolute. Well, actually relative to the main screen's (0,0).
                var desiredPos = try convertRelativeCoordsToAbsolute(
                    windowPos: CGPoint(x: desiredBounds["X"] as! Int, y: desiredBounds["Y"] as! Int),
                    savedDisplayID: savedWindowLayout["displayID"] as! UInt32,
                    screenLayouts: screenLayouts)
                
                var desiredSize = CGSize(width: desiredBounds["Width"] as! Int, height: desiredBounds["Height"] as! Int)
                
                // Only move if we need to.
                var currentPos = CGPoint()
                var currentSize = CGSize()
                
                var value3: AnyObject?
                var result = AXUIElementCopyAttributeValue(axuiWindow, kAXPositionAttribute as CFString, &value3)
                AXValueGetValue(value3 as! AXValue, AXValueType.cgPoint, &currentPos)
                result = AXUIElementCopyAttributeValue(axuiWindow, kAXSizeAttribute as CFString, &value3)
                AXValueGetValue(value3 as! AXValue, AXValueType.cgSize, &currentSize)

                debugLog("currentPos: \(currentPos.x), \(currentPos.y)")
                debugLog("desiredPos: \(desiredPos.x), \(desiredPos.y)")
                debugLog("currentSize: \(currentSize.width), \(currentSize.height)")
                debugLog("desiredSize: \(desiredSize.width), \(desiredSize.height)")

                // Rather than checking for equality, check for "within a couple of pixels" because I've found
                // that after moving, the window coords don't always exactly match what I sent.
                if (!isClose(x1:currentPos.x, y1:currentPos.y, x2:desiredPos.x, y2:desiredPos.y) ||
                    !isClose(x1:currentSize.width, y1:currentSize.height, x2:desiredSize.width, y2:desiredSize.height)) {
                    print("Moving [\(cgOwnerName)]\(cgWindowName) from [\(currentPos.x),\(currentPos.y)], " +
                          "size [\(currentSize.width), \(currentSize.height)]" +
                          " to [\(desiredPos.x),\(desiredPos.y)], " +
                          "size [\(desiredSize.width), \(desiredSize.height)]".bold)
                    
                    let position: CFTypeRef = AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &desiredPos)!
                    result = AXUIElementSetAttributeValue(axuiWindow, kAXPositionAttribute as CFString, position)
                    if result != .success {
                        print("     AXUIElementCopyAttributeValue(kAXTitleAttribute) failed: \(result.rawValue)".red.bold)
                    }
                    
                    let size: CFTypeRef = AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &desiredSize)!
                    result = AXUIElementSetAttributeValue(axuiWindow, kAXSizeAttribute as CFString, size)
                    if result != .success {
                        print("    AXUIElementCopyAttributeValue(kAXTitleAttribute) failed: \(result.rawValue)".red.bold)
                    }
                    
                    usleep(250000)
                } else {
                    print("No need to move [\(cgOwnerName)]\(cgWindowName)".dim.italic)
                }
            } // if doesMatch
        } catch {
            print("Error while processing window \(cgWindow): \(error)".red.bold)
        }
    } // for layout
} // func restoreLayoutForWindow


//=====================================================================================================================
//
// The two high level functions to save or restore the window layout.
//

/// Perform the save action.
func doSave() {
    print("{")
    
    saveScreenBounds()
    saveWindowLayouts()
    
    print("}")
}


/// Perform the restore action.
func doRestore() {
    let (screenLayouts, layoutsToRestore) = readLayoutConfig()

    //
    // Enumerate all desktop windows.
    //
    for cgWindow in getCgWindowList() {
        restoreLayoutForWindow(cgWindow: cgWindow, layoutsToRestore: layoutsToRestore, screenLayouts: screenLayouts)
    }
}


//=====================================================================================================================
//
// Main
//

// The first argument is always the executable, drop it
let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())

let parser = ArgumentParser(usage: "<options>", overview: "Saves and restores window layout.")
let saveFlag: OptionArgument<Bool> = parser.add(option: "--save", shortName: "-s",
                                                kind: Bool.self,
                                                usage: "Print the window layout to stdout (if not specified, default action is to restore layout from ~/.layout.json)")
let debugFlag: OptionArgument<Bool> = parser.add(option: "--debug",
                                                 shortName: "-d",
                                                 kind: Bool.self,
                                                 usage: "Debug logging")

let parsedArguments = try parser.parse(arguments)

do {
    let parsedArguments = try parser.parse(arguments)
    
    debugLogging = parsedArguments.get(debugFlag) == true

    // Save or restore?
    if parsedArguments.get(saveFlag) == true {
        doSave()
    } else {
        print("Restoring...")
        doRestore()
    }
}
catch let error as ArgumentParserError {
    print(error.description)
}
catch let error {
    print(error.localizedDescription)
}
