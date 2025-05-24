package renewal

import "log"

// Epoch sets to track
var EpochSets = []int{13, 23, 53}

// syncQueue maps epoch_set → next Walrus epoch to sync to
var syncQueue = make(map[int]uint64)

// EnqueueNext schedules walrusEpoch + set for the given epoch set
func EnqueueNext(set int, walrusEpoch uint64) {
    target := walrusEpoch + uint64(set)
    syncQueue[set] = target
    log.Printf("📥 Queued next Walrus renewal for set %d: targetEpoch=%d\n", set, target)
}

// GetQueuedTarget returns the queued target epoch for a set (0 if none)
func GetQueuedTarget(set int) uint64 {
    return syncQueue[set]
}
