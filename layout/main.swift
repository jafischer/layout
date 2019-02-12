import Cocoa
import Utility


// From https://gist.github.com/salexkidd/bcbea2372e92c6e5b04cbd7f48d9b204
extension NSScreen {
    public var displayID: CGDirectDisplayID {
        get {
            return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        }
    }
    
    
    public var displayName: String {
        get {
            var name = "Unknown"
            var object : io_object_t
            var serialPortIterator = io_iterator_t()
            let matching = IOServiceMatching("IODisplayConnect")
            
            let kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &serialPortIterator)
            if KERN_SUCCESS == kernResult && serialPortIterator != 0 {
                repeat {
                    object = IOIteratorNext(serialPortIterator)
                    let displayInfo = IODisplayCreateInfoDictionary(object, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary as! [String:AnyObject]
                    
                    if  (displayInfo[kDisplayVendorID] as? UInt32 == CGDisplayVendorNumber(displayID) &&
                        displayInfo[kDisplayProductID] as? UInt32 == CGDisplayModelNumber(displayID) &&
                        displayInfo[kDisplaySerialNumber] as? UInt32 ?? 0 == CGDisplaySerialNumber(displayID)
                        ) {
                        if let productName = displayInfo["DisplayProductName"] as? [String:String],
                            let firstKey = Array(productName.keys).first {
                            name = productName[firstKey]!
                            break
                        }
                    }
                } while object != 0
            }
            IOObjectRelease(serialPortIterator)
            return name
        }
    }
}


