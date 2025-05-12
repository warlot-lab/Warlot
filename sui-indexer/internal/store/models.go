package store

import (
    "strconv"
 "database/sql"
    "fmt"
    "log"
    "time"
)


func (db *DB) InsertNewUser(data map[string]interface{}) error {
    //Extract fields from parsedJson
    userAddr, ok1 := data["user"].(string)
    userIDHex, ok2 := data["user_id"].(string)
    registryID, ok3 := data["registry_id"].(string)
    log.Printf("🔔 [DEBUG] NewUser event caught: user=%s user_id=%s registry_id=%s\n\n", userAddr, userIDHex, registryID)
    if !ok1 || !ok2 || !ok3 {
        return fmt.Errorf("InsertNewUser: missing or invalid fields in data map")
    }

    //transaction Begins
    tx, err := db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    //Insert into poc.app_user
    if _, err := tx.Exec(
        `INSERT INTO poc.app_user(address) VALUES ($1) ON CONFLICT DO NOTHING`,
        userAddr,
    ); err != nil {
        return err
    }

    //Insert into poc.registry
    if _, err := tx.Exec(
        `INSERT INTO poc.registry(registry_id, user_id)
         VALUES ($1, (SELECT user_id FROM poc.app_user WHERE address=$2))
         ON CONFLICT DO NOTHING`,
        registryID, userAddr,
    ); err != nil {
        return err
    }

    log.Printf("✅ NewUser written to DB for\n\n", userAddr)
    //Commit
    return tx.Commit()
}




func (db *DB) InsertDeposit(data map[string]interface{},  timeStamp time.Time,  txDigest string) error {
    //Extract and parse fields
    
    userAddr, ok := data["user"].(string)
    if !ok {
        return fmt.Errorf("InsertDeposit: missing user address")
    }
    amountStr, ok := data["amount"].(string)
    if !ok {
        return fmt.Errorf("InsertDeposit: missing amount")
    }

    log.Printf("🔔 [DEBUG] Deposit event caught for user=%v amount=%v\n\n", userAddr, amountStr)

    amount, err := strconv.ParseInt(amountStr, 10, 64)
    if err != nil {
        return err
    }

    // transaction Begin
    tx, err := db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    //Ensure user exists
    if _, err := tx.Exec(
        `INSERT INTO poc.app_user(address) VALUES ($1) ON CONFLICT DO NOTHING`,
        userAddr,
    ); err != nil {
        return err
    }

    //Lookup user_id
    var userID int
    if err := tx.QueryRow(
        `SELECT user_id FROM poc.app_user WHERE address=$1`,
        userAddr,
    ).Scan(&userID); err != nil {
        return err
    }

    //Insert into transaction_history with dedupe on tx_digest
    res, err := tx.Exec(
        `INSERT INTO poc.transaction_history
            (tx_digest, user_id, epoch, amount, size_bytes, tx_type, created_at)
         VALUES ($1, $2, 0, $3, 0, 'fund_wallet', $4)
          ON CONFLICT (tx_digest, blob_obj_id) DO NOTHING`,
        txDigest, userID, amount, timeStamp,
    )
    if err != nil {
        return err
    }

    // Only update wallet balance if new history row created
    if n, _ := res.RowsAffected(); n > 0 {
        if _, err := tx.Exec(
            `INSERT INTO poc.wallet(user_id, balance)
             VALUES ($1, $2)
             ON CONFLICT (user_id) DO UPDATE
               SET balance = poc.wallet.balance + EXCLUDED.balance`,
            userID, amount,
        ); err != nil {
            return err
        }
    }

    log.Printf("✅ Deposit written to DB for\n\n", userAddr)
    //Commit
    return tx.Commit()
}



