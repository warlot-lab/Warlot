package bot

import (
	"fmt"
	"time"

	"github.com/steven3002/warlot/RenewBot/internal/sui"
)

// EpochSets are the renewal cycles you care about
var EpochSets = []int{13, 23, 53}

// syncQueue maps each epoch_set → the next Walrus‐based target epoch
var syncQueue = make(map[int]uint64)

var ratePerBytePerEpoch uint64
var currentWalrusEpoch uint64

type EpochScheduler struct {
	EpochDuration    time.Duration
	IntervalDuration time.Duration
	OnEpochTrigger   func(epoch int, walrusEpoch uint64, storageCost uint64)
	OnIntervalTick   func(epoch int)
}

func NewEpochScheduler() *EpochScheduler {
	return &EpochScheduler{
		EpochDuration:    24 * time.Hour,        // 1 day
		IntervalDuration: (24 * time.Hour) / 48, // 48 intervals in a day (each 30 minutes)

	}
}

// EnqueueNext captures walrusEpoch+set in the queue and prints the current map
func EnqueueNext(set int, walrusEpoch uint64) {
	target := walrusEpoch + uint64(set)
	syncQueue[set] = target

	// Print the entire queue so you can confirm
	fmt.Printf("📥 Enqueued for set %d → target %d; current queue: %v\n",
		set, target, syncQueue)
}

func (es *EpochScheduler) Start() {
	epochTicker := time.NewTicker(es.EpochDuration)
	intervalTicker := time.NewTicker(es.IntervalDuration)
	defer epochTicker.Stop()
	defer intervalTicker.Stop()

	walrusEpochx, epoch_costx, err := sui.GetWalrusEpoch()
	if err != nil {
		fmt.Println("❌ failed to fetch Walrus epoch:", err)
	} else {

		ratePerBytePerEpoch = epoch_costx
		currentWalrusEpoch = walrusEpochx
	}
	// test
	for _, epochCount := range EpochSets {
		syncQueue[epochCount] = uint64(epochCount) + walrusEpochx
	}

	epoch := 11

	for {
		select {
		case <-epochTicker.C:
			epoch++
			fmt.Printf("[Epoch] %d\n", epoch)

			// On every base‐epoch, fetch Walrus epoch and enqueue
			for _, set := range EpochSets {
				if epoch%(set-1) == 0 {
					walrusEpoch, epoch_cost, err := sui.GetWalrusEpoch()
					if err != nil {
						fmt.Println("❌ failed to fetch Walrus epoch:", err)
					} else {
						EnqueueNext(set, walrusEpoch)
						ratePerBytePerEpoch = epoch_cost
						currentWalrusEpoch = walrusEpoch
					}
				}
			}

			// Fire  renewal logic
			if es.OnEpochTrigger != nil {
				es.OnEpochTrigger(epoch, currentWalrusEpoch, ratePerBytePerEpoch)
			}

		case <-intervalTicker.C:
			fmt.Printf("[Interval] 30-minute tick at bot-epoch %d; queue: %v\n", epoch, syncQueue)
			if es.OnIntervalTick != nil {
				es.OnIntervalTick(epoch)
			}
		}
	}
}
