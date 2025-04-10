# Integrating Kuzu.xcframework into Your Swift App

This guide explains how to manually add the pre-built `Kuzu.xcframework` (built on this machine) to your Xcode project and provides a basic example of using its C API from Swift.

**Framework Location:**

The framework you need is located at the following path on this computer:

`/Users/johnwbenac/kuzo_ios/temp_lipo/Kuzu.xcframework`

You can copy this folder directly into your project structure or reference it from its current location when adding it to Xcode.

---

## 1. Add Framework to Xcode Project

1.  **Open your Swift app project** in Xcode.
2.  **Locate `Kuzu.xcframework`:** Navigate to `/Users/johnwbenac/kuzo_ios/temp_lipo/` in Finder.
3.  **Drag and Drop:** Drag the `Kuzu.xcframework` folder from Finder directly into the Xcode Project Navigator (the left-hand file list). A good place is often the top level of your project, or within a "Frameworks" group if you have one.
4.  **Choose Options:** A dialog box titled "Choose options for adding these files" will appear. Ensure:
    *   "Copy items if needed" is **checked** (recommended for portability).
    *   Under "Add to targets", your main app target is **checked**.
5.  Click **"Finish"**.
6.  **Embed the Framework:**
    *   Navigate to your app target's settings (select the project in the Navigator -> select your app target under "TARGETS").
    *   Go to the **"General"** tab.
    *   Scroll down to the **"Frameworks, Libraries, and Embedded Content"** section.
    *   Verify `Kuzu.xcframework` is listed. Change its "Embed" setting from "Do Not Embed" to **"Embed & Sign"**.

---

## 2. Set Up Objective-C Bridging Header

To call Kuzu's C API from Swift, you need an Objective-C Bridging Header.

*   **If you already have a Bridging Header** (usually named `YourProjectName-Bridging-Header.h`):
    *   Open it and add the import line shown below.
*   **If you don't have a Bridging Header:**
    1.  In Xcode, go to **File -> New -> File...**
    2.  Choose the **"Objective-C File"** template and click Next.
    3.  Name it anything (e.g., `dummy`) and click Next. Choose the default group/target.
    4.  Xcode should prompt: "Would you like to configure an Objective-C bridging header?". Click **"Create Bridging Header"**.
    5.  You can now safely **delete** the `dummy.m` file you just created.
*   **Add Kuzu Import to Bridging Header:**
    *   Open the newly created (or existing) bridging header file (`YourProjectName-Bridging-Header.h`).
    *   Add the following line:

    ```c
    // In YourProjectName-Bridging-Header.h
    #import <Kuzu/kuzu.h>
    ```
    *   *Troubleshooting:* If you encounter a 'file not found' error during the build process later, try changing the import line to `#import <Kuzu/c_api/kuzu.h>`.

---

## 3. Using Kuzu in Swift (Basic Example)

You can now call Kuzu C functions from your Swift code. Here's a basic example demonstrating initialization, querying, and cleanup. Integrate this logic appropriately within your app's UI or data management layers.