// InsertManagedBlob upserts a blob record on user_transfer events
func (db *DB) InsertManagedBlob(data map[string]interface{}) error {
    // Extract fields
    ownerAddr, ok := data["owner"].(string)
    if !ok {
        return fmt.Errorf("InsertManagedBlob: missing owner")
    }
    blobID, ok := data["blob_obj_id"].(string)
    if !ok {
        return fmt.Errorf("InsertManagedBlob: missing blob_obj_id")
    }
    currentEpochF, ok := data["current_epoch"].(float64)
    if !ok {
        return fmt.Errorf("InsertManagedBlob: missing current_epoch")
    }
    currentEpoch := int(currentEpochF)
    sizeStr, ok := data["size"].(string)
    if !ok {
        return fmt.Errorf("InsertManagedBlob: missing size")
    }
    sizeBytes, err := strconv.ParseInt(sizeStr, 10, 64)
    if err != nil {
        return err
    }
    epochSetF, ok := data["epoch_set"].(float64)
    if !ok {
        return fmt.Errorf("InsertManagedBlob: missing epoch_set")
    }
    epochSet := int(epochSetF)
    cycleEndStr, ok := data["cycle_end"].(string)
    if !ok {
        return fmt.Errorf("InsertManagedBlob: missing cycle_end")
    }
    cycleEnd, err := strconv.ParseInt(cycleEndStr, 10, 64)
    if err != nil {
        return err
    }

    log.Printf(
        "🔔 ManagedBlobs event: owner=%s blob=%s size=%d currentEpoch=%d epochSet=%d cycleEnd=%d\n\n",
        ownerAddr, blobID, sizeBytes, currentEpoch, epochSet, cycleEnd,
    )
    // Begin transaction
    tx, err := db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    // Ensure user exists
    if _, err := tx.Exec(
        `INSERT INTO poc.app_user(address) VALUES ($1) ON CONFLICT DO NOTHING`,
        ownerAddr,
    ); err != nil {
        return err
    }

    // Upsert warlot_stored_file
    _, err = tx.Exec(
        `INSERT INTO poc.warlot_stored_file(
             owner_id, registry_id, blob_obj_id,
             size_bytes, current_epoch, epoch_set,
             cycle_end, origin_id
         ) VALUES (
             (SELECT user_id FROM poc.app_user WHERE address=$1),
             (SELECT registry_id FROM poc.registry WHERE user_id=(SELECT user_id FROM poc.app_user WHERE address=$1)),
             $2, $3, $4, $5, $6,
             (SELECT origin_id FROM poc.blob_origin WHERE name='user_transfer')
         )
         ON CONFLICT (blob_obj_id) DO UPDATE SET
             size_bytes    = EXCLUDED.size_bytes,
             current_epoch = EXCLUDED.current_epoch,
             epoch_set     = EXCLUDED.epoch_set,
             cycle_end     = EXCLUDED.cycle_end,
             origin_id     = EXCLUDED.origin_id;`,
        ownerAddr, blobID, sizeBytes,
        currentEpoch, epochSet, cycleEnd,
    )
    if err != nil {
        return err
    }
    log.Printf("✅ ManagedBlobs written to DB for blob\n\n", blobID)
    return tx.Commit()
}