func dumpScreens() {
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


func screenOriginForWindow(windowBounds: CGRect) -> (CGDirectDisplayID, CGRect) {
    let mainScreenRect = NSScreen.screens.first!.frame
    for screen in NSScreen.screens {
        var screenRect: NSRect = screen.frame
        
        // Unbelievably, NSScreen coordinates are different from CGWindow coordinates! NSScreen 0,0 is bottom-left, and
        // CGWindow is top-left. O.o
        screenRect.origin.y = NSMaxY(mainScreenRect) - NSMaxY(screenRect)

        if screenRect.contains(windowBounds.origin) {
            return (screen.displayID, screenRect)
        }
    }
    
    return (0, CGRect())
}

func dumpWindows(windowList: [[String: AnyObject]]) {
    print("  \"windows\": [")
    
    for window in windowList {
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
        print("Error reading layout config! \(error)")
    }
    
    return (screenLayouts, desiredWindowLayouts)
}

func isClose(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) -> Bool {
    return abs(x1 - x2) < 4 && abs(y1 - y2) < 4;
}

func convertRelativeCoordsToAbsolute(windowPos: CGPoint, savedDisplayID: Int, screenLayouts: [UInt32: [String: AnyObject]]) throws -> CGPoint {
    let mainScreenRect = NSScreen.screens.first!.frame
    var targetScreen: NSScreen? = nil
    for screen in NSScreen.screens {
        if screen.displayID == savedDisplayID {
            targetScreen = screen
            break
        }
    }
    
    if targetScreen == nil {
        // TODO: jafischer-2019-02-12 compared savedLayouts to current window layout, find closest one.
        throw NSError(domain: "Failed to find target screen", code: 2)
    }
    
    var screenRect: NSRect = targetScreen!.frame
    
    // Unbelievably, NSScreen coordinates are different from CGWindow coordinates! NSScreen 0,0 is bottom-left, and
    // CGWindow is top-left. O.o
    screenRect.origin.y = NSMaxY(mainScreenRect) - NSMaxY(screenRect)

    return CGPoint(x: windowPos.x + CGFloat(screenRect.origin.x),
                   y: windowPos.y + CGFloat(screenRect.origin.y))
}

func restoreLayoutsForWindow(screenLayouts: [UInt32: [String: AnyObject]], savedWindowLayout: [String: AnyObject]) {
    //
    // One complication here is that we have to enumerate all desktop windows using the CGWindowList... API, and yet we have
    // to use an entirely different API (the Accessibility API) to actually move the windows. (There's no way to enumerate all
    // desktop windows with the Accessibility API -- well, at least not easily).
    //
    let listOptions = CGWindowListOption(arrayLiteral: CGWindowListOption.excludeDesktopElements, CGWindowListOption.optionOnScreenOnly)
    let desktopWindowList = CGWindowListCopyWindowInfo(listOptions, CGWindowID(0)) as! [[String: AnyObject]]
    
    for cgWindow in desktopWindowList {
        let ownerName = cgWindow["kCGWindowOwnerName"] as! String
        if ownerName != savedWindowLayout["kCGWindowOwnerName"] as! String {
            continue
        }
        
        // Is this owner one of the ones in the layout config? I.e., does this owner exist in the owner map?
        var cgWindowName = cgWindow["kCGWindowName"] as! String
        
        // For each owner there can be several layouts, one for each window in the application. So let's find which one matches the current window.
        do {
            var doesMatch = false
            var regex = NSRegularExpression()
            
            var useRegex = true
            if let exactMatch = savedWindowLayout["exactMatch"] as? Bool {
                useRegex = !exactMatch
            }
            
            if useRegex {
                regex = try NSRegularExpression(pattern: savedWindowLayout["kCGWindowName"] as! String, options: [])
                doesMatch = regex.numberOfMatches(in: cgWindowName, options: [], range: NSRange(location: 0, length: (cgWindowName as NSString).length)) != 0
            } else {
                doesMatch = cgWindowName == savedWindowLayout["kCGWindowName"] as! String
            }
            
            if doesMatch {
                //
                // OK so we've found a window that we want to move. So now we have to use the Accessibility API to find the same window.
                //
                
                // Get an AXUI handle to the window's process.
                let axuiApp = AXUIElementCreateApplication(cgWindow["kCGWindowOwnerPID"] as! Int32)
                
                // Get the list of the process's windows.
                var value: AnyObject?
                var result = AXUIElementCopyAttributeValue(axuiApp, kAXWindowsAttribute as CFString, &value)
                
                if result != .success {
                    print("AXUIElementCopyAttributeValue(kAXWindowsAttribute) failed with result: \(result.rawValue), \(result)")
                    break
                }
                
                // Enumerate through the windowList to find the matching window.
                if let windowList = value as? [AXUIElement] {
                    for axuiWindow in windowList {
                        var value2: AnyObject?
                        result = AXUIElementCopyAttributeValue(axuiWindow, kAXTitleAttribute as CFString, &value2)
                        
                        if result != .success {
                            print("AXUIElementCopyAttributeValue(kAXTitleAttribute) failed with result: \(result.rawValue), \(result)")
                            break
                        }
                        
                        if let windowTitle = value2 as? String {
                            //
                            // Interesting note: this AXUI window title does not always equal the title returned by the CG API above!
                            // For example, Chrome seems to append " - Chrome" to the window title when returning it to the AXUI... so frustrating.
                            // So we have to do the whole comparison with the layout config window title again.
                            //
                            if useRegex {
                                doesMatch = regex.numberOfMatches(in: windowTitle, options: [], range: NSRange(location: 0, length: (windowTitle as NSString).length)) != 0
                            } else {
                                doesMatch = windowTitle == savedWindowLayout["kCGWindowName"] as! String
                            }
                            
                            if doesMatch {
                                if cgWindowName.count > 40 {
                                    cgWindowName = String(cgWindowName[..<String.Index(encodedOffset: 40)]) + "..."
                                }
                                print("Window [\(ownerName)]\(cgWindowName)")
                                
                                let desiredBounds = savedWindowLayout["kCGWindowBounds"]!
                                
                                // desiredBounds is in screen-relative coordinates. So first we need to find the corresponding screen,
                                // and then make the coordinates absolute. Well, actually relative to the main screen's (0,0).
                                var desiredPosition = try convertRelativeCoordsToAbsolute(
                                    windowPos: CGPoint(x: desiredBounds["X"] as! Int, y: desiredBounds["Y"] as! Int),
                                    savedDisplayID: savedWindowLayout["displayID"] as! Int,
                                    screenLayouts: screenLayouts)
                                
                                var desiredSize = CGSize(width: desiredBounds["Width"] as! Int, height: desiredBounds["Height"] as! Int)
                                
                                // Only move if we need to.
                                var currentPoint = CGPoint()
                                var currentSize = CGSize()
                                
                                var value3: AnyObject?
                                result = AXUIElementCopyAttributeValue(axuiWindow, kAXPositionAttribute as CFString, &value3)
                                AXValueGetValue(value3 as! AXValue, AXValueType.cgPoint, &currentPoint)
                                result = AXUIElementCopyAttributeValue(axuiWindow, kAXSizeAttribute as CFString, &value3)
                                AXValueGetValue(value3 as! AXValue, AXValueType.cgSize, &currentSize)
                                
                                // Rather than checking for equality, check for "within a couple of pixels" because I've found that after moving, the window coords
                                // don't always exactly match what I sent.
                                if (!isClose(x1: currentPoint.x, y1: currentPoint.y, x2: desiredPosition.x, y2: desiredPosition.y)
                                    || !isClose(x1: currentSize.width, y1: currentSize.height, x2: desiredSize.width, y2: desiredSize.height)) {
                                    print("    Moving from [\(currentPoint.x),\(currentPoint.y)], size [\(currentSize.width), \(currentSize.height)]")
                                    print("             to [\(desiredPosition.x),\(desiredPosition.y)], size [\(desiredSize.width), \(desiredSize.height)]")
                                    
                                    let position: CFTypeRef = AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &desiredPosition)!
                                    AXUIElementSetAttributeValue(axuiWindow, kAXPositionAttribute as CFString, position)
                                    
                                    let size: CFTypeRef = AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &desiredSize)!
                                    AXUIElementSetAttributeValue(axuiWindow, kAXSizeAttribute as CFString, size)
                                    
                                    usleep(250000)
                                } else {
                                    print("    No need to move or size.")
                                }
                                break
                            }
                        }
                    }
                }
                
                break
            } // if doesMatch
        } catch {
            print("Error while processing window \(cgWindow): \(error)")
        }
    } // for cgWindow in desktopWindowList
} // func restoreLayoutsForWindow


