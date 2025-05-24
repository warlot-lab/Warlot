package renewal

import (
	"database/sql"
	"log"

	"github.com/steven3002/warlot/RenewBot/internal/db"
	"github.com/steven3002/warlot/RenewBot/internal/mailer"
	"github.com/steven3002/warlot/RenewBot/internal/sui"
)

type BlobRenewal struct {
	Address        string
	TotalEpochDiff int64
	RequiredFunds  int64
	Balance        int64
	HasSufficient  bool
}

func CheckAndRenew(epoch int, walrusEpoch uint64, storageCost uint64, blobDB, userDB *sql.DB) {
	bases := []int{13, 23, 53}

	log.Printf("this is in check and renew: %v", walrusEpoch)
	for _, base := range bases {

		if epoch%(base-1) != 0 {
			continue
		}
		var users []string
		log.Printf("🚀 Running renewal check for epoch %d (base %d)\n", epoch, base)

		rows, err := blobDB.Query(`
            SELECT
              u.address,
              SUM($2 + w.epoch_set - w.current_epoch)                                         AS total_epoch_diff,
              SUM(($2 + w.epoch_set - w.current_epoch) * CEIL(w.encoded_size::numeric / (1024 * 1024)) * $3) AS required_funds,
              wlt.balance,
              (wlt.balance >= SUM(($2 + w.epoch_set - w.current_epoch) * CEIL(w.encoded_size/ (1024 * 1024)) * $3)) AS has_sufficient
            FROM poc.warlot_stored_file AS w
            JOIN poc.app_user      AS u   ON u.user_id   = w.owner_id
            JOIN poc.wallet        AS wlt ON wlt.user_id = u.user_id
            WHERE w.epoch_set = $1
            GROUP BY u.address, wlt.balance
            ORDER BY u.address;
        `, base, int(walrusEpoch), int(storageCost))
		if err != nil {
			log.Println("DB Query Error:", err)
			return
		}
		defer rows.Close()

		for rows.Next() {
			var b BlobRenewal
			if err := rows.Scan(
				&b.Address,
				&b.TotalEpochDiff,
				&b.RequiredFunds,
				&b.Balance,
				&b.HasSufficient,
			); err != nil {
				log.Println("Scan Error:", err)
				continue
			}

			if !b.HasSufficient {
				// Lookup user name & email

				name, email, err := db.GetUserInfo(userDB, b.Address)

				if err != nil {
					log.Println("User lookup failed:", err)
					continue
				}

				log.Printf("❌ Insufficient balance for %s (%s): needs %d, has %d\n",
					name, b.Address, b.RequiredFunds, b.Balance)
				log.Printf("📨 Sending daily notification to %s\n %s", b.Address, email)
				mailer.SendFailureEmail(name, b.Address, email, uint64(b.RequiredFunds), uint64(b.Balance), base, 1)

			} else {
				log.Printf("✅ Sufficient balance for %s (needs %d, has %d)\n",
					b.Address, b.RequiredFunds, b.Balance)
				users = append(users, b.Address)

			}
		}
		if len(users) > 0 {
			sui.RenewBlob(users, uint64(base))
		}
		if err := rows.Err(); err != nil {
			log.Println("Row iteration error:", err)
		}

	}
}
