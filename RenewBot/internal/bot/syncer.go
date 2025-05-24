package bot

import (
	"database/sql"
	"fmt"
	"log"

	"github.com/steven3002/warlot/RenewBot/internal/db"
	"github.com/steven3002/warlot/RenewBot/internal/mailer"
	"github.com/steven3002/warlot/RenewBot/internal/sui"
)

// syncAccumulator tracks per-address totals for one epoch set
type syncAccumulator struct {
	balance   int64
	totalCost int64
}

type deficiency struct {
	needed  int64 // total missing funds across all sets
	balance int64 // (you can keep the last‐seen balance, or initial balance—up to you)
}

// RunSync scans per-blob rows, accumulates cost per address+set, then processes each
func RunSync(blobDB, userDB *sql.DB) {
	log.Println("🔄 30-minute sync pass start")
	// ratePerBytePerEpoch, err =:
	//Prepare accumulators: map[epochSet]map[address]*syncAccumulator
	accs := make(map[int]map[string]*syncAccumulator, len(EpochSets))
	// this is to accumulate the total of the funds needed to sync

	Insufficient := make(map[string]deficiency)

	for _, set := range EpochSets {
		accs[set] = make(map[string]*syncAccumulator)
	}

	// 2) Scan every blob row
	rows, err := blobDB.Query(`
        SELECT
          u.address,
          w.current_epoch,
          w.epoch_set,
          w.encoded_size,
          wlt.balance
        FROM poc.warlot_stored_file w
        JOIN poc.app_user u   ON u.user_id   = w.owner_id
        JOIN poc.wallet   wlt ON wlt.user_id = u.user_id
    `)
	if err != nil {
		log.Println("sync query error:", err)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var (
			addr    string
			curr    int
			set     int
			enSize  int64
			balance int64
		)
		if err := rows.Scan(&addr, &curr, &set, &enSize, &balance); err != nil {
			log.Println("sync scan error:", err)
			continue
		}

		// Only blobs needing sync: current < queued target
		target, ok := syncQueue[set]
		if !ok || uint64(curr) >= target {
			continue
		}

		//Compute cost for this blob
		epochsToBump := uint64(target) - uint64(curr)

		cost := ComputeCost(uint64(enSize), epochsToBump, ratePerBytePerEpoch)

		//  Accumulate into the map
		m := accs[set]
		if acc, exists := m[addr]; exists {
			acc.totalCost += cost
			acc.balance = balance // same for each row
		} else {
			m[addr] = &syncAccumulator{
				balance:   balance,
				totalCost: cost,
			}
		}
	}
	if err := rows.Err(); err != nil {
		log.Println("row iteration error:", err)
	}

	// Process each accumulator: email or ready
	for _, set := range EpochSets {
		ready := []string{}
		for addr, acc := range accs[set] {
			if acc.balance < acc.totalCost {
				d, exists := Insufficient[addr]

				if exists {
					// add on to whatever shortfall we already have
					d.needed += acc.totalCost
				} else {
					// first time we see this addr short
					d = deficiency{
						needed:  acc.totalCost,
						balance: acc.balance,
					}
				}
				Insufficient[addr] = d
				// once-per-day low-balance email
			} else {
				// enough balance
				ready = append(ready, addr)
			}
		}

		// Log ready list for this set
		if len(ready) > 0 {
			// sync the blobs
			sui.SyncBlob(ready, uint64(set), syncQueue[set])
			fmt.Printf("✅ Ready to sync epoch_set=%d for %d addresses: %v\n",
				set, len(ready), ready)
		}
	}

	for addr, d := range Insufficient {
		name, email, err := db.GetUserInfo(userDB, addr)
		if err != nil {
			log.Println("user lookup failed:", err)
			continue
		}
		log.Printf("❌ Insufficient balance for %s (%s): needs %d, has %d\n",
			name, addr, d.needed, d.balance)

		shouldNotify, err := db.ShouldNotify(userDB, addr)
		if err != nil {
			log.Println("notification-check failed:", err)
			continue
		}
		if shouldNotify {
			log.Printf("📨 Sending daily notification to %s\n", addr)
			mailer.SendFailureEmail(name, addr, email, uint64(d.needed), uint64(d.balance), 0, 2)
		} else {
			log.Printf("🔇 Already notified %s today; skipping\n", addr)
		}
	}

}

func CeilDivBytesToMB(sizeBytes uint64) uint64 {
	const mb = 1024 * 1024
	return (sizeBytes + mb - 1) / mb
}

func ComputeCost(
	encodedSize uint64, //  w.encoded_size
	epochsToBump uint64, // number of epochs
	ratePerBytePerEpoch uint64, // rate
) int64 {
	mbChunks := CeilDivBytesToMB(encodedSize)
	// safe to cast mbChunks and epochsToBump to int64 as long as their
	// product stays within int64 limits
	return int64(epochsToBump * mbChunks * ratePerBytePerEpoch)
}