//
// The two high level functions to dump or restore the window layout.
//

func dumpLayout(windowList: [[String: AnyObject]]) {
    print("{")
    
    dumpScreens()
    dumpWindows(windowList: windowList)
    
    print("}")
}

func restoreLayout(windowList: [[String: AnyObject]]) {
    let (screenLayouts, layoutsToRestore) = readLayoutConfig()
    for layout in layoutsToRestore {
        restoreLayoutsForWindow(screenLayouts: screenLayouts, savedWindowLayout: layout)
    }
}


//
// Main
//

let listOptions = CGWindowListOption(arrayLiteral: CGWindowListOption.excludeDesktopElements, CGWindowListOption.optionOnScreenOnly)
let cgWindowList: NSArray = CGWindowListCopyWindowInfo(listOptions, CGWindowID(0))!
let windowList = cgWindowList as NSArray as! [[String: AnyObject]]

// The first argument is always the executable, drop it
let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())

let parser = ArgumentParser(usage: "<options>", overview: "Saves and restores window layout.")
let dumpFlag: OptionArgument<Bool> = parser.add(option: "--dump", shortName: "-d", kind: Bool.self, usage: "Dump the window layout to stdout (otherwise, will be restored from ~/.layout.json)")

let parsedArguments = try parser.parse(arguments)

do {
    let parsedArguments = try parser.parse(arguments)
    
    // Dump or restore?
    if parsedArguments.get(dumpFlag) == true {
        dumpLayout(windowList: windowList)
    } else {
        print("Restoring...")
        restoreLayout(windowList: windowList)
    }
}
catch let error as ArgumentParserError {
    print(error.description)
}
catch let error {
    print(error.localizedDescription)
}
