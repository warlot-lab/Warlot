package main

import (
	"log"

	"github.com/joho/godotenv"
	"github.com/steven3002/warlot/RenewBot/internal/bot"
	"github.com/steven3002/warlot/RenewBot/internal/db"
	"github.com/steven3002/warlot/RenewBot/internal/renewal"
)

func main() {

	_ = godotenv.Load()
	blobDB, err := db.ConnectBlobDB()
	if err != nil {
		log.Fatalf("blob DB error: %v", err)
	}
	defer blobDB.Close()

	userDB, err := db.ConnectUserDB()
	if err != nil {
		log.Fatalf("user DB error: %v", err)
	}
	defer userDB.Close()

	scheduler := bot.NewEpochScheduler()

	// Existing renewal on base epochs
	scheduler.OnEpochTrigger = func(epoch int, walrusEpoch uint64, ratePerBytePerEpoch uint64) {
		renewal.CheckAndRenew(epoch, walrusEpoch, ratePerBytePerEpoch, blobDB, userDB)
	}

	scheduler.OnIntervalTick = func(_ int) {
		bot.RunSync(blobDB, userDB)
	}

	log.Println("🚀 Starting Warlot Renewal Bot scheduler...")
	scheduler.Start()
}