```swift
import SwiftUI // Or UIKit if not using SwiftUI
import Darwin // Needed for free() if Kuzu doesn't provide a string free function

// Example SwiftUI View
struct KuzuDemoView: View {
    @State private var kuzoLog: String = "Kuzu Log:\n"

    var body: some View {
        VStack(alignment: .leading) {
            Text("Kuzu iOS Demo")
                .font(.headline)
            ScrollView {
                Text(kuzoLog)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Run Kuzu Operations") {
                runKuzuDemo()
            }
        }
        .padding()
    }

    func log(_ message: String) {
        print(message) // Log to console
        kuzoLog += message + "\\n" // Update UI state
    }

    func runKuzuDemo() {
        log("Starting Kuzu Demo...")
        var dbPath = ""
        var db: OpaquePointer? = nil // kuzu_database*
        var connection: OpaquePointer? = nil // kuzu_connection*
        var queryResult: OpaquePointer? = nil // kuzu_query_result*

        // --- Get Database Path ---
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            log("Error: Cannot find Application Support directory.")
            return
        }
        let dbDir = appSupportDir.appendingPathComponent("kuzoData") // Subdirectory for Kuzu
        dbPath = dbDir.appendingPathComponent("app_db.kuzu").path // Specific file

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true, attributes: nil)
            // Optional: For a clean demo run, remove the old DB file first.
            // try? FileManager.default.removeItem(atPath: dbPath)
            log("Database Path: \(dbPath)")
        } catch {
            log("Error creating DB directory: \(error.localizedDescription)")
            return
        }

        // --- 1. Initialize Database ---
        // Use C String for path
        let cDbPath = (dbPath as NSString).utf8String
        // Configure path, leave others default. Set a reasonable max size.
        let dbConfig = kuzu_database_config(
            db_path: cDbPath,
            buffer_pool_size: 0, // 0 = default
            max_num_threads: 0, // 0 = default
            enable_compression: true,
            read_only_mode: false,
            max_db_size: 1024 * 1024 * 1024 * 2 // 2 GB limit
        )
        // **ACTION NEEDED**: Confirm `kuzu_default_system_config()` exists in kuzu.h or find the correct way to get default config.
        let systemConfig = kuzu_default_system_config()
        db = kuzu_database_init(dbConfig, systemConfig) // Pass system config if needed

        guard let db = db else {
            log("Failed to initialize database at path: \(dbPath)")
            // Optionally check systemConfig validity here too
            return
        }
        log("Database Initialized.")
        defer {
            log("Destroying Database...")
            kuzu_database_destroy(db) // Ensure DB is destroyed on exit
        }

        // --- 2. Create Connection ---
        connection = kuzu_connection_init(db)
        guard let connection = connection else {
            log("Failed to create connection.")
            // db is handled by defer
            return
        }
        log("Connection Created.")
        defer {
            log("Destroying Connection...")
            kuzu_connection_destroy(connection) // Ensure Connection is destroyed on exit
        }

        // --- 3. Execute Cypher Queries ---
        let queries: [(description: String, cypher: String)] = [
            ("Create Schema", "CREATE NODE TABLE IF NOT EXISTS Item(itemID STRING, name STRING, price DOUBLE, PRIMARY KEY (itemID))"),
            ("Insert/Update Item 1", "MERGE (i:Item {itemID: 'item001'}) SET i.name = 'Gadget', i.price = 19.99"),
            ("Insert/Update Item 2", "MERGE (i:Item {itemID: 'item002'}) SET i.name = 'Widget', i.price = 14.50"),
            ("Read Items", "MATCH (i:Item) WHERE i.price > 15.0 RETURN i.name, i.price ORDER BY i.name")
        ]

        for query in queries {
            log("Executing Query: \(query.description)")
            let cQuery = (query.cypher as NSString).utf8String
            queryResult = kuzu_connection_query(connection, cQuery)

            guard let currentResult = queryResult else {
                log(" -> Query Error: \(getKuzuError(connection))")
                continue // Skip to next query
            }
            defer { kuzu_query_result_destroy(currentResult) } // Ensure result is destroyed

            if !kuzu_query_result_is_success(currentResult) {
                log(" -> Query Failed: \(String(cString: kuzu_query_result_get_error_message(currentResult)))")
                continue // Skip to next query
            }

            log(" -> Query Succeeded.")

            // --- 4. Process Results (if it was a read query) ---
            if query.description == "Read Items" {
                log("Processing Read Results:")
                while kuzu_query_result_has_next(currentResult) {
                    let flatTuple = kuzu_query_result_get_next(currentResult)
                    guard let flatTuple = flatTuple else { continue }
                    defer { kuzu_flat_tuple_destroy(flatTuple) } // Destroy tuple

                    // Get Name (Column 0)
                    let nameValue = kuzu_flat_tuple_get_value(flatTuple, 0)
                    var nameStr = "N/A"
                    if let nameValue = nameValue {
                         // **ACTION NEEDED**: Confirm string free function in kuzu.h (e.g., kuzu_free_string)
                         if let namePtr = kuzu_value_get_string(nameValue) {
                            nameStr = String(cString: namePtr)
                            kuzu_free_string(namePtr) // Free the string memory!
                        }
                        kuzu_value_destroy(nameValue) // Destroy the value object
                    }

                    // Get Price (Column 1)
                    let priceValue = kuzu_flat_tuple_get_value(flatTuple, 1)
                    var price: Double = 0.0
                    if let priceValue = priceValue {
                        price = kuzu_value_get_double(priceValue)
                        kuzu_value_destroy(priceValue) // Destroy the value object
                    }

                    log("  - Item: \(nameStr), Price: \(String(format: "%.2f", price))")
                }
            }
        } // End query loop

        log("Kuzu Demo Finished.")
    } // End runKuzoDemo()

    // Helper to get the last error message from the connection
    func getKuzuError(_ connection: OpaquePointer?) -> String {
        guard let connection = connection, let msgPtr = kuzu_connection_get_error_message(connection) else {
            return "Unknown Kuzu error or nil connection"
        }
        // Kuzu C API docs state this pointer is owned by the connection. Copy it.
        return String(cString: msgPtr)
    }

    // Stubs for functions potentially needing implementation based on kuzu.h
    // **ACTION NEEDED**: Replace these with actual calls or logic based on `kuzu.h`

    // Function to get default system config. Check kuzu.h for the real function.
    func kuzu_default_system_config() -> OpaquePointer? {
        // Example: return kuzu_system_config_default() if that exists.
        log("Warning: Using placeholder for kuzu_default_system_config(). Check kuzu.h.")
        return nil // Return nil if no specific config needed or function TBD
    }

    // Function to free strings returned by Kuzu. Check kuzu.h for the real function.
    func kuzu_free_string(_ str: UnsafeMutablePointer<CChar>?) {
        // If kuzu.h provides `kuzu_free_string` or `kuzu_destroy_string`, use it.
        // Otherwise, default to libc's free (requires `import Darwin`).
        // kuzu_free_string(str) // <-- Use this if it exists in kuzu.h
        free(str) // <-- Use this as fallback if Kuzu function doesn't exist
        // log("Warning: Using free() for Kuzu string. Confirm correct function in kuzu.h.")
    }
} // End SwiftUI View

```

