import Cocoa


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

let listOptions = CGWindowListOption(arrayLiteral: CGWindowListOption.excludeDesktopElements, CGWindowListOption.optionOnScreenOnly)
let cgWindowList: NSArray = CGWindowListCopyWindowInfo(listOptions, CGWindowID(0))!
let windowList = cgWindowList as NSArray as! [[String: AnyObject]]

print("{")

dumpScreens()
dumpWindows(windowList: windowList)

print("}")