// InsertPublisherBlob upserts a blob record for publisher-origin events
func (db *DB) InsertPublisherBlob(data map[string]interface{}) error {
    // Extract fields
    ownerAddr, ok := data["owner"].(string)
    if !ok {
        return fmt.Errorf("InsertPublisherBlob: missing owner")
    }
    blobID, ok := data["blob_obj_id"].(string)
    if !ok {
        return fmt.Errorf("InsertPublisherBlob: missing blob_obj_id")
    }
    currentEpochF, ok := data["current_epoch"].(float64)
    if !ok {
        return fmt.Errorf("InsertPublisherBlob: missing current_epoch")
    }
    currentEpoch := int(currentEpochF)
    sizeStr, ok := data["size"].(string)
    if !ok {
        return fmt.Errorf("InsertPublisherBlob: missing size")
    }
    sizeBytes, err := strconv.ParseInt(sizeStr, 10, 64)
    if err != nil {
        return err
    }
    epochSetF, ok := data["epoch_set"].(float64)
    if !ok {
        return fmt.Errorf("InsertPublisherBlob: missing epoch_set")
    }
    epochSet := int(epochSetF)
    cycleEndStr, ok := data["cycle_end"].(string)
    if !ok {
        return fmt.Errorf("InsertPublisherBlob: missing cycle_end")
    }
    cycleEnd, err := strconv.ParseInt(cycleEndStr, 10, 64)
    if err != nil {
        return err
    }

    log.Printf(
        "🔔 WarlotFileStore: owner=%s blob=%s size=%d currentEpoch=%d epochSet=%d cycleEnd=%d\n\n",
        ownerAddr, blobID, sizeBytes, currentEpoch, epochSet, cycleEnd,
    )
    // Begin transaction
    tx, err := db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    // Ensure owner exists
    if _, err := tx.Exec(
        `INSERT INTO poc.app_user(address) VALUES ($1) ON CONFLICT DO NOTHING`,
        ownerAddr,
    ); err != nil {
        return err
    }

    // Upsert warlot_stored_file with publisher origin
    _, err = tx.Exec(
        `INSERT INTO poc.warlot_stored_file(
             owner_id, registry_id, blob_obj_id,
             size_bytes, current_epoch, epoch_set,
             cycle_end, origin_id
         ) VALUES (
             (SELECT user_id FROM poc.app_user WHERE address=$1),
             (SELECT registry_id FROM poc.registry WHERE user_id=(SELECT user_id FROM poc.app_user WHERE address=$1)),
             $2, $3, $4, $5, $6,
             (SELECT origin_id FROM poc.blob_origin WHERE name='publisher')
         )
         ON CONFLICT (blob_obj_id) DO UPDATE SET
             size_bytes    = EXCLUDED.size_bytes,
             current_epoch = EXCLUDED.current_epoch,
             epoch_set     = EXCLUDED.epoch_set,
             cycle_end     = EXCLUDED.cycle_end,
             origin_id     = EXCLUDED.origin_id;`,
        ownerAddr, blobID, sizeBytes,
        currentEpoch, epochSet, cycleEnd,
    )
    if err != nil {
        return err
    }

    log.Printf("✅ WarlotFileStore written to DB for blob\n\n", blobID)
    return tx.Commit()
}



// InsertRenewDigest handles renew digest events: logs and subtracts balance
type renewData struct {
    TxDigest   string
    UserAddr   string
    BlobID     string
    EpochVal   int
    AmountVal  int64
    SizeBytes  int64
}

func (db *DB) InsertRenewDigest(data map[string]interface{}, timeStamp time.Time, txDigest string) error {
    // Extract and parse
  
    userAddr, ok := data["user"].(string)
    if !ok {
        return fmt.Errorf("InsertRenewDigest: missing user")
    }
    blobID, ok := data["blob_obj_id"].(string)
    if !ok {
        return fmt.Errorf("InsertRenewDigest: missing blob_obj_id")
    }
    epochF, ok := data["epoch"].(float64)
    if !ok {
        return fmt.Errorf("InsertRenewDigest: missing epoch")
    }
    epochVal := int(epochF)
    amountStr, ok := data["amount"].(string)
    if !ok {
        return fmt.Errorf("InsertRenewDigest: missing amount")
    }
    amountVal, err := strconv.ParseInt(amountStr, 10, 64)
    if err != nil {
        return err
    }
    sizeStr, ok := data["size"].(string)
    if !ok {
        return fmt.Errorf("InsertRenewDigest: missing size")
    }
    sizeBytes, err := strconv.ParseInt(sizeStr, 10, 64)
    if err != nil {
        return err
    }


    log.Printf(
        "🔔 RenewDigest: user=%s blob=%s epoch=%d amount=%d size=%d\n\n",
        userAddr, blobID, epochVal, amountVal, sizeBytes,
    )

    // Begin transaction
    tx, err := db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    // Ensure user exists
    if _, err := tx.Exec(
        `INSERT INTO poc.app_user(address) VALUES ($1) ON CONFLICT DO NOTHING`,
        userAddr,
    ); err != nil {
        return err
    }

    // Lookup user_id
    var userID int
    if err := tx.QueryRow(
        `SELECT user_id FROM poc.app_user WHERE address=$1`,
        userAddr,
    ).Scan(&userID); err != nil {
        return err
    }

    // Insert history with dedupe on tx_digest
    res, err := tx.Exec(
        `INSERT INTO poc.transaction_history
            (tx_digest, user_id, registry_id, blob_obj_id,
             epoch, amount, size_bytes, tx_type, created_at)
         VALUES ($1, $2,
                 (SELECT registry_id FROM poc.registry WHERE user_id=$2),
                 $3, $4, $5, $6, 'renew_digest', $7)
         ON CONFLICT (tx_digest, blob_obj_id) DO NOTHING`,
        txDigest, userID, blobID, epochVal, amountVal, sizeBytes, timeStamp,
    )
    if err != nil {
        return err
    }

    // Update wallet only if new history row inserted
    if n, _ := res.RowsAffected(); n > 0 {
        if _, err := tx.Exec(
            `UPDATE poc.wallet
                SET balance = balance - $1
             WHERE user_id = $2`,
            amountVal, userID,
        ); err != nil {
            return err
        }
    }

    log.Println("✅ RenewDigest written to DB for user\n\n", userAddr)
    return tx.Commit()
}



