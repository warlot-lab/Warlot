package main

import (
    "log"
    "time"

    "github.com/steven3002/Warlot/sui-indexer/internal/config"
    "github.com/steven3002/Warlot/sui-indexer/internal/rpc"
    "github.com/steven3002/Warlot/sui-indexer/internal/store"
    "github.com/steven3002/Warlot/sui-indexer/internal/processor"
        "github.com/steven3002/Warlot/sui-indexer/pkg/sui"
)




func main() {
    // Load configuration
    cfg := config.Load()

    // Initialize database connection
    db := store.NewDB(cfg.DatabaseURL)
    defer db.Close()

    // Create RPC client
    client := rpc.NewClient(cfg.SuiRPCURL)

    // Create processor
    proc := processor.NewProcessor(db, client, cfg)

    // Main loop
    cursor := sui.Cursor{
        TxDigest: "CvUS9FXijJvcgYMz3gqprxwcsfENZiwyXUmonPuFX6mR",
        EventSeq: "0", 
    }
    
    for {
        events, nextCursor, err := client.QueryEvents(cursor)
        log.Printf("⚓🛞 Querying cursor: %s", cursor.TxDigest)


        if err != nil {
            log.Printf("RPC error: %v", err)
            time.Sleep(cfg.RetryInterval)
            continue
        }
        proc.ProcessBatch(events)
        cursor = nextCursor
        time.Sleep(cfg.RetryInterval)
    }
}