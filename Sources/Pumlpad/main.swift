import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.mainMenu = MainMenu.make()
app.run()
