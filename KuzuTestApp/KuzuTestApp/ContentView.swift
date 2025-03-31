//
//  ContentView.swift
//  KuzuTestApp
//
//  Created by John W Benac on 3/30/25.
//

import SwiftUI

struct ContentView: View { 
    @State private var logs: [String] = []
    // Use the C structs directly, not OpaquePointers
    @State private var db = kuzu_database() // Initialize with default initializer
    @State private var connection = kuzu_connection() // Initialize with default initializer
    // queryResult will be used per-query, declare locally.
    // @State private var queryResult = kuzu_query_result()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Kuzu iOS Demo")
                .font(.headline)
            ScrollView {
                Text(logs.joined(separator: "\n"))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Ensure text wraps
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Run Kuzu Operations") {
                runKuzuDemo()
            }
        }
        .padding()
    }

    func log(_ message: String) {
        DispatchQueue.main.async { // Ensure UI updates on main thread
            print(message) // Log to console
            logs.append(message) // Update UI state
        }
    }

    func runKuzuDemo() {
        // Run Kuzu operations on a background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            log("Starting Kuzu Demo on background thread...")
            var dbPath = ""

            // --- Get Database Path (Use Caches Directory) ---
            guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                log("Error: Cannot find Caches directory.")
                return
            }
            // You might not even need the "kuzoData" subfolder in Caches
            dbPath = cachesDir.appendingPathComponent("app_db.kuzu").path

            /* Original Application Support Path:
            guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                log("Error: Cannot find Application Support directory.")
                return
            }
            let dbDir = appSupportDir.appendingPathComponent("kuzoData")
            dbPath = dbDir.appendingPathComponent("app_db.kuzu").path
            */
            
            // Creating the directory might not be necessary for Caches, but doesn't hurt
            do {
                try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true, attributes: nil)
                log("Database Path: \(dbPath)")
            } catch {
                log("Error ensuring DB directory exists: \(error.localizedDescription)")
                return
            }

            // --- 1. Initialize Database ---
            let cDbPath = (dbPath as NSString).utf8String
            let systemConfig = kuzu_system_config(
                buffer_pool_size: 1024 * 1024 * 16, // 16MB instead of default
                max_num_threads: 1, // Just 1 thread for iOS
                enable_compression: true,
                read_only: false,
                max_db_size: 1024 * 1024 * 64, // 64MB limit (smaller for mobile)
                auto_checkpoint: true,
                checkpoint_threshold: 1024 * 1024 // 1MB (smaller checkpoint threshold)
            )

            // Also create directory structure explicitly
            let dbDirPath = (dbPath as NSString).deletingLastPathComponent
            do {
                try FileManager.default.createDirectory(atPath: dbDirPath, withIntermediateDirectories: true, attributes: nil)
                log("Ensured DB directory exists at: \(dbDirPath)")
            } catch {
                log("Error creating DB directory: \(error.localizedDescription)")
                return
            }

            // Call init, passing pointers and checking the state
            let db_state = kuzu_database_init(cDbPath, systemConfig, &db)

            // Check the raw value of the enum state
            guard db_state.rawValue == 0 else { // 0 corresponds to KuzuSuccess
                log("Failed to initialize database at path: \(dbPath) - State: \(db_state)")
                // Database init failed, nothing to destroy yet.
                return
            }
            log("Database Initialized.")
            // Defer database destruction until the end of this function's scope
            defer {
                log("Destroying Database...")
                kuzu_database_destroy(&db) // Pass pointer to destroy
            }

            // --- 2. Create Connection ---
            // Call init, passing pointers and checking the state
            let conn_state = kuzu_connection_init(&db, &connection) // Pass pointer to db and connection
            // Check the raw value of the enum state
            guard conn_state.rawValue == 0 else { // 0 corresponds to KuzuSuccess
                log("Failed to create connection - State: \(conn_state)")
                // Connection init failed, db will be destroyed by its defer.
                return
            }
            log("Connection Created.")
            // Defer connection destruction until the end of this function's scope
            defer {
                log("Destroying Connection...")
                kuzu_connection_destroy(&connection) // Pass pointer to destroy
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
                // Declare queryResult locally for each query
                var currentQueryResult = kuzu_query_result()

                // Pass pointer for the out parameter and check state
                let query_state = kuzu_connection_query(&connection, cQuery, &currentQueryResult)

                guard query_state.rawValue == 0 else { // 0 corresponds to KuzuSuccess
                    log(" -> Query Error: Failed to execute query '\(query.description)' - State: \(query_state)")
                    // Query failed, no valid result to destroy. Loop continues.
                    continue
                }

                // Defer destruction of the *valid* result object for this iteration scope
                defer {
                    log("   Destroying query result for '\(query.description)' (deferred)")
                    kuzu_query_result_destroy(&currentQueryResult)
                }

                // Check if the query execution itself reported failure (e.g., syntax error)
                if !kuzu_query_result_is_success(&currentQueryResult) {
                    // Get error message if available
                    let errMsgPtr = kuzu_query_result_get_error_message(&currentQueryResult)
                    if let ptr = errMsgPtr {
                        log(" -> Query Failed: \(String(cString: ptr))")
                        kuzu_destroy_string(ptr) // Destroy the error string
                    } else {
                        log(" -> Query Failed: (Unknown error)")
                    }
                    // Result is not successful, defer will handle destruction. Loop continues.
                    continue
                }

                log(" -> Query Succeeded.")

                // --- 4. Process Results (if it was a read query) ---
                if query.description == "Read Items" {
                    log("Processing Read Results:")
                    // Iterate through the results
                    while kuzu_query_result_has_next(&currentQueryResult) {
                        // Declare tuple locally for each row
                        var flatTuple = kuzu_flat_tuple()
                        let tuple_state = kuzu_query_result_get_next(&currentQueryResult, &flatTuple)

                        guard tuple_state.rawValue == 0 else {
                            log("   Warning: Failed to get next tuple - State: \(tuple_state)")
                            // Cannot get tuple, stop processing this result set.
                            break
                        }
                        // Defer destruction of the valid tuple for this iteration scope
                        defer { kuzu_flat_tuple_destroy(&flatTuple) }

                        // Get Name (Column 0)
                        var nameStr = "N/A"
                        // Declare value locally
                        var nameValue = kuzu_value()
                        let name_val_state = kuzu_flat_tuple_get_value(&flatTuple, 0, &nameValue)

                        if name_val_state.rawValue == 0 {
                             // Defer destruction of the valid value
                            defer { kuzu_value_destroy(&nameValue) }
                            // Correctly call kuzu_value_get_string with out parameter
                            var namePtr: UnsafeMutablePointer<CChar>? = nil
                            let get_str_state = kuzu_value_get_string(&nameValue, &namePtr)

                             if get_str_state.rawValue == 0, let validNamePtr = namePtr {
                                nameStr = String(cString: validNamePtr)
                                kuzu_destroy_string(validNamePtr) // Destroy string immediately after use
                            } else {
                                log("   Warning: Failed to get string from name value (State: \(get_str_state))")
                            }
                        } else {
                             log("   Warning: Failed to get name value (State: \(name_val_state))")
                        }

                        // Get Price (Column 1)
                        var price: Double = 0.0
                        // Declare value locally
                        var priceValue = kuzu_value()
                        let price_val_state = kuzu_flat_tuple_get_value(&flatTuple, 1, &priceValue)

                        if price_val_state.rawValue == 0 {
                            // Defer destruction of the valid value
                            defer { kuzu_value_destroy(&priceValue) }
                            // Get double using out-parameter pattern and check state
                            let get_double_state = kuzu_value_get_double(&priceValue, &price)
                            if get_double_state.rawValue != 0 {
                                log("   Warning: Failed to get double from price value (State: \(get_double_state))")
                                price = 0.0 // Reset price on failure
                            }
                        } else {
                            log("   Warning: Failed to get price value (State: \(price_val_state))")
                        }

                        log("  - Item: \(nameStr), Price: \(String(format: "%.2f", price))")
                    } // end while kuzu_query_result_has_next
                } // end if Read Items

                // Explicitly destroy the query result here, before the loop ends and defer potentially destroys it again
                // Note: The defer block at the start of the 'for' loop handles this now.
                // Removing the manual destruction line below.
                // log("   Manually Destroying query result for '\(query.description)'")
                // kuzu_query_result_destroy(&currentQueryResult)

            } // End query loop

            log("Kuzu Demo Finished.")
        } // End background dispatch block
    } // End runKuzoDemo()
}

// Previews are often helpful, though may not fully work without build config
#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