// InsertBlobUpdate updates only the current_epoch of an existing blob
func (db *DB) InsertBlobUpdate(data map[string]interface{}) error {
    blobID, ok := data["blob_obj_id"].(string)
    if !ok {
        return fmt.Errorf("InsertBlobUpdate: missing blob_obj_id")
    }
    epochF, ok := data["current_epoch"].(float64)
    if !ok {
        return fmt.Errorf("InsertBlobUpdate: missing current_epoch")
    }
    newEpoch := int(epochF)

    log.Printf(
        "🔔 BlobUpdate:  blob=%s newCurrentEpoch=%d\n\n",
        blobID, newEpoch,
    )
    _, err := db.Exec(`
        UPDATE poc.warlot_stored_file
           SET current_epoch = $1
         WHERE blob_obj_id   = $2
    `, newEpoch, blobID)

    log.Printf("✅ BlobUpdate processed for blob\n\n", blobID)
    return err
}




// InsertWithdrawBlob logs a blob removal and deletes the stored file
func (db *DB) InsertWithdrawBlob(data map[string]interface{}, timeStamp time.Time, txDigest string) error {
    // Extract fields
    ownerAddr, ok := data["owner"].(string)
    if !ok {
        return fmt.Errorf("InsertWithdrawBlob: missing owner")
    }
    blobID, ok := data["blob_obj_id"].(string)
    if !ok {
        return fmt.Errorf("InsertWithdrawBlob: missing blob_obj_id")
    }

    log.Printf(
        "🔔 WithdrawBlob: owner=%s blob=%s\n\n",
        ownerAddr, blobID,
    )
    // Begin transaction
    tx, err := db.Begin()
    if err != nil {
        return err
    }
    defer tx.Rollback()

    // Ensure user exists
    if _, err := tx.Exec(
        `INSERT INTO poc.app_user(address) VALUES ($1) ON CONFLICT DO NOTHING`,
        ownerAddr,
    ); err != nil {
        return err
    }

    // Lookup user_id and registry_id
    var userID int
    if err := tx.QueryRow(
        `SELECT user_id FROM poc.app_user WHERE address=$1`,
        ownerAddr,
    ).Scan(&userID); err != nil {
        return err
    }
    var registryID sql.NullString
    _ = tx.QueryRow(
        `SELECT registry_id FROM poc.registry WHERE user_id=$1`,
        userID,
    ).Scan(&registryID)

    // Fetch current_epoch & size_bytes before deletion
    var currentEpoch int
    var sizeBytes int64
    if err := tx.QueryRow(
        `SELECT current_epoch, size_bytes
           FROM poc.warlot_stored_file
          WHERE blob_obj_id = $1`,
        blobID,
    ).Scan(&currentEpoch, &sizeBytes); err != nil {
        return err
    }

    // Insert transaction_history with dedupe on tx_digest
    res, err := tx.Exec(
        `INSERT INTO poc.transaction_history
            (tx_digest, user_id, registry_id, blob_obj_id,
             epoch, amount, size_bytes, tx_type, created_at)
         VALUES ($1, $2, $3, $4, $5, 0, $6, 'blob_removal', $7)
          ON CONFLICT (tx_digest, blob_obj_id) DO NOTHING`,
        txDigest, userID, registryID, blobID, currentEpoch, sizeBytes, timeStamp,
    )
    if err != nil {
        return err
    }

    // Only delete if new history row inserted
    if n, _ := res.RowsAffected(); n > 0 {
        if _, err := tx.Exec(
            `DELETE FROM poc.warlot_stored_file WHERE blob_obj_id = $1`,
            blobID,
        ); err != nil {
            return err
        }
    }

    log.Printf("✅ WithdrawBlob processed for blob %s", blobID)
    return tx.Commit()
}