---

## 4. Important Considerations

*   **Memory Management is Crucial:** The Kuzu C API requires you to manually manage the memory of objects it returns (like `kuzu_query_result`, `kuzu_flat_tuple`, `kuzu_value`, and especially returned C strings).
    *   Always call the corresponding `kuzu_*_destroy()` function when you are finished with an object (use `defer` blocks where appropriate).
    *   **Verify the String Freeing Function:** The example uses a placeholder `kuzu_free_string()`. You **must check `kuzu.h`** to find the correct function Kuzu provides for freeing `char*` strings returned by functions like `kuzu_value_get_string()`. Using the wrong function (or `free()` if Kuzu provides its own) **will** cause crashes or memory leaks.
    *   **Verify Default System Config:** The example uses `kuzu_default_system_config()`. Check `kuzu.h` for the correct way to obtain a default system configuration if needed for `kuzu_database_init`.
*   **Error Handling:** The example shows basic error checking using `kuzu_query_result_is_success()` and `kuzu_connection_get_error_message()`. Production code should handle potential errors more robustly.
*   **Threading:** Database operations can be time-consuming. To avoid blocking the main UI thread, perform Kuzu operations on a background queue (e.g., using `DispatchQueue.global().async`). Accessing the same `kuzu_connection` from multiple threads concurrently is likely **unsafe** unless the Kuzu documentation explicitly allows it or you implement your own locking. Creating separate connections per queue/thread might be necessary.
*   **Build Issues:** If your project fails to build after adding the framework:
    *   Double-check the Bridging Header import (`#import <Kuzu/kuzu.h>`).
    *   Verify `Kuzu.xcframework` is set to **"Embed & Sign"** in the target's "Frameworks, Libraries, and Embedded Content" section.
    *   Clean the build folder (**Product -> Clean Build Folder**) and try building again.

---

Good luck with the integration! Provide feedback on any issues encountered. 